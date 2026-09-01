const std = @import("std");
const decoder_module = @import("media/macos/decoder.zig");

const AudioDecoder = decoder_module.AudioDecoder;
const TrackInfo = decoder_module.TrackInfo;

const DecodedFixture = struct {
    pcm: []u8,
    info: TrackInfo,

    fn deinit(self: *DecodedFixture, allocator: std.mem.Allocator) void {
        allocator.free(self.pcm);
        self.* = undefined;
    }
};

fn fixturePath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![:0]u8 {
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const path = try std.fs.path.join(allocator, &.{ root_buffer[0..root_len], "fixture.flac" });
    defer allocator.free(path);
    return allocator.dupeZ(u8, path);
}

fn decodeFixture(encoded: []const u8, chunk_size: usize) !DecodedFixture {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = encoded });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);

    var decoder = try AudioDecoder.open(allocator, path, .{});
    defer decoder.deinit();
    const buffer = try allocator.alloc(u8, chunk_size);
    defer allocator.free(buffer);
    var pcm: std.ArrayListUnmanaged(u8) = .empty;
    errdefer pcm.deinit(allocator);

    while (true) {
        const result = try decoder.read(buffer);
        try pcm.appendSlice(allocator, buffer[0..result.bytes]);
        if (result.end_of_stream) break;
    }
    const after_eof = try decoder.read(buffer);
    try std.testing.expectEqual(@as(usize, 0), after_eof.bytes);
    try std.testing.expect(after_eof.end_of_stream);

    return .{ .pcm = try pcm.toOwnedSlice(allocator), .info = decoder.trackInfo() };
}

fn expectDecoded(
    encoded: []const u8,
    expected: []const u8,
    chunk_size: usize,
    sample_rate: u32,
    channels: u32,
    valid_bits: u16,
) !void {
    var decoded = try decodeFixture(encoded, chunk_size);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, expected, decoded.pcm);
    try std.testing.expectEqual(sample_rate, decoded.info.sample_rate);
    try std.testing.expectEqual(channels, decoded.info.channels);
    try std.testing.expectEqual(valid_bits, decoded.info.valid_bits_per_sample);
    try std.testing.expectEqual(
        @as(?u64, @intCast(expected.len / decoded.info.bytesPerFrame())),
        decoded.info.duration_frames,
    );
}

test "AudioToolbox decodes supported PCM formats exactly across caller buffer sizes" {
    try expectDecoded(
        @embedFile("testdata/fixtures/strict-s16le-stereo.flac"),
        @embedFile("testdata/fixtures/strict-s16le-stereo.expected.pcm"),
        7,
        44_100,
        2,
        16,
    );
    try expectDecoded(
        @embedFile("testdata/fixtures/baseline-s16le-mono-22050.flac"),
        @embedFile("testdata/fixtures/baseline-s16le-mono-22050.expected.pcm"),
        6,
        22_050,
        1,
        16,
    );
    try expectDecoded(
        @embedFile("testdata/fixtures/strict-s24le-stereo.flac"),
        @embedFile("testdata/fixtures/strict-s24le-stereo.expected-24in32.pcm"),
        13,
        96_000,
        2,
        24,
    );

    const block_encoded = @embedFile("testdata/fixtures/baseline-block-boundary-s16le-stereo.flac");
    const block_expected = @embedFile("testdata/fixtures/baseline-block-boundary-s16le-stereo.expected.pcm");
    for ([_]usize{ 4, 18_432, 20_000 }) |chunk_size| {
        try expectDecoded(block_encoded, block_expected, chunk_size, 48_000, 2, 16);
    }
}

test "AudioToolbox handles empty and one-frame streams with final-read EOF" {
    try expectDecoded(
        @embedFile("testdata/fixtures/baseline-empty-s16le-stereo.flac"),
        @embedFile("testdata/fixtures/baseline-empty-s16le-stereo.expected.pcm"),
        4,
        44_100,
        2,
        16,
    );
    try expectDecoded(
        @embedFile("testdata/fixtures/baseline-one-frame-s16le-mono.flac"),
        @embedFile("testdata/fixtures/baseline-one-frame-s16le-mono.expected.pcm"),
        2,
        48_000,
        1,
        16,
    );
}

test "AudioToolbox seeks precisely and clears pending PCM" {
    const allocator = std.testing.allocator;
    const encoded = @embedFile("testdata/fixtures/seekable-s16le-stereo.flac");
    const expected = @embedFile("testdata/fixtures/seekable-s16le-stereo.expected.pcm");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = encoded });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);

    for ([_]u64{ 0, 4_607, 4_608, 4_609, 6_000, 9_216, 11_024, 11_025 }) |target| {
        var decoder = try AudioDecoder.open(allocator, path, .{});
        defer decoder.deinit();
        var pre_seek: [5]u8 = undefined;
        _ = try decoder.read(&pre_seek);
        try decoder.seekToFrame(target);

        var actual: std.ArrayListUnmanaged(u8) = .empty;
        defer actual.deinit(allocator);
        var buffer: [28]u8 = undefined;
        while (true) {
            const result = try decoder.read(&buffer);
            try actual.appendSlice(allocator, buffer[0..result.bytes]);
            if (result.end_of_stream) break;
        }
        const offset: usize = @intCast(target * decoder.trackInfo().bytesPerFrame());
        try std.testing.expectEqualSlices(u8, expected[offset..], actual.items);
    }

    var decoder = try AudioDecoder.open(allocator, path, .{});
    defer decoder.deinit();
    try std.testing.expectError(error.SeekOutOfRange, decoder.seekToFrame(11_026));
}

test "AudioToolbox releases resources across repeated decoder lifetimes" {
    const allocator = std.testing.allocator;
    const encoded = @embedFile("testdata/fixtures/strict-s16le-stereo.flac");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = encoded });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);

    for (0..100) |_| {
        var decoder = try AudioDecoder.open(allocator, path, .{});
        var buffer: [11]u8 = undefined;
        _ = try decoder.read(&buffer);
        try decoder.seekToFrame(0);
        decoder.deinit();
    }
}

test "AudioToolbox rejects malformed input" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "fixture.flac",
        .data = "fLaC\x80\xff\xff\xfftruncated",
    });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);
    try std.testing.expectError(error.CouldNotOpenInput, AudioDecoder.open(allocator, path, .{}));
}
