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
    \\CREATE TABLE IF NOT EXISTS tracks (
    \\    id INTEGER PRIMARY KEY,
    \\    root_id INTEGER NOT NULL REFERENCES library_roots(id) ON DELETE CASCADE,
    \\    path TEXT NOT NULL,
    \\    size INTEGER NOT NULL CHECK (size >= 0),
    \\    modified_ns INTEGER NOT NULL,
    \\    last_seen_scan_id INTEGER NOT NULL,
    \\    UNIQUE (root_id, path)
    \\);
    \\CREATE INDEX IF NOT EXISTS tracks_last_seen_idx
    \\    ON tracks(root_id, last_seen_scan_id);
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
            "INSERT INTO tracks(root_id, path, size, modified_ns, last_seen_scan_id) " ++
                "VALUES (?1, ?2, ?3, ?4, ?5) " ++
                "ON CONFLICT(root_id, path) DO UPDATE SET " ++
                "size=excluded.size, modified_ns=excluded.modified_ns, " ++
                "last_seen_scan_id=excluded.last_seen_scan_id",
        );
        defer stmt.deinit();

        for (files) |file| {
            try stmt.bindI64(1, scan.root_id);
            try stmt.bindText(2, file.path);
            try stmt.bindI64(3, std.math.cast(i64, file.size) orelse return error.DatabaseConstraint);
            try stmt.bindI64(4, file.modified_ns);
            try stmt.bindI64(5, scan.id);

            if (try stmt.step() != .done) return error.DatabaseOperationFailed;
            try stmt.reset();
        }

        try self.exec("COMMIT");
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
};

const vtable: database.Database.VTable = .{
    .deinit = Sqlite.deinit,
    .migrate = Sqlite.migrate,
    .begin_scan = Sqlite.beginScan,
    .find_file = Sqlite.findFile,
    .upsert_files = Sqlite.upsertFiles,
    .finish_scan = Sqlite.finishScan,
    .abort_scan = Sqlite.abortScan,
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

test "SQLite scan lifecycle upserts files and removes stale rows" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const first = try db.beginScan("/music");
    try db.upsertFiles(first, &.{
        .{ .path = "/music/one.flac", .size = 100, .modified_ns = 10 },
        .{ .path = "/music/two.flac", .size = 200, .modified_ns = 20 },
    });
    try db.finishScan(first);

    const second = try db.beginScan("/music");
    const unchanged = (try db.findFile(second, "/music/one.flac")).?;
    try std.testing.expectEqual(@as(u64, 100), unchanged.size);
    try db.upsertFiles(second, &.{
        .{ .path = "/music/one.flac", .size = 101, .modified_ns = 11 },
    });
    try db.finishScan(second);

    try std.testing.expect((try db.findFile(second, "/music/two.flac")) == null);
    const updated = (try db.findFile(second, "/music/one.flac")).?;
    try std.testing.expectEqual(@as(u64, 101), updated.size);
}

test "aborted scan does not remove unseen files" {
    var db = try open(std.testing.allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const complete = try db.beginScan("/music");
    try db.upsertFiles(complete, &.{
        .{ .path = "/music/one.flac", .size = 100, .modified_ns = 10 },
    });
    try db.finishScan(complete);

    const partial = try db.beginScan("/music");
    db.abortScan(partial);

    try std.testing.expect((try db.findFile(complete, "/music/one.flac")) != null);
}
