const std = @import("std");

const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavutil/dict.h");
    @cInclude("libavutil/imgutils.h");
});

pub const max_artwork_bytes = 10 * 1024 * 1024;
pub const max_artwork_width = 6_000;
pub const max_artwork_height = 6_000;
pub const max_artwork_pixels = 25_000_000;

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

pub const ArtworkFormat = enum {
    jpeg,
    png,
    webp,

    pub fn mimeType(self: ArtworkFormat) []const u8 {
        return switch (self) {
            .jpeg => "image/jpeg",
            .png => "image/png",
            .webp => "image/webp",
        };
    }

    pub fn extension(self: ArtworkFormat) []const u8 {
        return switch (self) {
            .jpeg => "jpg",
            .png => "png",
            .webp => "webp",
        };
    }
};

pub const Artwork = struct {
    format: ArtworkFormat,
    bytes: []u8,
    width: u32,
    height: u32,

    pub fn deinit(self: *Artwork, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
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
        .artwork = null,
    };
    errdefer result.deinit(allocator);

    result.artwork = try readArtwork(allocator, format_ctx);
    result.title = try dupeOptional(allocator, title);
    result.track_artist = try dupeOptional(allocator, track_artist);
    result.album_artist = try dupeOptional(allocator, album_artist);
    result.album = try dupeOptional(allocator, album);
    result.release_date = try dupeOptional(allocator, release_date);

    return result;
}

/// Returns the first supported, decodable attached picture. Invalid or
/// oversized artwork is ignored so it cannot prevent the track from scanning.
fn readArtwork(
    allocator: std.mem.Allocator,
    format_ctx: [*c]c.AVFormatContext,
) std.mem.Allocator.Error!?Artwork {
    var index: usize = 0;
    while (index < format_ctx.*.nb_streams) : (index += 1) {
        const stream = format_ctx.*.streams[index];
        if ((stream.*.disposition & c.AV_DISPOSITION_ATTACHED_PIC) == 0) continue;

        const format = artworkFormat(stream.*.codecpar.*.codec_id) orelse continue;
        const picture = &stream.*.attached_pic;
        const dimensions = validateArtwork(stream.*.codecpar, picture) orelse continue;
        const byte_len = std.math.cast(usize, picture.*.size) orelse continue;

        return .{
            .format = format,
            .bytes = try allocator.dupe(u8, picture.*.data[0..byte_len]),
            .width = dimensions.width,
            .height = dimensions.height,
        };
    }

    return null;
}

const ArtworkDimensions = struct {
    width: u32,
    height: u32,
};

fn artworkFormat(codec_id: c.enum_AVCodecID) ?ArtworkFormat {
    return switch (codec_id) {
        c.AV_CODEC_ID_MJPEG => .jpeg,
        c.AV_CODEC_ID_PNG => .png,
        c.AV_CODEC_ID_WEBP => .webp,
        else => null,
    };
}

/// Performs every resource check before the caller copies the compressed data.
/// Decoding one frame verifies both the claimed format and actual dimensions.
fn validateArtwork(
    codec_parameters: [*c]const c.AVCodecParameters,
    picture: [*c]const c.AVPacket,
) ?ArtworkDimensions {
    if (picture.*.data == null or picture.*.size <= 0) return null;

    if (picture.*.size > max_artwork_bytes) return null;

    if (artworkFormat(codec_parameters.*.codec_id) == null) return null;

    if (codec_parameters.*.width > 0 and codec_parameters.*.height > 0 and
        !dimensionsAllowed(codec_parameters.*.width, codec_parameters.*.height))
    {
        return null;
    }

    const decoder = c.avcodec_find_decoder(codec_parameters.*.codec_id) orelse return null;

    var decoder_ctx = c.avcodec_alloc_context3(decoder) orelse return null;
    defer c.avcodec_free_context(&decoder_ctx);

    if (c.avcodec_parameters_to_context(decoder_ctx, codec_parameters) < 0) return null;

    decoder_ctx.*.max_pixels = max_artwork_pixels;
    if (c.avcodec_open2(decoder_ctx, decoder, null) < 0) return null;

    const frame = c.av_frame_alloc() orelse return null;
    defer c.av_frame_free(@constCast(&frame));

    if (c.avcodec_send_packet(decoder_ctx, picture) < 0) return null;
    if (c.avcodec_receive_frame(decoder_ctx, frame) < 0) return null;
    if (!dimensionsAllowed(frame.*.width, frame.*.height)) return null;

    return .{
        .width = @intCast(frame.*.width),
        .height = @intCast(frame.*.height),
    };
}

fn dimensionsAllowed(width: c_int, height: c_int) bool {
    if (width <= 0 or height <= 0) return false;

    if (width > max_artwork_width or height > max_artwork_height) return false;

    const width_u32: u32 = @intCast(width);
    const height_u32: u32 = @intCast(height);
    const pixels = @as(u64, width_u32) * @as(u64, height_u32);

    if (pixels > max_artwork_pixels) return false;

    return c.av_image_check_size(width_u32, height_u32, 0, null) >= 0;
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

test "artwork dimension policy rejects oversized and pathological images" {
    try std.testing.expect(dimensionsAllowed(5_000, 5_000));
    try std.testing.expect(!dimensionsAllowed(0, 1_000));
    try std.testing.expect(!dimensionsAllowed(6_001, 1_000));
    try std.testing.expect(!dimensionsAllowed(6_000, 6_000));
}

test "validates a supported image by decoding one frame" {
    const png =
        "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52" ++
        "\x00\x00\x00\x01\x00\x00\x00\x01\x08\x04\x00\x00\x00\xb5\x1c\x0c\x02" ++
        "\x00\x00\x00\x0b\x49\x44\x41\x54\x78\xda\x63\x64\xf8\x0f\x00\x01\x05\x01" ++
        "\x01\x27\x18\xe3\x66\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82";

    var codec_parameters = c.avcodec_parameters_alloc() orelse return error.OutOfMemory;
    defer c.avcodec_parameters_free(&codec_parameters);
    codec_parameters.*.codec_type = c.AVMEDIA_TYPE_VIDEO;
    codec_parameters.*.codec_id = c.AV_CODEC_ID_PNG;

    var packet = c.av_packet_alloc() orelse return error.OutOfMemory;
    defer c.av_packet_free(&packet);
    if (c.av_new_packet(packet, @intCast(png.len)) < 0) return error.OutOfMemory;
    @memcpy(packet.*.data[0..png.len], png);

    const dimensions = validateArtwork(codec_parameters, packet) orelse
        return error.ArtworkRejected;
    try std.testing.expectEqual(@as(u32, 1), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);
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
    try std.testing.expect(metadata.artwork == null);
}
