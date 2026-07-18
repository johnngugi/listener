const std = @import("std");
const database = @import("database.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const OpenOptions = struct {
    create: bool = true,
    busy_timeout_ms: c_int = 5_000,
};

const schema =
    \\PRAGMA foreign_keys = ON;
    \\CREATE TABLE IF NOT EXISTS library_roots (
    \\    id INTEGER PRIMARY KEY,
    \\    path TEXT NOT NULL UNIQUE
    \\);
    \\CREATE TABLE IF NOT EXISTS library_scans (
    \\    id INTEGER PRIMARY KEY,
    \\    root_id INTEGER NOT NULL REFERENCES library_roots(id) ON DELETE CASCADE,
    \\    started_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    completed_at INTEGER
    \\);
    \\CREATE TABLE IF NOT EXISTS artworks (
    \\    id INTEGER PRIMARY KEY,
    \\    sha256 BLOB NOT NULL UNIQUE CHECK (length(sha256) = 32),
    \\    mime_type TEXT NOT NULL,
    \\    width INTEGER NOT NULL CHECK (width > 0),
    \\    height INTEGER NOT NULL CHECK (height > 0),
    \\    byte_length INTEGER NOT NULL CHECK (byte_length > 0),
    \\    storage_key TEXT NOT NULL UNIQUE
    \\);
    \\CREATE TABLE IF NOT EXISTS tracks (
    \\    id INTEGER PRIMARY KEY,
    \\    root_id INTEGER NOT NULL REFERENCES library_roots(id) ON DELETE CASCADE,
    \\    path TEXT NOT NULL,
    \\    size INTEGER NOT NULL CHECK (size >= 0),
    \\    modified_ns INTEGER NOT NULL,
    \\    title TEXT,
    \\    track_artist TEXT,
    \\    album_artist TEXT,
    \\    album TEXT,
    \\    track_number INTEGER,
    \\    disc_number INTEGER,
    \\    release_date TEXT,
    \\    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
    \\    codec TEXT NOT NULL,
    \\    sample_rate INTEGER NOT NULL CHECK (sample_rate >= 0),
    \\    bits_per_sample INTEGER NOT NULL CHECK (bits_per_sample >= 0),
    \\    artwork_id INTEGER REFERENCES artworks(id) ON DELETE SET NULL,
    \\    date_added INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    last_seen_scan_id INTEGER NOT NULL,
    \\    UNIQUE (root_id, path)
    \\);
    \\CREATE INDEX IF NOT EXISTS tracks_last_seen_idx
    \\    ON tracks(root_id, last_seen_scan_id);
    \\CREATE INDEX IF NOT EXISTS tracks_artwork_idx
    \\    ON tracks(artwork_id);
;

const Sqlite = struct {
    allocator: std.mem.Allocator,
    handle: *c.sqlite3,

    fn fromContext(context: *anyopaque) *Sqlite {
        return @ptrCast(@alignCast(context));
    }

    fn deinit(context: *anyopaque) void {
        const self = fromContext(context);
        _ = c.sqlite3_close_v2(self.handle);
        self.allocator.destroy(self);
    }

    fn migrate(context: *anyopaque) database.Error!void {
        const self = fromContext(context);
        try self.exec(schema);
    }

    fn beginScan(context: *anyopaque, root_path: []const u8) database.Error!database.Scan {
        const self = fromContext(context);
        try self.exec("BEGIN IMMEDIATE");
        errdefer self.rollback();

        var root_stmt = try self.prepare(
            "INSERT INTO library_roots(path) VALUES (?1) " ++
                "ON CONFLICT(path) DO UPDATE SET path=excluded.path " ++
                "RETURNING id",
        );
        defer root_stmt.deinit();

        try root_stmt.bindText(1, root_path);
        if (try root_stmt.step() != .row) return error.DatabaseOperationFailed;

        const root_id = root_stmt.columnI64(0);
        if (try root_stmt.step() != .done) return error.DatabaseOperationFailed;

        var scan_stmt = try self.prepare(
            "INSERT INTO library_scans(root_id) VALUES (?1) RETURNING id",
        );
        defer scan_stmt.deinit();

        try scan_stmt.bindI64(1, root_id);
        if (try scan_stmt.step() != .row) return error.DatabaseOperationFailed;

        const scan_id = scan_stmt.columnI64(0);
        if (try scan_stmt.step() != .done) return error.DatabaseOperationFailed;

        try self.exec("COMMIT");
        return .{ .id = scan_id, .root_id = root_id };
    }

    fn findFile(
        context: *anyopaque,
        scan: database.Scan,
        path: []const u8,
    ) database.Error!?database.FileState {
        const self = fromContext(context);
        var stmt = try self.prepare(
            "SELECT size, modified_ns FROM tracks WHERE root_id=?1 AND path=?2",
        );
        defer stmt.deinit();

        try stmt.bindI64(1, scan.root_id);
        try stmt.bindText(2, path);

        return switch (try stmt.step()) {
            .done => null,
            .row => .{
                .size = @intCast(stmt.columnI64(0)),
                .modified_ns = stmt.columnI64(1),
            },
        };
    }

    fn upsertFiles(
        context: *anyopaque,
        scan: database.Scan,
        files: []const database.ScannedFile,
    ) database.Error!void {
        if (files.len == 0) return;

        const self = fromContext(context);

        try self.requireOpenScan(scan);
        try self.exec("BEGIN IMMEDIATE");
        errdefer self.rollback();

        var stmt = try self.prepare(
            "INSERT INTO tracks(" ++
                "root_id, path, size, modified_ns, title, track_artist, " ++
                "album_artist, album, track_number, disc_number, release_date, " ++
                "duration_ms, codec, sample_rate, bits_per_sample, artwork_id, " ++
                "last_seen_scan_id" ++
                ") VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, " ++
                "?12, ?13, ?14, ?15, ?16, ?17) " ++
                "ON CONFLICT(root_id, path) DO UPDATE SET " ++
                "size=excluded.size, modified_ns=excluded.modified_ns, " ++
                "title=excluded.title, track_artist=excluded.track_artist, " ++
                "album_artist=excluded.album_artist, album=excluded.album, " ++
                "track_number=excluded.track_number, disc_number=excluded.disc_number, " ++
                "release_date=excluded.release_date, duration_ms=excluded.duration_ms, " ++
                "codec=excluded.codec, sample_rate=excluded.sample_rate, " ++
                "bits_per_sample=excluded.bits_per_sample, " ++
                "artwork_id=excluded.artwork_id, " ++
                "last_seen_scan_id=excluded.last_seen_scan_id",
        );
        defer stmt.deinit();

        for (files) |file| {
            try stmt.bindI64(1, scan.root_id);
            try stmt.bindText(2, file.path);
            try stmt.bindI64(3, std.math.cast(i64, file.size) orelse return error.DatabaseConstraint);
            try stmt.bindI64(4, file.modified_ns);
            try stmt.bindOptionalText(5, file.title);
            try stmt.bindOptionalText(6, file.track_artist);
            try stmt.bindOptionalText(7, file.album_artist);
            try stmt.bindOptionalText(8, file.album);
            try stmt.bindOptionalI64(9, try optionalInt(file.track_number));
            try stmt.bindOptionalI64(10, try optionalInt(file.disc_number));
            try stmt.bindOptionalText(11, file.release_date);
            try stmt.bindOptionalI64(12, try optionalInt(file.duration_ms));
            try stmt.bindText(13, file.codec);
            try stmt.bindI64(14, file.sample_rate);
            try stmt.bindI64(15, file.bits_per_sample);
            try stmt.bindOptionalI64(16, file.artwork_id);
            try stmt.bindI64(17, scan.id);

            if (try stmt.step() != .done) return error.DatabaseOperationFailed;
            try stmt.reset();
        }

        try self.exec("COMMIT");
    }

    fn upsertArtwork(
        context: *anyopaque,
        scan: database.Scan,
        artwork: database.ScannedArtwork,
    ) database.Error!i64 {
        const self = fromContext(context);

        try self.requireOpenScan(scan);
        try self.exec("BEGIN IMMEDIATE");
        errdefer self.rollback();

        var insert_stmt = try self.prepare(
            "INSERT INTO artworks(" ++
                "sha256, mime_type, width, height, byte_length, storage_key" ++
                ") VALUES (?1, ?2, ?3, ?4, ?5, ?6) " ++
                "ON CONFLICT(sha256) DO NOTHING",
        );
        defer insert_stmt.deinit();

        try insert_stmt.bindBlob(1, &artwork.sha256);
        try insert_stmt.bindText(2, artwork.mime_type);
        try insert_stmt.bindI64(3, artwork.width);
        try insert_stmt.bindI64(4, artwork.height);
        try insert_stmt.bindI64(
            5,
            std.math.cast(i64, artwork.byte_length) orelse return error.DatabaseConstraint,
        );
        try insert_stmt.bindText(6, artwork.storage_key);

        if (try insert_stmt.step() != .done) return error.DatabaseOperationFailed;

        var find_stmt = try self.prepare(
            "SELECT id FROM artworks WHERE sha256=?1",
        );
        defer find_stmt.deinit();

        try find_stmt.bindBlob(1, &artwork.sha256);
        if (try find_stmt.step() != .row) return error.DatabaseOperationFailed;

        const artwork_id = find_stmt.columnI64(0);
        if (try find_stmt.step() != .done) return error.DatabaseOperationFailed;

        try self.exec("COMMIT");
        return artwork_id;
    }

    fn getArtwork(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        artwork_id: i64,
    ) database.Error!?database.Artwork {
        const self = fromContext(context);
        var stmt = try self.prepare(
            "SELECT id, mime_type, width, height, byte_length, storage_key " ++
                "FROM artworks WHERE id=?1",
        );
        defer stmt.deinit();

        try stmt.bindI64(1, artwork_id);
        if (try stmt.step() == .done) return null;

        const mime_type = try stmt.columnTextAlloc(allocator, 1);
        errdefer allocator.free(mime_type);
        const storage_key = try stmt.columnTextAlloc(allocator, 5);
        errdefer allocator.free(storage_key);

        const width = stmt.columnI64(2);
        const height = stmt.columnI64(3);
        const byte_length = stmt.columnI64(4);
        if (width <= 0 or height <= 0 or byte_length <= 0) {
            return error.DatabaseOperationFailed;
        }

        return .{
            .id = stmt.columnI64(0),
            .mime_type = mime_type,
            .width = std.math.cast(u32, width) orelse return error.DatabaseOperationFailed,
            .height = std.math.cast(u32, height) orelse return error.DatabaseOperationFailed,
            .byte_length = std.math.cast(u64, byte_length) orelse return error.DatabaseOperationFailed,
            .storage_key = storage_key,
        };
    }

    fn finishScan(context: *anyopaque, scan: database.Scan) database.Error!void {
        const self = fromContext(context);

        try self.exec("BEGIN IMMEDIATE");
        errdefer self.rollback();

        try self.requireOpenScan(scan);

        var delete_stmt = try self.prepare(
            "DELETE FROM tracks WHERE root_id=?1 AND last_seen_scan_id<>?2",
        );
        defer delete_stmt.deinit();

        try delete_stmt.bindI64(1, scan.root_id);
        try delete_stmt.bindI64(2, scan.id);
        if (try delete_stmt.step() != .done) return error.DatabaseOperationFailed;

        try self.exec(
            "DELETE FROM artworks WHERE NOT EXISTS (" ++
                "SELECT 1 FROM tracks WHERE tracks.artwork_id=artworks.id" ++
                ")",
        );

        var finish_stmt = try self.prepare(
            "UPDATE library_scans SET completed_at=unixepoch() " ++
                "WHERE id=?1 AND root_id=?2 AND completed_at IS NULL",
        );
        defer finish_stmt.deinit();

        try finish_stmt.bindI64(1, scan.id);
        try finish_stmt.bindI64(2, scan.root_id);
        if (try finish_stmt.step() != .done) return error.DatabaseOperationFailed;

        try self.exec("COMMIT");
    }

    fn abortScan(context: *anyopaque, scan: database.Scan) void {
        const self = fromContext(context);
        var stmt = self.prepare(
            "DELETE FROM library_scans WHERE id=?1 AND root_id=?2 AND completed_at IS NULL",
        ) catch return;
        defer stmt.deinit();
        stmt.bindI64(1, scan.id) catch return;
        stmt.bindI64(2, scan.root_id) catch return;
        _ = stmt.step() catch return;
    }

    fn listTracks(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        after_id: i64,
        limit: u32,
    ) database.Error!database.TrackPage {
        const self = fromContext(context);

        var count_stmt = try self.prepare("SELECT COUNT(*) FROM tracks");
        defer count_stmt.deinit();

        if (try count_stmt.step() != .row) return error.DatabaseOperationFailed;

        const total_count = count_stmt.columnI64(0);
        if (total_count < 0) return error.DatabaseOperationFailed;

        var stmt = try self.prepare(
            "SELECT id, path, size, modified_ns, title, track_artist, " ++
                "album_artist, album, track_number, disc_number, release_date, " ++
                "duration_ms, codec, sample_rate, bits_per_sample, date_added, " ++
                "artwork_id " ++
                "FROM tracks " ++
                "WHERE id>?1 ORDER BY id LIMIT ?2",
        );
        defer stmt.deinit();

        try stmt.bindI64(1, after_id);
        try stmt.bindI64(2, @as(i64, limit) + 1);

        var tracks: std.ArrayList(database.Track) = .empty;
        errdefer {
            for (tracks.items) |*track| track.deinit(allocator);
            tracks.deinit(allocator);
        }

        while (try stmt.step() == .row) {
            const path = try stmt.columnTextAlloc(allocator, 1);
            errdefer allocator.free(path);

            const title = try stmt.columnOptionalTextAlloc(allocator, 4);
            errdefer freeOptional(allocator, title);

            const track_artist = try stmt.columnOptionalTextAlloc(allocator, 5);
            errdefer freeOptional(allocator, track_artist);

            const album_artist = try stmt.columnOptionalTextAlloc(allocator, 6);
            errdefer freeOptional(allocator, album_artist);

            const album = try stmt.columnOptionalTextAlloc(allocator, 7);
            errdefer freeOptional(allocator, album);

            const release_date = try stmt.columnOptionalTextAlloc(allocator, 10);
            errdefer freeOptional(allocator, release_date);

            const codec = try stmt.columnTextAlloc(allocator, 12);
            errdefer allocator.free(codec);

            const size = stmt.columnI64(2);
            const sample_rate = stmt.columnI64(13);
            const bits_per_sample = stmt.columnI64(14);

            if (size < 0 or sample_rate < 0 or bits_per_sample < 0) {
                return error.DatabaseOperationFailed;
            }

            tracks.append(allocator, .{
                .id = stmt.columnI64(0),
                .path = path,
                .size = @intCast(size),
                .modified_ns = stmt.columnI64(3),
                .title = title,
                .track_artist = track_artist,
                .album_artist = album_artist,
                .album = album,
                .track_number = try optionalCast(u16, stmt.columnOptionalI64(8)),
                .disc_number = try optionalCast(u16, stmt.columnOptionalI64(9)),
                .release_date = release_date,
                .duration_ms = try optionalCast(u64, stmt.columnOptionalI64(11)),
                .codec = codec,
                .sample_rate = std.math.cast(u32, sample_rate) orelse
                    return error.DatabaseOperationFailed,
                .bits_per_sample = std.math.cast(u8, bits_per_sample) orelse
                    return error.DatabaseOperationFailed,
                .date_added = stmt.columnI64(15),
                .artwork_id = stmt.columnOptionalI64(16),
            }) catch return error.OutOfMemory;
        }

        const has_more = tracks.items.len > limit;
        if (has_more) {
            var extra = tracks.pop().?;
            extra.deinit(allocator);
        }

        return .{
            .tracks = tracks.toOwnedSlice(allocator) catch return error.OutOfMemory,
            .total_size = @intCast(total_count),
            .has_more = has_more,
        };
    }

    fn requireOpenScan(self: *Sqlite, scan: database.Scan) database.Error!void {
        var stmt = try self.prepare(
            "SELECT 1 FROM library_scans " ++
                "WHERE id=?1 AND root_id=?2 AND completed_at IS NULL",
        );
        defer stmt.deinit();

        try stmt.bindI64(1, scan.id);
        try stmt.bindI64(2, scan.root_id);

        if (try stmt.step() != .row) return error.InvalidScan;
    }

    fn exec(self: *Sqlite, sql: [*:0]const u8) database.Error!void {
        const result = c.sqlite3_exec(self.handle, sql, null, null, null);
        if (result != c.SQLITE_OK) return mapError(result);
    }

    fn rollback(self: *Sqlite) void {
        _ = c.sqlite3_exec(self.handle, "ROLLBACK", null, null, null);
    }

    fn prepare(self: *Sqlite, sql: [*:0]const u8) database.Error!Statement {
        var handle: ?*c.sqlite3_stmt = null;
        const result = c.sqlite3_prepare_v2(self.handle, sql, -1, &handle, null);
        if (result != c.SQLITE_OK) return mapError(result);
        return .{ .handle = handle orelse return error.DatabaseOperationFailed };
    }
};

const Step = enum { row, done };

const Statement = struct {
    handle: *c.sqlite3_stmt,

    fn deinit(self: *Statement) void {
        _ = c.sqlite3_finalize(self.handle);
        self.* = undefined;
    }

    fn bindI64(self: *Statement, index: c_int, value: i64) database.Error!void {
        const result = c.sqlite3_bind_int64(self.handle, index, value);
        if (result != c.SQLITE_OK) return mapError(result);
    }

    fn bindText(self: *Statement, index: c_int, value: []const u8) database.Error!void {
        const length = std.math.cast(c_int, value.len) orelse return error.DatabaseConstraint;
        // A null destructor is SQLITE_STATIC. Every caller steps (and, when
        // reusing a statement, resets) before the borrowed slice can expire.
        // This also avoids SQLite's `(sqlite3_destructor_type)-1` sentinel,
        // which Zig correctly rejects as a potentially misaligned function
        // pointer on ARM.
        const result = c.sqlite3_bind_text(self.handle, index, value.ptr, length, null);
        if (result != c.SQLITE_OK) return mapError(result);
    }

    fn bindBlob(self: *Statement, index: c_int, value: []const u8) database.Error!void {
        const length = std.math.cast(c_int, value.len) orelse return error.DatabaseConstraint;
        const result = c.sqlite3_bind_blob(self.handle, index, value.ptr, length, null);
        if (result != c.SQLITE_OK) return mapError(result);
    }

    fn bindOptionalText(
        self: *Statement,
        index: c_int,
        value: ?[]const u8,
    ) database.Error!void {
        if (value) |text| {
            return self.bindText(index, text);
        }

        if (c.sqlite3_bind_null(self.handle, index) != c.SQLITE_OK) {
            return error.DatabaseOperationFailed;
        }
    }

    fn bindOptionalI64(
        self: *Statement,
        index: c_int,
        value: ?i64,
    ) database.Error!void {
        if (value) |number| {
            return self.bindI64(index, number);
        }

        if (c.sqlite3_bind_null(self.handle, index) != c.SQLITE_OK) {
            return error.DatabaseOperationFailed;
        }
    }

    fn step(self: *Statement) database.Error!Step {
        return switch (c.sqlite3_step(self.handle)) {
            c.SQLITE_ROW => .row,
            c.SQLITE_DONE => .done,
            else => |result| mapError(result),
        };
    }

    fn reset(self: *Statement) database.Error!void {
        const reset_result = c.sqlite3_reset(self.handle);
        if (reset_result != c.SQLITE_OK) return mapError(reset_result);
        const clear_result = c.sqlite3_clear_bindings(self.handle);
        if (clear_result != c.SQLITE_OK) return mapError(clear_result);
    }

    fn columnI64(self: Statement, index: c_int) i64 {
        return c.sqlite3_column_int64(self.handle, index);
    }

    fn columnOptionalI64(self: Statement, index: c_int) ?i64 {
        if (c.sqlite3_column_type(self.handle, index) == c.SQLITE_NULL) return null;

        return self.columnI64(index);
    }

    fn columnTextAlloc(
        self: Statement,
        allocator: std.mem.Allocator,
        index: c_int,
    ) database.Error![]u8 {
        const length = c.sqlite3_column_bytes(self.handle, index);

        if (length < 0) return error.DatabaseOperationFailed;

        const text = c.sqlite3_column_text(self.handle, index) orelse
            return error.DatabaseOperationFailed;

        return allocator.dupe(u8, text[0..@intCast(length)]) catch error.OutOfMemory;
    }

    fn columnOptionalTextAlloc(
        self: Statement,
        allocator: std.mem.Allocator,
        index: c_int,
    ) database.Error!?[]u8 {
        if (c.sqlite3_column_type(self.handle, index) == c.SQLITE_NULL) return null;

        return try self.columnTextAlloc(allocator, index);
    }
};

fn optionalInt(value: anytype) database.Error!?i64 {
    return if (value) |number|
        std.math.cast(i64, number) orelse error.DatabaseConstraint
    else
        null;
}

fn optionalCast(comptime T: type, value: ?i64) database.Error!?T {
    return if (value) |number|
        std.math.cast(T, number) orelse error.DatabaseOperationFailed
    else
        null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |text| allocator.free(text);
}

const vtable: database.Database.VTable = .{
    .deinit = Sqlite.deinit,
    .migrate = Sqlite.migrate,
    .begin_scan = Sqlite.beginScan,
    .find_file = Sqlite.findFile,
    .upsert_files = Sqlite.upsertFiles,
    .upsert_artwork = Sqlite.upsertArtwork,
    .get_artwork = Sqlite.getArtwork,
    .finish_scan = Sqlite.finishScan,
    .abort_scan = Sqlite.abortScan,
    .list_tracks = Sqlite.listTracks,
};

pub fn open(
    allocator: std.mem.Allocator,
    path: [:0]const u8,
    options: OpenOptions,
) database.Error!database.Database {
    const self = allocator.create(Sqlite) catch return error.OutOfMemory;
    errdefer allocator.destroy(self);

    var handle: ?*c.sqlite3 = null;
    var flags: c_int = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_FULLMUTEX;
    if (options.create) flags |= c.SQLITE_OPEN_CREATE;

    const result = c.sqlite3_open_v2(path.ptr, &handle, flags, null);
    if (result != c.SQLITE_OK) {
        if (handle) |opened| _ = c.sqlite3_close_v2(opened);
        return if (result == c.SQLITE_NOMEM) error.OutOfMemory else error.DatabaseOpenFailed;
    }

    self.* = .{ .allocator = allocator, .handle = handle.? };
    errdefer _ = c.sqlite3_close_v2(self.handle);

    if (c.sqlite3_busy_timeout(self.handle, options.busy_timeout_ms) != c.SQLITE_OK) {
        return error.DatabaseOperationFailed;
    }
    try self.exec("PRAGMA foreign_keys=ON");

    return .{ .context = self, .vtable = &vtable };
}

fn mapError(result: c_int) database.Error {
    return switch (result) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.DatabaseBusy,
        c.SQLITE_CONSTRAINT => error.DatabaseConstraint,
        c.SQLITE_NOMEM => error.OutOfMemory,
        else => error.DatabaseOperationFailed,
    };
}

fn testFile(path: []const u8, size: u64, modified_ns: i64) database.ScannedFile {
    return .{
        .path = path,
        .size = size,
        .modified_ns = modified_ns,
        .title = null,
        .track_artist = null,
        .album_artist = null,
        .album = null,
        .track_number = null,
        .disc_number = null,
        .release_date = null,
        .duration_ms = null,
        .codec = "flac",
        .sample_rate = 44_100,
        .bits_per_sample = 16,
    };
}

test "SQLite scan lifecycle upserts files and removes stale rows" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const first = try db.beginScan("/music");
    try db.upsertFiles(first, &.{
        testFile("/music/one.flac", 100, 10),
        testFile("/music/two.flac", 200, 20),
    });
    try db.finishScan(first);

    const second = try db.beginScan("/music");
    const unchanged = (try db.findFile(second, "/music/one.flac")).?;
    try std.testing.expectEqual(@as(u64, 100), unchanged.size);
    try db.upsertFiles(second, &.{
        testFile("/music/one.flac", 101, 11),
    });
    try db.finishScan(second);

    try std.testing.expect((try db.findFile(second, "/music/two.flac")) == null);
    const updated = (try db.findFile(second, "/music/one.flac")).?;
    try std.testing.expectEqual(@as(u64, 101), updated.size);
}

test "artwork is deduplicated by digest and linked to tracks" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const scan = try db.beginScan("/music");
    const artwork = database.ScannedArtwork{
        .sha256 = @splat(0xab),
        .mime_type = "image/jpeg",
        .width = 1_000,
        .height = 1_000,
        .byte_length = 123_456,
        .storage_key = "ab/ab/abababab.jpg",
    };

    const first_id = try db.upsertArtwork(scan, artwork);
    const duplicate_id = try db.upsertArtwork(scan, artwork);
    try std.testing.expectEqual(first_id, duplicate_id);

    var stored_artwork = (try db.getArtwork(std.testing.allocator, first_id)).?;
    defer stored_artwork.deinit(std.testing.allocator);
    try std.testing.expectEqual(first_id, stored_artwork.id);
    try std.testing.expectEqualStrings("image/jpeg", stored_artwork.mime_type);
    try std.testing.expectEqual(@as(u32, 1_000), stored_artwork.width);
    try std.testing.expectEqual(@as(u32, 1_000), stored_artwork.height);
    try std.testing.expectEqual(@as(u64, 123_456), stored_artwork.byte_length);
    try std.testing.expectEqualStrings("ab/ab/abababab.jpg", stored_artwork.storage_key);
    try std.testing.expect((try db.getArtwork(std.testing.allocator, first_id + 1)) == null);

    var file = testFile("/music/song.flac", 100, 10);
    file.artwork_id = first_id;
    try db.upsertFiles(scan, &.{file});
    try db.finishScan(scan);

    var page = try db.listTracks(std.testing.allocator, 0, 10);
    defer page.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), page.tracks.len);
    try std.testing.expectEqual(first_id, page.tracks[0].artwork_id.?);
}

test "aborted scan does not remove unseen files" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const complete = try db.beginScan("/music");
    try db.upsertFiles(complete, &.{
        testFile("/music/one.flac", 100, 10),
    });
    try db.finishScan(complete);

    const partial = try db.beginScan("/music");
    db.abortScan(partial);

    try std.testing.expect((try db.findFile(complete, "/music/one.flac")) != null);
}

test "lists tracks with stable keyset pagination" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const scan = try db.beginScan("/music");
    try db.upsertFiles(scan, &.{
        testFile("/music/one.flac", 100, 10),
        testFile("/music/two.flac", 200, 20),
        testFile("/music/three.flac", 300, 30),
    });
    try db.finishScan(scan);

    var first = try db.listTracks(std.testing.allocator, 0, 2);
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), first.tracks.len);
    try std.testing.expectEqual(@as(u64, 3), first.total_size);
    try std.testing.expect(first.has_more);
    try std.testing.expectEqualStrings("/music/one.flac", first.tracks[0].path);

    var second = try db.listTracks(std.testing.allocator, first.tracks[1].id, 2);
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), second.tracks.len);
    try std.testing.expect(!second.has_more);
    try std.testing.expectEqualStrings("/music/three.flac", second.tracks[0].path);
}

test "persists extracted metadata and preserves date added on update" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    var file = testFile("/music/song.flac", 123, 10);
    file.title = "Song";
    file.track_artist = "Track Artist";
    file.album_artist = "Album Artist";
    file.album = "Album";
    file.track_number = 3;
    file.disc_number = 2;
    file.release_date = "2026-07-18";
    file.duration_ms = 245_000;
    file.sample_rate = 96_000;
    file.bits_per_sample = 24;

    const first_scan = try db.beginScan("/music");
    try db.upsertFiles(first_scan, &.{file});
    try db.finishScan(first_scan);

    var first_page = try db.listTracks(std.testing.allocator, 0, 10);
    const date_added = first_page.tracks[0].date_added;
    try std.testing.expectEqualStrings("Song", first_page.tracks[0].title.?);
    try std.testing.expectEqualStrings("Track Artist", first_page.tracks[0].track_artist.?);
    try std.testing.expectEqualStrings("Album Artist", first_page.tracks[0].album_artist.?);
    try std.testing.expectEqualStrings("Album", first_page.tracks[0].album.?);
    try std.testing.expectEqual(@as(?u16, 3), first_page.tracks[0].track_number);
    try std.testing.expectEqual(@as(?u16, 2), first_page.tracks[0].disc_number);
    try std.testing.expectEqualStrings("2026-07-18", first_page.tracks[0].release_date.?);
    try std.testing.expectEqual(@as(?u64, 245_000), first_page.tracks[0].duration_ms);
    try std.testing.expectEqualStrings("flac", first_page.tracks[0].codec);
    try std.testing.expectEqual(@as(u32, 96_000), first_page.tracks[0].sample_rate);
    try std.testing.expectEqual(@as(u8, 24), first_page.tracks[0].bits_per_sample);
    try std.testing.expect(date_added > 0);
    first_page.deinit(std.testing.allocator);

    file.title = "Updated Song";
    file.modified_ns = 11;
    const second_scan = try db.beginScan("/music");
    try db.upsertFiles(second_scan, &.{file});
    try db.finishScan(second_scan);

    var second_page = try db.listTracks(std.testing.allocator, 0, 10);
    defer second_page.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Updated Song", second_page.tracks[0].title.?);
    try std.testing.expectEqual(date_added, second_page.tracks[0].date_added);
}
