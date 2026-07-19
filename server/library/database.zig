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
    track_id: [36]u8,
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

pub fn newTrackId(io: std.Io) [36]u8 {
    var bytes: [16]u8 = undefined;
    io.random(&bytes);
    return trackIdFromBytes(bytes);
}

/// Converts 128 input bits into a canonical lowercase UUIDv4 string.
///
/// UUID version and variant are bit fields inside the 16-byte value; they are
/// not whole bytes. The version occupies the high four bits of byte 6. UUIDv4
/// requires those bits to be `0100`, so the low four random bits are preserved.
/// The variant occupies the high bits of byte 8. The standard RFC 4122/9562
/// UUID layout requires the prefix `10`, distinguishing it from older or
/// reserved UUID layouts, so the remaining six random bits are preserved.
pub fn trackIdFromBytes(input: [16]u8) [36]u8 {
    var bytes = input;
    // xxxx xxxx -> 0100 xxxx: UUID version 4 in byte 6's high nibble.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // xxxx xxxx -> 10xx xxxx: standard UUID variant in byte 8's high bits.
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    const hex = std.fmt.bytesToHex(bytes, .lower);
    var uuid: [36]u8 = undefined;
    @memcpy(uuid[0..8], hex[0..8]);
    uuid[8] = '-';
    @memcpy(uuid[9..13], hex[8..12]);
    uuid[13] = '-';
    @memcpy(uuid[14..18], hex[12..16]);
    uuid[18] = '-';
    @memcpy(uuid[19..23], hex[16..20]);
    uuid[23] = '-';
    @memcpy(uuid[24..36], hex[20..32]);
    return uuid;
}

pub fn isTrackId(value: []const u8) bool {
    if (value.len != 36) return false;
    for (value, 0..) |char, index| {
        if (index == 8 or index == 13 or index == 18 or index == 23) {
            if (char != '-') return false;
        } else if (!std.ascii.isHex(char)) {
            return false;
        }
    }
    // In 8-4-4-4-12 UUID text, index 14 is the version nibble and must be 4.
    // Index 19 is the variant nibble. A binary `10xx` prefix is hexadecimal
    // 8, 9, a, or b, which identifies the standard RFC UUID layout.
    return value[14] == '4' and
        (value[19] == '8' or value[19] == '9' or
            value[19] == 'a' or value[19] == 'b');
}

pub const FileState = struct {
    size: u64,
    modified_ns: i64,
};

pub const Track = struct {
    id: []u8,
    cursor: i64,
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
        allocator.free(self.id);
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

pub const TrackSource = struct {
    path: []u8,

    pub fn deinit(self: *TrackSource, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
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
        get_track_source: *const fn (
            context: *anyopaque,
            allocator: std.mem.Allocator,
            track_id: []const u8,
        ) Error!?TrackSource,
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

    pub fn getTrackSource(
        self: Database,
        allocator: std.mem.Allocator,
        track_id: []const u8,
    ) Error!?TrackSource {
        return self.vtable.get_track_source(
            self.context,
            allocator,
            track_id,
        );
    }
};

test "Database is a small type-erased handle" {
    try std.testing.expectEqual(@sizeOf(*anyopaque) * 2, @sizeOf(Database));
}

test "new track IDs are UUID v4 values" {
    const id = newTrackId(std.testing.io);
    try std.testing.expect(isTrackId(&id));
    try std.testing.expectEqual(@as(u8, '4'), id[14]);
}
