const std = @import("std");
const artwork_processor = @import("../media/artwork.zig");
const metadata_parser = @import("../media/flac/metadata.zig");

pub const ArtworkFormat = artwork_processor.Format;
pub const Artwork = artwork_processor.Artwork;
pub const max_artwork_bytes = artwork_processor.max_encoded_bytes;

/// Metadata owned by the caller. Every slice must be released with `deinit`.
pub const TrackMetadata = struct {
    title: ?[]u8 = null,
    track_artist: ?[]u8 = null,
    album_artist: ?[]u8 = null,
    album: ?[]u8 = null,
    track_number: ?u16 = null,
    disc_number: ?u16 = null,
    release_date: ?[]u8 = null,
    duration_ms: ?u64 = null,
    codec: []u8,
    sample_rate: u32,
    bits_per_sample: u8,
    artwork: ?Artwork = null,

    pub fn deinit(self: *TrackMetadata, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.title);
        freeOptional(allocator, self.track_artist);
        freeOptional(allocator, self.album_artist);
        freeOptional(allocator, self.album);
        freeOptional(allocator, self.release_date);
        if (self.artwork) |*artwork| artwork.deinit(allocator);
        allocator.free(self.codec);
        self.* = undefined;
    }
};

/// Reads only the bounded FLAC metadata chain. Audio frames are never loaded
/// into memory, so library scanning remains independent of track file size.
pub fn read(
    allocator: std.mem.Allocator,
    io: std.Io,
    media_path: []const u8,
) !TrackMetadata {
    const encoded_metadata = try readMetadataChain(allocator, io, media_path);
    defer allocator.free(encoded_metadata);

    var parsed = try metadata_parser.parse(allocator, encoded_metadata);
    defer parsed.deinit(allocator);

    var result: TrackMetadata = .{
        .title = try dupeOptional(allocator, parsed.title),
        .track_artist = null,
        .album_artist = null,
        .album = null,
        .track_number = parsed.track_number,
        .disc_number = parsed.disc_number,
        .release_date = null,
        .duration_ms = parsed.duration_ms,
        .codec = undefined,
        .sample_rate = parsed.sample_rate,
        .bits_per_sample = parsed.bits_per_sample,
        .artwork = null,
    };
    errdefer freeOptional(allocator, result.title);

    result.track_artist = try dupeOptional(allocator, parsed.track_artist);
    errdefer freeOptional(allocator, result.track_artist);
    result.album_artist = try dupeOptional(allocator, parsed.album_artist);
    errdefer freeOptional(allocator, result.album_artist);
    result.album = try dupeOptional(allocator, parsed.album);
    errdefer freeOptional(allocator, result.album);
    result.release_date = try dupeOptional(allocator, parsed.release_date);
    errdefer freeOptional(allocator, result.release_date);
    result.codec = try allocator.dupe(u8, parsed.codec);
    errdefer allocator.free(result.codec);

    if (parsed.artwork) |picture| {
        result.artwork = try artwork_processor.process(allocator, picture.bytes);
    }
    return result;
}

/// Reads a conventional sidecar and sends its bytes through the same backend
/// used for embedded FLAC artwork. The filename and extension are not used to
/// determine the encoded format.
pub fn readImage(
    allocator: std.mem.Allocator,
    io: std.Io,
    image_path: []const u8,
) !?Artwork {
    const encoded = std.Io.Dir.cwd().readFileAlloc(
        io,
        image_path,
        allocator,
        .limited(artwork_processor.max_source_bytes + 1),
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => null,
    };
    defer allocator.free(encoded);
    if (encoded.len > artwork_processor.max_source_bytes) return null;
    return artwork_processor.process(allocator, encoded);
}

fn readMetadataChain(
    allocator: std.mem.Allocator,
    io: std.Io,
    media_path: []const u8,
) ![]u8 {
    const file = try std.Io.Dir.openFileAbsolute(io, media_path, .{});
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    var encoded: std.ArrayList(u8) = .empty;
    errdefer encoded.deinit(allocator);

    var marker: [4]u8 = undefined;
    reader.readSliceAll(&marker) catch return error.InvalidStreamMarker;
    if (!std.mem.eql(u8, &marker, "fLaC")) return error.InvalidStreamMarker;
    try encoded.appendSlice(allocator, &marker);

    var is_last = false;
    while (!is_last) {
        var header: [4]u8 = undefined;
        reader.readSliceAll(&header) catch return error.TruncatedMetadata;
        is_last = (header[0] & 0x80) != 0;
        const block_length = (@as(usize, header[1]) << 16) |
            (@as(usize, header[2]) << 8) |
            @as(usize, header[3]);

        const next_length = std.math.add(usize, encoded.items.len, 4 + block_length) catch
            return error.MetadataTooLarge;
        if (next_length > metadata_parser.max_metadata_bytes) return error.MetadataTooLarge;

        try encoded.appendSlice(allocator, &header);
        const old_length = encoded.items.len;
        try encoded.resize(allocator, next_length);
        reader.readSliceAll(encoded.items[old_length..]) catch return error.TruncatedMetadata;
    }

    return encoded.toOwnedSlice(allocator);
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |text| try allocator.dupe(u8, text) else null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |text| allocator.free(text);
}

test "reads technical information from a FLAC file" {
    const fixture = @embedFile("../testdata/fixtures/strict-s16le-stereo.flac");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = fixture });

    const path = try fixturePath(std.testing.allocator, std.testing.io, tmp.dir, "fixture.flac");
    defer std.testing.allocator.free(path);
    var metadata = try read(std.testing.allocator, std.testing.io, path);
    defer metadata.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("flac", metadata.codec);
    try std.testing.expectEqual(@as(u8, 16), metadata.bits_per_sample);
    try std.testing.expect(metadata.duration_ms != null);
    try std.testing.expect(metadata.artwork == null);
}

test "validates embedded JPEG PNG and WebP through the shared backend" {
    const cases = .{
        .{ @embedFile("../testdata/fixtures/baseline-embedded-jpg.flac"), ArtworkFormat.jpeg },
        .{ @embedFile("../testdata/fixtures/baseline-embedded-png.flac"), ArtworkFormat.png },
        .{ @embedFile("../testdata/fixtures/baseline-embedded-webp.flac"), ArtworkFormat.webp },
    };

    inline for (cases) |case| {
        var metadata = try readFixtureMetadata(case[0]);
        defer metadata.deinit(std.testing.allocator);

        const artwork = metadata.artwork orelse return error.ArtworkRejected;
        try std.testing.expectEqual(case[1], artwork.format);
        try std.testing.expectEqual(@as(u32, 4), artwork.width);
        try std.testing.expectEqual(@as(u32, 2), artwork.height);
    }
}

test "sidecar format is detected from bytes rather than its extension" {
    const jpeg = @embedFile("../testdata/fixtures/baseline-cover.jpg");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "cover.png", .data = jpeg });

    const path = try fixturePath(std.testing.allocator, std.testing.io, tmp.dir, "cover.png");
    defer std.testing.allocator.free(path);
    var result = (try readImage(std.testing.allocator, std.testing.io, path)) orelse
        return error.ArtworkRejected;
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(ArtworkFormat.jpeg, result.format);
}

fn readFixtureMetadata(encoded: []const u8) !TrackMetadata {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = encoded });
    const path = try fixturePath(std.testing.allocator, std.testing.io, tmp.dir, "fixture.flac");
    defer std.testing.allocator.free(path);
    return read(std.testing.allocator, std.testing.io, path);
}

fn fixturePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    name: []const u8,
) ![]u8 {
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try dir.realPath(io, &root_buffer);
    return std.fs.path.join(allocator, &.{ root_buffer[0..root_len], name });
}
