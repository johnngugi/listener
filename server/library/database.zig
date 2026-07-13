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

/// The filesystem facts needed to identify a new or changed library file.
/// All slices are borrowed for the duration of a database call.
pub const ScannedFile = struct {
    path: []const u8,
    size: u64,
    modified_ns: i64,
};

pub const FileState = struct {
    size: u64,
    modified_ns: i64,
};

/// A storage-neutral interface for the library scanner.
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
        finish_scan: *const fn (context: *anyopaque, scan: Scan) Error!void,
        abort_scan: *const fn (context: *anyopaque, scan: Scan) void,
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

    /// Completes a successful scan and removes rows under this root that were
    /// not observed during it.
    pub fn finishScan(self: Database, scan: Scan) Error!void {
        return self.vtable.finish_scan(self.context, scan);
    }

    /// Aborting never removes files that were absent from a partial scan.
    pub fn abortScan(self: Database, scan: Scan) void {
        self.vtable.abort_scan(self.context, scan);
    }
};

test "Database is a small type-erased handle" {
    try std.testing.expectEqual(@sizeOf(*anyopaque) * 2, @sizeOf(Database));
}
