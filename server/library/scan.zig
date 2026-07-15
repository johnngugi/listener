const std = @import("std");
const database = @import("database.zig");
const sqlite = @import("sqlite.zig");

pub fn scanLibrary(
    root_dir: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,
    db: database.Database,
) !void {
    var queue: std.Deque([]u8) = .empty;
    defer {
        while (queue.popFront()) |path| allocator.free(path);
        queue.deinit(allocator);
    }

    const owned_root = try allocator.dupe(u8, root_dir);
    queue.pushBack(allocator, owned_root) catch |err| {
        allocator.free(owned_root);
        return err;
    };

    const scan = try db.beginScan(root_dir);
    errdefer db.abortScan(scan);

    var flac_files = try std.ArrayList(database.ScannedFile).initCapacity(allocator, 500);
    defer {
        freeFilePaths(allocator, flac_files.items);
        flac_files.deinit(allocator);
    }

    while (queue.len > 0) {
        const dir = queue.popFront().?;

        const cwd = try std.Io.Dir.openDirAbsolute(
            io,
            dir,
            .{
                .access_sub_paths = true,
                .follow_symlinks = false,
                .iterate = true,
            },
        );
        defer cwd.close(io);
        defer allocator.free(dir);

        var iterator = cwd.iterate();

        while (try iterator.next(io)) |entry| {
            if (entry.kind == .directory) {
                const full_path = try std.fs.path.join(allocator, &.{ dir, entry.name });
                queue.pushBack(allocator, full_path) catch |err| {
                    allocator.free(full_path);
                    return err;
                };
            } else if (entry.kind == .file) {
                const file_name = entry.name;
                const ext = std.fs.path.extension(file_name);

                if (std.ascii.eqlIgnoreCase(".flac", ext)) {
                    const full_path = try std.fs.path.join(allocator, &.{ dir, file_name });
                    const stat = cwd.statFile(io, file_name, .{ .follow_symlinks = false }) catch |err| {
                        allocator.free(full_path);
                        return err;
                    };
                    const size = stat.size;
                    const modified_ns = std.math.cast(i64, stat.mtime.nanoseconds) orelse {
                        allocator.free(full_path);
                        return error.TimestampOutOfRange;
                    };

                    const scanned_file = database.ScannedFile{
                        .path = full_path,
                        .size = size,
                        .modified_ns = modified_ns,
                    };
                    flac_files.appendAssumeCapacity(scanned_file);

                    if (flac_files.items.len == 500) {
                        try db.upsertFiles(scan, flac_files.items);
                        freeFilePaths(allocator, flac_files.items);
                        flac_files.clearRetainingCapacity();
                    }
                } else continue;
            }
        }
    }

    if (flac_files.items.len > 0) {
        try db.upsertFiles(scan, flac_files.items);
        freeFilePaths(allocator, flac_files.items);
        flac_files.clearRetainingCapacity();
    }

    try db.finishScan(scan);
}

fn freeFilePaths(allocator: std.mem.Allocator, files: []const database.ScannedFile) void {
    for (files) |file| allocator.free(file.path);
}

test "scanner traverses nested directories and flushes a partial batch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "nested");
    try tmp.dir.writeFile(io, .{ .sub_path = "one.FLAC", .data = "one" });
    try tmp.dir.writeFile(io, .{ .sub_path = "nested/two.flac", .data = "two-two" });
    try tmp.dir.writeFile(io, .{ .sub_path = "ignored.txt", .data = "not audio" });

    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root_path = root_buffer[0..root_len];

    var db = try sqlite.open(allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    try scanLibrary(root_path, io, allocator, db);

    const check_scan = try db.beginScan(root_path);
    defer db.abortScan(check_scan);

    const first_path = try std.fs.path.join(allocator, &.{ root_path, "one.FLAC" });
    defer allocator.free(first_path);
    const second_path = try std.fs.path.join(allocator, &.{ root_path, "nested", "two.flac" });
    defer allocator.free(second_path);
    const ignored_path = try std.fs.path.join(allocator, &.{ root_path, "ignored.txt" });
    defer allocator.free(ignored_path);

    const first = (try db.findFile(check_scan, first_path)).?;
    const second = (try db.findFile(check_scan, second_path)).?;
    try std.testing.expectEqual(@as(u64, 3), first.size);
    try std.testing.expectEqual(@as(u64, 7), second.size);
    try std.testing.expect((try db.findFile(check_scan, ignored_path)) == null);
}
