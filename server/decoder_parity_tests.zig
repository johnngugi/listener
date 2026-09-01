const std = @import("std");
const ffmpeg = @import("decoder.zig");
const native = @import("media/macos/decoder.zig");

const Backend = enum { ffmpeg, native };

const Decoded = struct {
    pcm: []u8,
    info: ffmpeg.TrackInfo,
    eof_reads: usize,

    fn deinit(self: *Decoded, allocator: std.mem.Allocator) void {
        allocator.free(self.pcm);
        self.* = undefined;
    }
};

fn fixturePath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![:0]u8 {
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const path = try std.fs.path.join(
        allocator,
        &.{ root_buffer[0..root_len], "fixture.flac" },
    );
    defer allocator.free(path);
    return allocator.dupeZ(u8, path);
}

fn decode(
    comptime backend: Backend,
    path: [:0]const u8,
    chunk_size: usize,
    seek_target: ?u64,
) !Decoded {
    const Decoder = switch (backend) {
        .ffmpeg => ffmpeg.AudioDecoder,
        .native => native.AudioDecoder,
    };
    const allocator = std.testing.allocator;
    var decoder = try Decoder.open(allocator, path, .{});
    defer decoder.deinit();
    if (seek_target) |target| try decoder.seekToFrame(target);

    const buffer = try allocator.alloc(u8, chunk_size);
    defer allocator.free(buffer);
    var pcm: std.ArrayListUnmanaged(u8) = .empty;
    errdefer pcm.deinit(allocator);
    var reads: usize = 0;
    while (true) {
        const result = try decoder.read(buffer);
        reads += 1;
        try std.testing.expectEqual(result.bytes / decoder.trackInfo().bytesPerFrame(), result.frames);
        try pcm.appendSlice(allocator, buffer[0..result.bytes]);
        if (result.end_of_stream) break;
        if (reads > 100_000) return error.DecoderDidNotReachEndOfStream;
    }

    const after_eof = try decoder.read(buffer);
    try std.testing.expectEqual(@as(usize, 0), after_eof.bytes);
    try std.testing.expect(after_eof.end_of_stream);
    return .{
        .pcm = try pcm.toOwnedSlice(allocator),
        .info = decoder.trackInfo(),
        .eof_reads = reads,
    };
}

fn expectTrackInfoEqual(expected: ffmpeg.TrackInfo, actual: native.TrackInfo) !void {
    try std.testing.expectEqual(expected.sample_rate, actual.sample_rate);
    try std.testing.expectEqual(expected.channels, actual.channels);
    try std.testing.expectEqual(expected.duration_frames, actual.duration_frames);
    try std.testing.expectEqual(expected.valid_bits_per_sample, actual.valid_bits_per_sample);
    try std.testing.expectEqual(expected.native_sample_format, actual.native_sample_format);
    try std.testing.expectEqual(expected.output_sample_format, actual.output_sample_format);
    try std.testing.expectEqual(expected.output_layout, actual.output_layout);
}

fn expectParity(encoded: []const u8, chunk_size: usize, seek_target: ?u64) !void {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = encoded });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);

    var oracle = try decode(.ffmpeg, path, chunk_size, seek_target);
    defer oracle.deinit(allocator);
    var candidate = try decode(.native, path, chunk_size, seek_target);
    defer candidate.deinit(allocator);

    try expectTrackInfoEqual(oracle.info, candidate.info);
    try std.testing.expectEqualSlices(u8, oracle.pcm, candidate.pcm);
    try std.testing.expectEqual(oracle.eof_reads, candidate.eof_reads);
}

test "native and FFmpeg match TrackInfo PCM chunking and EOF transitions" {
    const fixtures = [_][]const u8{
        @embedFile("testdata/fixtures/strict-s16le-stereo.flac"),
        @embedFile("testdata/fixtures/baseline-s16le-mono-22050.flac"),
        @embedFile("testdata/fixtures/strict-s24le-stereo.flac"),
        @embedFile("testdata/fixtures/baseline-one-frame-s16le-mono.flac"),
        @embedFile("testdata/fixtures/baseline-block-boundary-s16le-stereo.flac"),
    };
    for (fixtures) |encoded| {
        for ([_]usize{ 4, 7, 18_432, 20_000 }) |chunk_size| {
            try expectParity(encoded, chunk_size, null);
        }
    }
}

test "native and FFmpeg return identical PCM after common seek targets" {
    const encoded = @embedFile("testdata/fixtures/seekable-s16le-stereo.flac");
    for ([_]u64{ 0, 4_608, 4_609, 6_000, 9_216, 11_024, 11_025 }) |target| {
        try expectParity(encoded, 28, target);
    }
}

test "accepted empty-stream duration difference is explicit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "fixture.flac",
        .data = @embedFile("testdata/fixtures/baseline-empty-s16le-stereo.flac"),
    });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);

    var oracle = try decode(.ffmpeg, path, 4, null);
    defer oracle.deinit(allocator);
    var candidate = try decode(.native, path, 4, null);
    defer candidate.deinit(allocator);
    try std.testing.expectEqual(@as(?u64, null), oracle.info.duration_frames);
    try std.testing.expectEqual(@as(?u64, 0), candidate.info.duration_frames);
    try std.testing.expectEqualSlices(u8, oracle.pcm, candidate.pcm);
}

test "accepted pre-boundary seek difference is explicit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "fixture.flac",
        .data = @embedFile("testdata/fixtures/seekable-s16le-stereo.flac"),
    });
    const path = try fixturePath(allocator, &tmp);
    defer allocator.free(path);

    var oracle = try ffmpeg.AudioDecoder.open(allocator, path, .{});
    defer oracle.deinit();
    try std.testing.expectError(error.SeekFailed, oracle.seekToFrame(4_607));

    var candidate = try native.AudioDecoder.open(allocator, path, .{});
    defer candidate.deinit();
    try candidate.seekToFrame(4_607);
}

test "native and FFmpeg reject malformed and unsupported input" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "fixture.flac",
        .data = "fLaC\x80\xff\xff\xfftruncated",
    });
    const malformed_path = try fixturePath(allocator, &tmp);
    defer allocator.free(malformed_path);
    try std.testing.expectError(
        error.CouldNotOpenInput,
        ffmpeg.AudioDecoder.open(allocator, malformed_path, .{}),
    );
    try std.testing.expectError(
        error.CouldNotOpenInput,
        native.AudioDecoder.open(allocator, malformed_path, .{}),
    );

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = "not audio" });
    const unsupported_path = try fixturePath(allocator, &tmp);
    defer allocator.free(unsupported_path);
    try std.testing.expectError(
        error.UnsupportedSampleFormat,
        ffmpeg.AudioDecoder.open(allocator, unsupported_path, .{}),
    );
    try std.testing.expectError(
        error.CouldNotOpenInput,
        native.AudioDecoder.open(allocator, unsupported_path, .{}),
    );
}
