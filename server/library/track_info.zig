const std = @import("std");

const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavutil/dict.h");
});

/// Metadata owned by the caller. All strings remain valid after FFmpeg closes
/// the input and must be released with `deinit`.
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

    pub fn deinit(self: *TrackMetadata, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.title);
        freeOptional(allocator, self.track_artist);
        freeOptional(allocator, self.album_artist);
        freeOptional(allocator, self.album);
        freeOptional(allocator, self.release_date);
        allocator.free(self.codec);
        self.* = undefined;
    }
};

pub fn read(allocator: std.mem.Allocator, media_path: []const u8) !TrackMetadata {
    const terminated_path = try allocator.dupeSentinel(
        u8,
        media_path,
        0,
    );
    defer allocator.free(terminated_path);

    var format_ctx: [*c]c.AVFormatContext = null;
    if (c.avformat_open_input(&format_ctx, terminated_path.ptr, null, null) < 0) {
        return error.CouldNotOpenInput;
    }
    defer c.avformat_close_input(&format_ctx);

    if (c.avformat_find_stream_info(format_ctx, null) < 0) {
        return error.CouldNotFindStreamInfo;
    }

    const audio_stream_index = c.av_find_best_stream(
        format_ctx,
        c.AVMEDIA_TYPE_AUDIO,
        -1,
        -1,
        null,
        0,
    );
    if (audio_stream_index < 0) return error.NoAudioStream;

    const audio_stream = format_ctx.*.streams[@intCast(audio_stream_index)];
    const codec_parameters = audio_stream.*.codecpar;
    const format_metadata = format_ctx.*.metadata;
    const stream_metadata = audio_stream.*.metadata;

    const title = metadataValue(format_metadata, "title") orelse
        metadataValue(stream_metadata, "title");

    const track_artist = metadataValue(format_metadata, "artist") orelse
        metadataValue(stream_metadata, "artist");

    const album_artist = metadataValue(format_metadata, "album_artist") orelse
        metadataValue(format_metadata, "albumartist") orelse
        metadataValue(stream_metadata, "album_artist") orelse
        metadataValue(stream_metadata, "albumartist");

    const album = metadataValue(format_metadata, "album") orelse
        metadataValue(stream_metadata, "album");

    const release_date = metadataValue(format_metadata, "date") orelse
        metadataValue(format_metadata, "year") orelse
        metadataValue(stream_metadata, "date") orelse
        metadataValue(stream_metadata, "year");

    const track_number = parseNumber(
        metadataValue(format_metadata, "track") orelse
            metadataValue(format_metadata, "tracknumber") orelse
            metadataValue(stream_metadata, "tracknumber") orelse
            metadataValue(stream_metadata, "track"),
    );

    const disc_number = parseNumber(
        metadataValue(format_metadata, "disc") orelse
            metadataValue(format_metadata, "discnumber") orelse
            metadataValue(stream_metadata, "discnumber") orelse
            metadataValue(stream_metadata, "disc"),
    );

    const sample_rate = std.math.cast(u32, codec_parameters.*.sample_rate) orelse
        return error.InvalidSampleRate;

    const codec_name = std.mem.span(c.avcodec_get_name(codec_parameters.*.codec_id));

    var result: TrackMetadata = .{
        .codec = try allocator.dupe(u8, codec_name),
        .sample_rate = sample_rate,
        .bits_per_sample = bitsPerSample(codec_parameters),
        .track_number = track_number,
        .disc_number = disc_number,
        .duration_ms = durationMs(format_ctx, audio_stream),
    };
    errdefer result.deinit(allocator);

    result.title = try dupeOptional(allocator, title);
    result.track_artist = try dupeOptional(allocator, track_artist);
    result.album_artist = try dupeOptional(allocator, album_artist);
    result.album = try dupeOptional(allocator, album);
    result.release_date = try dupeOptional(allocator, release_date);

    return result;
}

fn durationMs(
    format_ctx: [*c]const c.AVFormatContext,
    audio_stream: [*c]const c.AVStream,
) ?u64 {
    if (audio_stream.*.duration != c.AV_NOPTS_VALUE) {
        const milliseconds = c.av_rescale_q(
            audio_stream.*.duration,
            audio_stream.*.time_base,
            c.AVRational{ .num = 1, .den = 1000 },
        );
        if (milliseconds >= 0) return @intCast(milliseconds);
    }

    if (format_ctx.*.duration != c.AV_NOPTS_VALUE and format_ctx.*.duration >= 0) {
        return @intCast(@divTrunc(format_ctx.*.duration, c.AV_TIME_BASE / 1000));
    }

    return null;
}

fn bitsPerSample(codec_parameters: [*c]const c.AVCodecParameters) u8 {
    const bits = if (codec_parameters.*.bits_per_raw_sample > 0)
        codec_parameters.*.bits_per_raw_sample
    else
        codec_parameters.*.bits_per_coded_sample;

    return std.math.cast(u8, @max(bits, 0)) orelse 0;
}

fn metadataValue(
    dictionary: ?*const c.AVDictionary,
    key: [*:0]const u8,
) ?[]const u8 {
    const entry = c.av_dict_get(dictionary, key, null, 0);

    if (entry == null or entry.*.value == null) return null;

    return std.mem.span(entry.*.value);
}

fn parseNumber(value: ?[]const u8) ?u16 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    const separator = std.mem.indexOfScalar(u8, trimmed, '/') orelse trimmed.len;
    const number = std.mem.trim(u8, trimmed[0..separator], " \t");

    if (number.len == 0) return null;

    return std.fmt.parseInt(u16, number, 10) catch null;
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    if (value) |text| {
        return try allocator.dupe(u8, text);
    }

    return null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |text| {
        allocator.free(text);
    }
}

test "parses track and disc numbers with optional totals" {
    try std.testing.expectEqual(@as(?u16, 3), parseNumber("3/12"));
    try std.testing.expectEqual(@as(?u16, 2), parseNumber(" 2 "));
    try std.testing.expectEqual(@as(?u16, null), parseNumber("unknown"));
    try std.testing.expectEqual(@as(?u16, null), parseNumber(null));
}

test "reads technical information from a FLAC file" {
    const fixture = @embedFile("../testdata/fixtures/strict-s16le-stereo.flac");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.flac", .data = fixture });

    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buffer);
    const fixture_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ root_buffer[0..root_len], "fixture.flac" },
    );
    defer std.testing.allocator.free(fixture_path);

    var metadata = try read(std.testing.allocator, fixture_path);
    defer metadata.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("flac", metadata.codec);
    try std.testing.expect(metadata.sample_rate > 0);
    try std.testing.expectEqual(@as(u8, 16), metadata.bits_per_sample);
    try std.testing.expect(metadata.duration_ms != null);
}
