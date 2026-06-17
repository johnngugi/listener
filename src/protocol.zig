const std = @import("std");

pub const magic = "LSTN".*;
pub const protocol_version: u16 = 1;
pub const header_wire_len: u16 = 40;
pub const max_body_len: u32 = 1024 * 1024;

pub const ProtocolError = error{
    InvalidMagic,
    UnsupportedVersion,
    InvalidHeaderLength,
    InvalidBodyLength,
    InvalidMessageType,
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

pub const AudioFrame = struct {
    pub const wire_len: u32 = 12;

    sample_offset: u64,
    frame_count: u32,

    pub fn encode(self: AudioFrame) [wire_len]u8 {
        var out: [wire_len]u8 = undefined;

        std.mem.writeInt(u64, out[0..8], self.sample_offset, .big);
        std.mem.writeInt(u32, out[8..12], self.frame_count, .big);

        return out;
    }

    pub fn decode(bytes: []const u8) ProtocolError!AudioFrame {
        if (bytes.len != wire_len) return error.InvalidBodyLength;

        return .{
            .sample_offset = std.mem.readInt(u64, bytes[0..8], .big),
            .frame_count = std.mem.readInt(u32, bytes[8..12], .big),
        };
    }
};

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
        .flags = 3,
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

    const audio_frame = AudioFrame{
        .sample_offset = 48_000,
        .frame_count = 960,
    };
    const audio_frame_bytes = audio_frame.encode();
    const decoded_audio_frame = try AudioFrame.decode(&audio_frame_bytes);
    try std.testing.expectEqualDeep(audio_frame, decoded_audio_frame);

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
}
