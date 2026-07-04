const std = @import("std");

pub const magic = "LSTN".*;
pub const protocol_version: u16 = 1;
pub const header_wire_len: u16 = 40;
pub const max_body_len: u32 = 1024 * 1024;

pub const ProtocolError = error{
    InvalidMagic,
    InvalidFlags,
    UnsupportedVersion,
    InvalidHeaderLength,
    InvalidBodyLength,
    InvalidPlaybackId,
    InvalidMessageType,
    InvalidMediaPath,
    InvalidProtocolErrorCode,
    InvalidProtocolErrorDetail,
    UnsupportedSampleFormat,
    BodyTooLarge,
};

pub const MessageType = enum(u16) {
    hello = 1,
    hello_ack = 2,
    start_stream = 3,
    stream_info = 4,
    audio_frame = 5,
    buffer_status = 6,
    cancel_generation = 7,
    stream_end = 8,
    protocol_error = 9,
    ping = 10,
    pong = 11,
};

// Wire layout:
//   magic          u8[4]
//   version        u16
//   message_type   u16
//   flags          u16
//   header_len     u16 = header_wire_len
//   body_len       u32
//   stream_id      u64
//   generation_id  u64
//   sequence       u64
pub const Header = struct {
    version: u16 = protocol_version,
    message_type: MessageType,
    flags: u16 = 0,
    body_len: u32,
    stream_id: u64 = 0,
    generation_id: u64 = 0,
    sequence: u64 = 0,

    pub fn encode(self: Header) ProtocolError![header_wire_len]u8 {
        if (self.body_len > max_body_len) return error.BodyTooLarge;

        var out: [header_wire_len]u8 = undefined;

        @memcpy(out[0..4], magic[0..]);
        std.mem.writeInt(u16, out[4..6], self.version, .big);
        std.mem.writeInt(
            u16,
            out[6..8],
            @intFromEnum(self.message_type),
            .big,
        );
        std.mem.writeInt(u16, out[8..10], self.flags, .big);
        std.mem.writeInt(u16, out[10..12], header_wire_len, .big);
        std.mem.writeInt(u32, out[12..16], self.body_len, .big);
        std.mem.writeInt(u64, out[16..24], self.stream_id, .big);
        std.mem.writeInt(u64, out[24..32], self.generation_id, .big);
        std.mem.writeInt(u64, out[32..40], self.sequence, .big);

        return out;
    }

    pub fn decode(bytes: []const u8) ProtocolError!Header {
        if (bytes.len < header_wire_len) return error.InvalidHeaderLength;
        if (!std.mem.eql(u8, bytes[0..4], magic[0..])) {
            return error.InvalidMagic;
        }

        const version = std.mem.readInt(u16, bytes[4..6], .big);
        if (version != protocol_version) return error.UnsupportedVersion;

        if (std.mem.readInt(u16, bytes[8..10], .big) != 0) {
            return error.InvalidFlags;
        }

        const encoded_header_len = std.mem.readInt(u16, bytes[10..12], .big);
        if (encoded_header_len != header_wire_len) {
            return error.InvalidHeaderLength;
        }

        const body_len = std.mem.readInt(u32, bytes[12..16], .big);
        if (body_len > max_body_len) return error.BodyTooLarge;

        return .{
            .version = version,
            .message_type = try decodeMessageType(
                std.mem.readInt(u16, bytes[6..8], .big),
            ),
            .flags = std.mem.readInt(u16, bytes[8..10], .big),
            .body_len = body_len,
            .stream_id = std.mem.readInt(u64, bytes[16..24], .big),
            .generation_id = std.mem.readInt(u64, bytes[24..32], .big),
            .sequence = std.mem.readInt(u64, bytes[32..40], .big),
        };
    }
};

pub const SampleFormat = enum(u16) {
    pcm_s16le = 1,
    pcm_s24le_packed = 2,
    // A signed 24-bit value sign-extended into a little-endian i32.
    pcm_s24le_in_s32le = 3,
    pcm_s32le = 4,
    pcm_f32le = 5,
};

// Wire layout:
//   format                     u16
//   sample_rate                u32
//   channels                   u16
//   channel_layout             u32
//   total_frames               u64
//   actual_start_frame         u64
//   recommended_buffer_frames  u32
pub const StreamInfo = struct {
    pub const wire_len: u32 = 32;

    format: SampleFormat,
    sample_rate: u32,
    channels: u16,
    channel_layout: u32,
    total_frames: u64,
    actual_start_frame: u64,
    recommended_buffer_frames: u32,

    pub fn encode(self: StreamInfo) [wire_len]u8 {
        var out: [wire_len]u8 = undefined;

        std.mem.writeInt(u16, out[0..2], @intFromEnum(self.format), .big);
        std.mem.writeInt(u32, out[2..6], self.sample_rate, .big);
        std.mem.writeInt(u16, out[6..8], self.channels, .big);
        std.mem.writeInt(u32, out[8..12], self.channel_layout, .big);
        std.mem.writeInt(u64, out[12..20], self.total_frames, .big);
        std.mem.writeInt(u64, out[20..28], self.actual_start_frame, .big);
        std.mem.writeInt(
            u32,
            out[28..32],
            self.recommended_buffer_frames,
            .big,
        );

        return out;
    }

    pub fn decode(bytes: []const u8) ProtocolError!StreamInfo {
        if (bytes.len != wire_len) return error.InvalidBodyLength;

        return .{
            .format = try decodeSampleFormat(
                std.mem.readInt(u16, bytes[0..2], .big),
            ),
            .sample_rate = std.mem.readInt(u32, bytes[2..6], .big),
            .channels = std.mem.readInt(u16, bytes[6..8], .big),
            .channel_layout = std.mem.readInt(u32, bytes[8..12], .big),
            .total_frames = std.mem.readInt(u64, bytes[12..20], .big),
            .actual_start_frame = std.mem.readInt(u64, bytes[20..28], .big),
            .recommended_buffer_frames = std.mem.readInt(
                u32,
                bytes[28..32],
                .big,
            ),
        };
    }
};

// Wire layout:
//   requested_start_frame  u64
//   playback_id_len        u16
//   path_len               u16
//   playback_id            u8[playback_id_len]
//   media_path             u8[path_len]
pub const StartStream = struct {
    pub const fixed_wire_len: u32 = 12;
    pub const max_playback_id_len: u16 = 256;
    pub const max_path_len: u16 = 4096;
    pub const max_wire_len = fixed_wire_len + max_playback_id_len + max_path_len;

    requested_start_frame: u64,
    playback_id: []const u8,
    media_path: []const u8,

    pub fn encode(self: StartStream, out: []u8) ![]u8 {
        try self.validate();

        const encoded_len = fixed_wire_len + self.playback_id.len + self.media_path.len;
        if (encoded_len > out.len) return error.BufferTooSmall;

        std.mem.writeInt(u64, out[0..8], self.requested_start_frame, .big);
        std.mem.writeInt(u16, out[8..10], @intCast(self.playback_id.len), .big);
        std.mem.writeInt(u16, out[10..12], @intCast(self.media_path.len), .big);

        const playback_id_start = fixed_wire_len;
        const path_start = playback_id_start + self.playback_id.len;
        @memcpy(out[playback_id_start..path_start], self.playback_id);
        @memcpy(out[path_start..encoded_len], self.media_path);

        return out[0..encoded_len];
    }

    pub fn decode(bytes: []const u8) ProtocolError!StartStream {
        if (bytes.len < fixed_wire_len or bytes.len > max_wire_len) {
            return error.InvalidBodyLength;
        }

        const playback_id_len = std.mem.readInt(u16, bytes[8..10], .big);
        const path_len = std.mem.readInt(u16, bytes[10..12], .big);

        if (bytes.len != fixed_wire_len + playback_id_len + path_len) {
            return error.InvalidBodyLength;
        }

        const playback_id_start = fixed_wire_len;
        const path_start = playback_id_start + playback_id_len;
        const playback_id = bytes[playback_id_start..path_start];
        const media_path = bytes[path_start..];

        try validatePlaybackId(playback_id);
        try validateMediaPath(media_path);

        return .{
            .requested_start_frame = std.mem.readInt(u64, bytes[0..8], .big),
            .playback_id = playback_id,
            .media_path = media_path,
        };
    }

    pub fn validate(self: StartStream) ProtocolError!void {
        try validatePlaybackId(self.playback_id);
        try validateMediaPath(self.media_path);
    }

    fn validatePlaybackId(playback_id: []const u8) ProtocolError!void {
        if (playback_id.len == 0 or playback_id.len > max_playback_id_len) {
            return error.InvalidPlaybackId;
        }

        if (!std.unicode.utf8ValidateSlice(playback_id)) {
            return error.InvalidPlaybackId;
        }

        if (std.mem.findScalar(u8, playback_id, 0) != null) {
            return error.InvalidPlaybackId;
        }
    }

    fn validateMediaPath(path: []const u8) ProtocolError!void {
        if (path.len == 0 or path.len > max_path_len) {
            return error.InvalidMediaPath;
        }

        if (!std.unicode.utf8ValidateSlice(path)) {
            return error.InvalidMediaPath;
        }

        if (std.mem.indexOfScalar(u8, path, 0) != null) {
            return error.InvalidMediaPath;
        }
    }
};

// Wire layout:
//   frame_offset  u64
//   frame_count   u32
//   audio_data    u8[body_len - fixed_wire_len]
pub const AudioFrame = struct {
    pub const fixed_wire_len: u32 = 12;
    pub const max_data_len: u16 = 1024;
    pub const max_wire_len = fixed_wire_len + max_data_len;

    frame_offset: u64,
    frame_count: u32,
    audio_data: []const u8,

    pub fn encode(self: AudioFrame, out: []u8) ![]u8 {
        if (self.audio_data.len > max_data_len) {
            return error.AudioDataTooLarge;
        }

        const encoded_len = fixed_wire_len + self.audio_data.len;
        if (encoded_len > out.len) return error.BufferTooSmall;

        std.mem.writeInt(u64, out[0..8], self.frame_offset, .big);
        std.mem.writeInt(u32, out[8..12], self.frame_count, .big);
        @memcpy(out[12..encoded_len], self.audio_data);

        return out[0..encoded_len];
    }

    pub fn decode(bytes: []const u8) ProtocolError!AudioFrame {
        if (bytes.len < fixed_wire_len or bytes.len > max_wire_len) {
            return error.InvalidBodyLength;
        }

        return .{
            .frame_offset = std.mem.readInt(u64, bytes[0..8], .big),
            .frame_count = std.mem.readInt(u32, bytes[8..12], .big),
            .audio_data = bytes[fixed_wire_len..],
        };
    }
};

// Wire layout:
//   buffered_frames         u32
//   credit_frames           u32
//   next_render_frame       u64
//   last_received_sequence  u64
//   underrun_count          u32
pub const BufferStatus = struct {
    pub const wire_len: u32 = 28;

    buffered_frames: u32,
    // Absolute allowance. Each status replaces the previous credit value.
    credit_frames: u32,
    next_render_frame: u64,
    last_received_sequence: u64,
    underrun_count: u32,

    pub fn encode(self: BufferStatus) [wire_len]u8 {
        var out: [wire_len]u8 = undefined;

        std.mem.writeInt(u32, out[0..4], self.buffered_frames, .big);
        std.mem.writeInt(u32, out[4..8], self.credit_frames, .big);
        std.mem.writeInt(u64, out[8..16], self.next_render_frame, .big);
        std.mem.writeInt(
            u64,
            out[16..24],
            self.last_received_sequence,
            .big,
        );
        std.mem.writeInt(u32, out[24..28], self.underrun_count, .big);

        return out;
    }

    pub fn decode(bytes: []const u8) ProtocolError!BufferStatus {
        if (bytes.len != wire_len) return error.InvalidBodyLength;

        return .{
            .buffered_frames = std.mem.readInt(u32, bytes[0..4], .big),
            .credit_frames = std.mem.readInt(u32, bytes[4..8], .big),
            .next_render_frame = std.mem.readInt(u64, bytes[8..16], .big),
            .last_received_sequence = std.mem.readInt(
                u64,
                bytes[16..24],
                .big,
            ),
            .underrun_count = std.mem.readInt(u32, bytes[24..28], .big),
        };
    }
};

pub const ProtocolErrorCode = enum(u16) {
    malformed_message = 1,
    invalid_body = 2,
    unexpected_message = 3,
    invalid_state = 4,
    unsupported_operation = 5,
    stream_unavailable = 6,
    internal_error = 7,
};

// Wire layout:
//   error_code              u16
//   offending_message_type  u16
//   offending_sequence      u64
//   detail_len              u16
//   detail                  u8[detail_len]
pub const ProtocolErrorBody = struct {
    pub const fixed_wire_len: u32 = 14;
    pub const max_detail_len: u16 = 4096;
    pub const max_wire_len = fixed_wire_len + max_detail_len;

    error_code: ProtocolErrorCode,
    offending_message_type: u16,
    offending_sequence: u64,
    detail: []const u8,

    pub fn encode(self: ProtocolErrorBody, out: []u8) ![]u8 {
        const encoded_len = fixed_wire_len + self.detail.len;
        if (encoded_len > out.len) return error.BufferTooSmall;

        try validateProtocolErrorDetail(self.detail);

        std.mem.writeInt(
            u16,
            out[0..2],
            @intFromEnum(self.error_code),
            .big,
        );
        std.mem.writeInt(
            u16,
            out[2..4],
            self.offending_message_type,
            .big,
        );
        std.mem.writeInt(
            u64,
            out[4..12],
            self.offending_sequence,
            .big,
        );
        std.mem.writeInt(u16, out[12..14], @intCast(self.detail.len), .big);
        @memcpy(out[14..encoded_len], self.detail);

        return out[0..encoded_len];
    }

    pub fn decode(bytes: []const u8) ProtocolError!ProtocolErrorBody {
        if (bytes.len < fixed_wire_len or bytes.len > max_wire_len) {
            return error.InvalidBodyLength;
        }

        const detail_len = std.mem.readInt(u16, bytes[12..14], .big);
        if (bytes.len != fixed_wire_len + detail_len) {
            return error.InvalidBodyLength;
        }

        const detail = bytes[fixed_wire_len..];
        try validateProtocolErrorDetail(detail);

        return .{
            .error_code = try decodeProtocolErrorCode(
                std.mem.readInt(u16, bytes[0..2], .big),
            ),
            .offending_message_type = std.mem.readInt(
                u16,
                bytes[2..4],
                .big,
            ),
            .offending_sequence = std.mem.readInt(u64, bytes[4..12], .big),
            .detail = detail,
        };
    }
};

fn decodeMessageType(value: u16) ProtocolError!MessageType {
    return switch (value) {
        1 => .hello,
        2 => .hello_ack,
        3 => .start_stream,
        4 => .stream_info,
        5 => .audio_frame,
        6 => .buffer_status,
        7 => .cancel_generation,
        8 => .stream_end,
        9 => .protocol_error,
        10 => .ping,
        11 => .pong,
        else => error.InvalidMessageType,
    };
}

fn decodeProtocolErrorCode(value: u16) ProtocolError!ProtocolErrorCode {
    return switch (value) {
        1 => .malformed_message,
        2 => .invalid_body,
        3 => .unexpected_message,
        4 => .invalid_state,
        5 => .unsupported_operation,
        6 => .stream_unavailable,
        7 => .internal_error,
        else => error.InvalidProtocolErrorCode,
    };
}

fn validateProtocolErrorDetail(detail: []const u8) ProtocolError!void {
    if (detail.len > ProtocolErrorBody.max_detail_len) {
        return error.InvalidProtocolErrorDetail;
    }

    if (!std.unicode.utf8ValidateSlice(detail)) {
        return error.InvalidProtocolErrorDetail;
    }

    if (std.mem.indexOfScalar(u8, detail, 0) != null) {
        return error.InvalidProtocolErrorDetail;
    }
}

fn decodeSampleFormat(value: u16) ProtocolError!SampleFormat {
    return switch (value) {
        1 => .pcm_s16le,
        2 => .pcm_s24le_packed,
        3 => .pcm_s24le_in_s32le,
        4 => .pcm_s32le,
        5 => .pcm_f32le,
        else => error.UnsupportedSampleFormat,
    };
}

test "header encodes the expected wire representation" {
    const header = Header{
        .message_type = .audio_frame,
        .body_len = 256,
        .stream_id = 1,
        .generation_id = 2,
        .sequence = 3,
    };

    const bytes = try header.encode();

    try std.testing.expectEqualSlices(u8, "LSTN", bytes[0..4]);
    try std.testing.expectEqual(
        protocol_version,
        std.mem.readInt(u16, bytes[4..6], .big),
    );
    try std.testing.expectEqual(
        header_wire_len,
        std.mem.readInt(u16, bytes[10..12], .big),
    );
    try std.testing.expectEqual(
        @as(u32, 256),
        std.mem.readInt(u32, bytes[12..16], .big),
    );
}

test "header round trip" {
    const expected = Header{
        .message_type = .buffer_status,
        .body_len = BufferStatus.wire_len,
        .stream_id = 42,
        .generation_id = 7,
        .sequence = 99,
    };

    const bytes = try expected.encode();
    const actual = try Header.decode(&bytes);

    try std.testing.expectEqual(expected.version, actual.version);
    try std.testing.expectEqual(expected.message_type, actual.message_type);
    try std.testing.expectEqual(expected.flags, actual.flags);
    try std.testing.expectEqual(expected.body_len, actual.body_len);
    try std.testing.expectEqual(expected.stream_id, actual.stream_id);
    try std.testing.expectEqual(expected.generation_id, actual.generation_id);
    try std.testing.expectEqual(expected.sequence, actual.sequence);
}

test "header rejects malformed input" {
    const header = Header{
        .message_type = .hello,
        .body_len = 0,
    };
    const valid = try header.encode();

    try std.testing.expectError(
        error.InvalidHeaderLength,
        Header.decode(valid[0 .. header_wire_len - 1]),
    );

    var invalid_magic = valid;
    invalid_magic[0] = 'X';
    try std.testing.expectError(
        error.InvalidMagic,
        Header.decode(&invalid_magic),
    );

    var invalid_flags = valid;
    std.mem.writeInt(u16, invalid_flags[8..10], 1, .big);
    try std.testing.expectError(
        error.InvalidFlags,
        Header.decode(&invalid_flags),
    );

    var oversized_body = valid;
    std.mem.writeInt(
        u32,
        oversized_body[12..16],
        max_body_len + 1,
        .big,
    );
    try std.testing.expectError(
        error.BodyTooLarge,
        Header.decode(&oversized_body),
    );

    var unknown_message_type = valid;
    std.mem.writeInt(u16, unknown_message_type[6..8], 500, .big);
    try std.testing.expectError(
        error.InvalidMessageType,
        Header.decode(&unknown_message_type),
    );
}

test "start stream encodes expected wire representation" {
    const start = StartStream{
        .requested_start_frame = 48_000,
        .playback_id = "playback-1",
        .media_path = "/music/song.flac",
    };

    var storage: [StartStream.max_wire_len]u8 = undefined;
    const encoded = try start.encode(&storage);

    try std.testing.expectEqual(
        StartStream.fixed_wire_len + start.playback_id.len + start.media_path.len,
        encoded.len,
    );
    try std.testing.expectEqual(
        @as(u64, 48_000),
        std.mem.readInt(u64, encoded[0..8], .big),
    );
    try std.testing.expectEqual(
        start.playback_id.len,
        std.mem.readInt(u16, encoded[8..10], .big),
    );
    try std.testing.expectEqual(
        start.media_path.len,
        std.mem.readInt(u16, encoded[10..12], .big),
    );
    try std.testing.expectEqualSlices(
        u8,
        start.playback_id,
        encoded[StartStream.fixed_wire_len .. StartStream.fixed_wire_len + start.playback_id.len],
    );
    try std.testing.expectEqualSlices(
        u8,
        start.media_path,
        encoded[StartStream.fixed_wire_len + start.playback_id.len ..],
    );
}

test "start stream decode rejects invalid media paths" {
    var empty_path: [StartStream.fixed_wire_len + 10]u8 = @splat(0);
    std.mem.writeInt(u16, empty_path[8..10], 10, .big);
    @memcpy(empty_path[StartStream.fixed_wire_len..], "playback-1");
    try std.testing.expectError(
        error.InvalidMediaPath,
        StartStream.decode(&empty_path),
    );

    var nul_path: [StartStream.fixed_wire_len + 13]u8 = @splat(0);
    std.mem.writeInt(u16, nul_path[8..10], 10, .big);
    std.mem.writeInt(u16, nul_path[10..12], 3, .big);
    @memcpy(nul_path[StartStream.fixed_wire_len .. StartStream.fixed_wire_len + 10], "playback-1");
    @memcpy(nul_path[StartStream.fixed_wire_len + 10 ..], "a\x00b");
    try std.testing.expectError(
        error.InvalidMediaPath,
        StartStream.decode(&nul_path),
    );

    var invalid_utf8: [StartStream.fixed_wire_len + 11]u8 = @splat(0);
    std.mem.writeInt(u16, invalid_utf8[8..10], 10, .big);
    std.mem.writeInt(u16, invalid_utf8[10..12], 1, .big);
    @memcpy(invalid_utf8[StartStream.fixed_wire_len .. StartStream.fixed_wire_len + 10], "playback-1");
    invalid_utf8[StartStream.fixed_wire_len + 10] = 0xff;
    try std.testing.expectError(
        error.InvalidMediaPath,
        StartStream.decode(&invalid_utf8),
    );
}

test "start stream decode rejects invalid playback ids" {
    var empty_playback_id: [StartStream.fixed_wire_len + 16]u8 = @splat(0);
    std.mem.writeInt(u16, empty_playback_id[10..12], 16, .big);
    @memcpy(empty_playback_id[StartStream.fixed_wire_len..], "/music/song.flac");
    try std.testing.expectError(
        error.InvalidPlaybackId,
        StartStream.decode(&empty_playback_id),
    );

    var nul_playback_id: [StartStream.fixed_wire_len + 3 + 16]u8 = @splat(0);
    std.mem.writeInt(u16, nul_playback_id[8..10], 3, .big);
    std.mem.writeInt(u16, nul_playback_id[10..12], 16, .big);
    @memcpy(nul_playback_id[StartStream.fixed_wire_len .. StartStream.fixed_wire_len + 3], "a\x00b");
    @memcpy(nul_playback_id[StartStream.fixed_wire_len + 3 ..], "/music/song.flac");
    try std.testing.expectError(
        error.InvalidPlaybackId,
        StartStream.decode(&nul_playback_id),
    );
}

test "message bodies round trip" {
    const stream_info = StreamInfo{
        .format = .pcm_s24le_packed,
        .sample_rate = 96_000,
        .channels = 2,
        .channel_layout = 3,
        .total_frames = 1_000_000,
        .actual_start_frame = 48_000,
        .recommended_buffer_frames = 24_000,
    };
    const stream_info_bytes = stream_info.encode();
    const decoded_stream_info = try StreamInfo.decode(&stream_info_bytes);
    try std.testing.expectEqualDeep(stream_info, decoded_stream_info);

    const audio_data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const audio_frame = AudioFrame{
        .frame_offset = 48_000,
        .frame_count = 1,
        .audio_data = &audio_data,
    };
    var audio_frame_storage: [AudioFrame.max_wire_len]u8 = undefined;
    const audio_frame_bytes = try audio_frame.encode(&audio_frame_storage);
    const decoded_audio_frame = try AudioFrame.decode(audio_frame_bytes);
    try std.testing.expectEqual(
        audio_frame.frame_offset,
        decoded_audio_frame.frame_offset,
    );
    try std.testing.expectEqual(
        audio_frame.frame_count,
        decoded_audio_frame.frame_count,
    );
    try std.testing.expectEqualSlices(
        u8,
        audio_frame.audio_data,
        decoded_audio_frame.audio_data,
    );

    const buffer_status = BufferStatus{
        .buffered_frames = 24_000,
        .credit_frames = 24_000,
        .next_render_frame = 72_000,
        .last_received_sequence = 50,
        .underrun_count = 0,
    };
    const buffer_status_bytes = buffer_status.encode();
    const decoded_buffer_status = try BufferStatus.decode(&buffer_status_bytes);
    try std.testing.expectEqualDeep(buffer_status, decoded_buffer_status);

    const protocol_error = ProtocolErrorBody{
        .error_code = .unsupported_operation,
        .offending_message_type = @intFromEnum(MessageType.start_stream),
        .offending_sequence = 51,
        .detail = "seeking is not implemented",
    };
    var protocol_error_storage: [ProtocolErrorBody.max_wire_len]u8 = undefined;
    const protocol_error_bytes = try protocol_error.encode(
        &protocol_error_storage,
    );
    const decoded_protocol_error = try ProtocolErrorBody.decode(
        protocol_error_bytes,
    );
    try std.testing.expectEqual(
        protocol_error.error_code,
        decoded_protocol_error.error_code,
    );
    try std.testing.expectEqual(
        protocol_error.offending_message_type,
        decoded_protocol_error.offending_message_type,
    );
    try std.testing.expectEqual(
        protocol_error.offending_sequence,
        decoded_protocol_error.offending_sequence,
    );
    try std.testing.expectEqualSlices(
        u8,
        protocol_error.detail,
        decoded_protocol_error.detail,
    );
}

test "protocol error body rejects malformed input" {
    const valid = ProtocolErrorBody{
        .error_code = .invalid_body,
        .offending_message_type = @intFromEnum(MessageType.buffer_status),
        .offending_sequence = 12,
        .detail = "invalid body length",
    };
    var storage: [ProtocolErrorBody.max_wire_len]u8 = undefined;
    const encoded = try valid.encode(&storage);

    var invalid_code: [ProtocolErrorBody.fixed_wire_len]u8 = @splat(0);
    std.mem.writeInt(u16, invalid_code[0..2], 500, .big);
    try std.testing.expectError(
        error.InvalidProtocolErrorCode,
        ProtocolErrorBody.decode(&invalid_code),
    );

    try std.testing.expectError(
        error.InvalidBodyLength,
        ProtocolErrorBody.decode(encoded[0 .. encoded.len - 1]),
    );

    const invalid_utf8 = ProtocolErrorBody{
        .error_code = .invalid_body,
        .offending_message_type = @intFromEnum(MessageType.buffer_status),
        .offending_sequence = 12,
        .detail = &.{0xff},
    };
    try std.testing.expectError(
        error.InvalidProtocolErrorDetail,
        invalid_utf8.encode(&storage),
    );
}
