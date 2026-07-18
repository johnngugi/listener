const std = @import("std");
const database = @import("database.zig");
const sqlite = @import("sqlite.zig");
const track_info = @import("track_info.zig");
const Sha256 = std.crypto.hash.sha2.Sha256;

pub fn scanLibrary(
    root_dir: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,
    db: database.Database,
    artwork_dir: []const u8,
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
        freeScannedFiles(allocator, flac_files.items);
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
                    var metadata = track_info.read(allocator, full_path) catch |err| {
                        allocator.free(full_path);
                        return err;
                    };

                    var metadata_transferred = false;
                    defer if (!metadata_transferred) {
                        allocator.free(full_path);
                        metadata.deinit(allocator);
                    };

                    if (metadata.title == null) {
                        metadata.title = try allocator.dupe(u8, std.fs.path.stem(file_name));
                    }

                    var artwork_id: ?i64 = null;

                    if (metadata.artwork) |artwork| {
                        var digest: [Sha256.digest_length]u8 = undefined;
                        Sha256.hash(artwork.bytes, &digest, .{});

                        const storage_key = try artworkStorageKey(allocator, digest, artwork.format);
                        defer allocator.free(storage_key);

                        const absolute_path = try std.fs.path.join(allocator, &.{
                            artwork_dir,
                            storage_key,
                        });
                        defer allocator.free(absolute_path);

                        const key_dir = std.fs.path.dirname(absolute_path).?;
                        const name = std.fs.path.basename(absolute_path);

                        try std.Io.Dir.cwd().createDirPath(io, key_dir);
                        try writeFile(io, key_dir, name, artwork.bytes);

                        artwork_id = try db.upsertArtwork(scan, .{
                            .sha256 = digest,
                            .mime_type = artwork.format.mimeType(),
                            .width = artwork.width,
                            .height = artwork.height,
                            .byte_length = artwork.bytes.len,
                            .storage_key = storage_key,
                        });
                    }

                    if (metadata.artwork) |*artwork| artwork.deinit(allocator);
                    metadata.artwork = null;

                    const scanned_file = database.ScannedFile{
                        .path = full_path,
                        .size = size,
                        .modified_ns = modified_ns,
                        .title = metadata.title,
                        .track_artist = metadata.track_artist,
                        .album_artist = metadata.album_artist,
                        .album = metadata.album,
                        .track_number = metadata.track_number,
                        .disc_number = metadata.disc_number,
                        .release_date = metadata.release_date,
                        .duration_ms = metadata.duration_ms,
                        .codec = metadata.codec,
                        .sample_rate = metadata.sample_rate,
                        .bits_per_sample = metadata.bits_per_sample,
                        .artwork_id = artwork_id,
                    };
                    // The scan batch now owns the metadata's allocated strings.
                    metadata_transferred = true;
                    flac_files.appendAssumeCapacity(scanned_file);

                    if (flac_files.items.len == 500) {
                        try db.upsertFiles(scan, flac_files.items);
                        freeScannedFiles(allocator, flac_files.items);
                        flac_files.clearRetainingCapacity();
                    }
                } else continue;
            }
        }
    }

    if (flac_files.items.len > 0) {
        try db.upsertFiles(scan, flac_files.items);
        freeScannedFiles(allocator, flac_files.items);
        flac_files.clearRetainingCapacity();
    }

    try db.finishScan(scan);
}

fn freeScannedFiles(allocator: std.mem.Allocator, files: []const database.ScannedFile) void {
    for (files) |file| {
        allocator.free(file.path);
        freeOptional(allocator, file.title);
        freeOptional(allocator, file.track_artist);
        freeOptional(allocator, file.album_artist);
        freeOptional(allocator, file.album);
        freeOptional(allocator, file.release_date);
        allocator.free(file.codec);
    }
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |text| allocator.free(text);
}

fn artworkStorageKey(
    allocator: std.mem.Allocator,
    digest: [Sha256.digest_length]u8,
    format: track_info.ArtworkFormat,
) ![]u8 {
    const hex = std.fmt.bytesToHex(digest, .lower);

    return std.fmt.allocPrint(
        allocator,
        "{s}/{s}/{s}.{s}",
        .{
            hex[0..2],
            hex[2..4],
            hex[0..],
            format.extension(),
        },
    );
}

fn writeFile(io: std.Io, absolute_path: []const u8, filename: []const u8, data: []const u8) !void {
    var dir = try std.Io.Dir.openDirAbsolute(io, absolute_path, .{});
    defer dir.close(io);

    const file = dir.createFile(io, filename, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var streaming_writer = file.writer(io, &buf);
    const writer = &streaming_writer.interface;

    try writer.writeAll(data);
    try streaming_writer.flush();
}

test "scanner traverses nested directories and flushes a partial batch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "nested");
    const fixture = @embedFile("../testdata/fixtures/strict-s16le-stereo.flac");
    try tmp.dir.writeFile(io, .{ .sub_path = "one.FLAC", .data = fixture });
    try tmp.dir.writeFile(io, .{ .sub_path = "nested/two.flac", .data = fixture });
    try tmp.dir.writeFile(io, .{ .sub_path = "ignored.txt", .data = "not audio" });

    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root_path = root_buffer[0..root_len];

    var db = try sqlite.open(allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    try scanLibrary(root_path, io, allocator, db, root_path);

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
    try std.testing.expectEqual(@as(u64, fixture.len), first.size);
    try std.testing.expectEqual(@as(u64, fixture.len), second.size);
    try std.testing.expect((try db.findFile(check_scan, ignored_path)) == null);

    var page = try db.listTracks(allocator, 0, 10);
    defer page.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), page.tracks.len);
    try std.testing.expectEqualStrings("flac", page.tracks[0].codec);
    try std.testing.expectEqual(@as(u8, 16), page.tracks[0].bits_per_sample);
    try std.testing.expect(page.tracks[0].duration_ms != null);
}
