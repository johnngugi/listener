const std = @import("std");

/// Errors shared by every library database implementation.
pub const Error = error{
    DatabaseBusy,
    DatabaseConstraint,
    DatabaseOpenFailed,
    DatabaseOperationFailed,
    InvalidScan,
    OutOfMemory,
};

pub const Scan = struct {
    id: i64,
    root_id: i64,
};

pub const ScannedArtwork = struct {
    sha256: [32]u8,
    mime_type: []const u8,
    width: u32,
    height: u32,
    byte_length: u64,
    storage_key: []const u8,
};

pub const Artwork = struct {
    id: i64,
    mime_type: []u8,
    width: u32,
    height: u32,
    byte_length: u64,
    storage_key: []u8,

    pub fn deinit(self: *Artwork, allocator: std.mem.Allocator) void {
        allocator.free(self.mime_type);
        allocator.free(self.storage_key);
        self.* = undefined;
    }
};

/// The filesystem facts needed to identify a new or changed library file.
/// All slices are borrowed for the duration of a database call.
pub const ScannedFile = struct {
    path: []const u8,
    size: u64,
    modified_ns: i64,
    title: ?[]const u8,
    track_artist: ?[]const u8,
    album_artist: ?[]const u8,
    album: ?[]const u8,
    track_number: ?u16,
    disc_number: ?u16,
    release_date: ?[]const u8,
    duration_ms: ?u64,
    codec: []const u8,
    sample_rate: u32,
    bits_per_sample: u8,
    artwork_id: ?i64 = null,
};

pub const FileState = struct {
    size: u64,
    modified_ns: i64,
};

pub const Track = struct {
    id: i64,
    path: []u8,
    size: u64,
    modified_ns: i64,
    title: ?[]u8,
    track_artist: ?[]u8,
    album_artist: ?[]u8,
    album: ?[]u8,
    track_number: ?u16,
    disc_number: ?u16,
    release_date: ?[]u8,
    duration_ms: ?u64,
    codec: []u8,
    sample_rate: u32,
    bits_per_sample: u8,
    date_added: i64,
    artwork_id: ?i64 = null,

    pub fn deinit(self: *Track, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        freeOptional(allocator, self.title);
        freeOptional(allocator, self.track_artist);
        freeOptional(allocator, self.album_artist);
        freeOptional(allocator, self.album);
        freeOptional(allocator, self.release_date);
        allocator.free(self.codec);
        self.* = undefined;
    }
};

pub const TrackPage = struct {
    tracks: []Track,
    total_size: u64,
    has_more: bool,

    pub fn deinit(self: *TrackPage, allocator: std.mem.Allocator) void {
        for (self.tracks) |*track| track.deinit(allocator);
        allocator.free(self.tracks);
        self.* = undefined;
    }
};

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |text| allocator.free(text);
}

/// A storage-neutral interface for library scanning and browsing.
///
/// This interface deliberately exposes library operations instead of SQL. A
/// different implementation can therefore use another database without
/// teaching the scanner about statements, bindings, or transactions.
pub const Database = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (context: *anyopaque) void,
        migrate: *const fn (context: *anyopaque) Error!void,
        begin_scan: *const fn (context: *anyopaque, root_path: []const u8) Error!Scan,
        find_file: *const fn (context: *anyopaque, scan: Scan, path: []const u8) Error!?FileState,
        upsert_files: *const fn (context: *anyopaque, scan: Scan, files: []const ScannedFile) Error!void,
        upsert_artwork: *const fn (context: *anyopaque, scan: Scan, artwork: ScannedArtwork) Error!i64,
        get_artwork: *const fn (
            context: *anyopaque,
            allocator: std.mem.Allocator,
            artwork_id: i64,
        ) Error!?Artwork,
        finish_scan: *const fn (context: *anyopaque, scan: Scan) Error!void,
        abort_scan: *const fn (context: *anyopaque, scan: Scan) void,
        list_tracks: *const fn (
            context: *anyopaque,
            allocator: std.mem.Allocator,
            after_id: i64,
            limit: u32,
        ) Error!TrackPage,
    };

    pub fn deinit(self: *Database) void {
        self.vtable.deinit(self.context);
        self.* = undefined;
    }

    pub fn migrate(self: Database) Error!void {
        return self.vtable.migrate(self.context);
    }

    pub fn beginScan(self: Database, root_path: []const u8) Error!Scan {
        return self.vtable.begin_scan(self.context, root_path);
    }

    pub fn findFile(self: Database, scan: Scan, path: []const u8) Error!?FileState {
        return self.vtable.find_file(self.context, scan, path);
    }

    pub fn upsertFiles(self: Database, scan: Scan, files: []const ScannedFile) Error!void {
        return self.vtable.upsert_files(self.context, scan, files);
    }

    pub fn upsertArtwork(self: Database, scan: Scan, artwork: ScannedArtwork) Error!i64 {
        return self.vtable.upsert_artwork(self.context, scan, artwork);
    }

    pub fn getArtwork(
        self: Database,
        allocator: std.mem.Allocator,
        artwork_id: i64,
    ) Error!?Artwork {
        return self.vtable.get_artwork(self.context, allocator, artwork_id);
    }

    /// Completes a successful scan and removes rows under this root that were
    /// not observed during it.
    pub fn finishScan(self: Database, scan: Scan) Error!void {
        return self.vtable.finish_scan(self.context, scan);
    }

    /// Aborting never removes files that were absent from a partial scan.
    pub fn abortScan(self: Database, scan: Scan) void {
        self.vtable.abort_scan(self.context, scan);
    }

    pub fn listTracks(
        self: Database,
        allocator: std.mem.Allocator,
        after_id: i64,
        limit: u32,
    ) Error!TrackPage {
        return self.vtable.list_tracks(self.context, allocator, after_id, limit);
    }
};

test "Database is a small type-erased handle" {
    try std.testing.expectEqual(@sizeOf(*anyopaque) * 2, @sizeOf(Database));
}
