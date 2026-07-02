const std = @import("std");
const Stream = std.Io.net.Stream;

const protocol = @import("lstn_protocol");

pub const RequestError = error{
    BodyBufferTooSmall,
    UnexpectedHelloBody,
    InvalidHelloHeader,
};

pub const Frame = struct {
    header: protocol.Header,
    body: []const u8,
};

pub const ClientMessage = union(enum) {
    hello: void,
    start_stream: protocol.StartStream,
    buffer_status: protocol.BufferStatus,
    cancel_generation: void,
    ping: void,
    pong: void,
};

pub const Request = struct {
    stream_id: u64,
    generation_id: u64,
    sequence: u64,
    message: ClientMessage,
};

pub fn read(reader: *std.Io.Reader, body_storage: []u8) !Frame {
    var header_bytes: [protocol.header_wire_len]u8 = undefined;

    try reader.readSliceAll(&header_bytes);

    const header = try protocol.Header.decode(&header_bytes);
    const body_len: usize = @intCast(header.body_len);

    if (body_len > body_storage.len) {
        return RequestError.BodyBufferTooSmall;
    }

    const body = body_storage[0..body_len];
    try reader.readSliceAll(body);

    return .{
        .header = header,
        .body = body,
    };
}

pub fn decodeRequest(frame: Frame) !Request {
    const message: ClientMessage = switch (frame.header.message_type) {
        .hello => blk: {
            if (frame.header.body_len != 0) {
                return error.InvalidBodyLength;
            }

            break :blk .{ .hello = {} };
        },
        .ping, .pong => |message_type| blk: {
            if (frame.header.body_len != 0) {
                return error.InvalidBodyLength;
            }

            break :blk switch (message_type) {
                .ping => .{ .ping = {} },
                .pong => .{ .pong = {} },
                else => unreachable,
            };
        },
        .cancel_generation => blk: {
            if (frame.body.len != 0)
                return error.InvalidBodyLength;

            break :blk .{ .cancel_generation = {} };
        },
        .buffer_status => .{
            .buffer_status = try protocol.BufferStatus.decode(frame.body),
        },
        .start_stream => .{
            .start_stream = try protocol.StartStream.decode(frame.body),
        },
        else => return error.UnexpectedClientMessage,
    };

    return .{
        .stream_id = frame.header.stream_id,
        .generation_id = frame.header.generation_id,
        .sequence = frame.header.sequence,
        .message = message,
    };
}

test "reads and decodes hello request" {
    const expected_header = protocol.Header{
        .message_type = .hello,
        .body_len = 0,
        .stream_id = 42,
        .generation_id = 7,
        .sequence = 3,
    };
    const bytes = try expected_header.encode();
    var reader: std.Io.Reader = .fixed(&bytes);
    var body_storage: [protocol.BufferStatus.wire_len]u8 = undefined;

    const frame = try read(&reader, &body_storage);
    const actual = try decodeRequest(frame);

    try std.testing.expectEqual(@as(u64, 42), actual.stream_id);
    try std.testing.expectEqual(@as(u64, 7), actual.generation_id);
    try std.testing.expectEqual(@as(u64, 3), actual.sequence);
    try std.testing.expect(actual.message == .hello);
}

test "reads and decodes buffer status request" {
    const expected_status = protocol.BufferStatus{
        .buffered_frames = 1024,
        .credit_frames = 2048,
        .next_render_frame = 4096,
        .last_received_sequence = 12,
        .underrun_count = 2,
    };
    const body = expected_status.encode();
    const header = protocol.Header{
        .message_type = .buffer_status,
        .body_len = protocol.BufferStatus.wire_len,
        .stream_id = 9,
        .generation_id = 4,
        .sequence = 13,
    };
    const header_bytes = try header.encode();

    var bytes: [protocol.header_wire_len + protocol.BufferStatus.wire_len]u8 = undefined;
    @memcpy(bytes[0..protocol.header_wire_len], &header_bytes);
    @memcpy(bytes[protocol.header_wire_len..], &body);

    var reader: std.Io.Reader = .fixed(&bytes);
    var body_storage: [protocol.BufferStatus.wire_len]u8 = undefined;

    const frame = try read(&reader, &body_storage);
    const actual = try decodeRequest(frame);

    try std.testing.expectEqual(@as(u64, 9), actual.stream_id);
    try std.testing.expectEqual(@as(u64, 4), actual.generation_id);
    try std.testing.expectEqual(@as(u64, 13), actual.sequence);
    try std.testing.expect(actual.message == .buffer_status);
    try std.testing.expectEqual(
        expected_status,
        actual.message.buffer_status,
    );
}

test "read rejects a body larger than its storage" {
    const header = protocol.Header{
        .message_type = .buffer_status,
        .body_len = protocol.BufferStatus.wire_len,
    };
    const bytes = try header.encode();
    var reader: std.Io.Reader = .fixed(&bytes);
    var body_storage: [protocol.BufferStatus.wire_len - 1]u8 = undefined;

    try std.testing.expectError(
        RequestError.BodyBufferTooSmall,
        read(&reader, &body_storage),
    );
}

test "read rejects a truncated header" {
    const bytes = [_]u8{0} ** (protocol.header_wire_len - 1);
    var reader: std.Io.Reader = .fixed(&bytes);
    var body_storage: [protocol.BufferStatus.wire_len]u8 = undefined;

    try std.testing.expectError(
        error.EndOfStream,
        read(&reader, &body_storage),
    );
}

test "decode rejects a body for an empty-body message" {
    const frame = Frame{
        .header = .{
            .message_type = .hello,
            .body_len = 1,
        },
        .body = &.{0},
    };

    try std.testing.expectError(
        error.InvalidBodyLength,
        decodeRequest(frame),
    );
}

test "decodes empty ping and pong requests" {
    inline for (.{ protocol.MessageType.ping, protocol.MessageType.pong }) |message_type| {
        const actual = try decodeRequest(.{
            .header = .{
                .message_type = message_type,
                .body_len = 0,
                .sequence = 7,
            },
            .body = &.{},
        });

        try std.testing.expect(switch (message_type) {
            .ping => actual.message == .ping,
            .pong => actual.message == .pong,
            else => unreachable,
        });
    }
}

test "decode rejects server messages from a client" {
    const frame = Frame{
        .header = .{
            .message_type = .hello_ack,
            .body_len = 0,
        },
        .body = &.{},
    };

    try std.testing.expectError(
        error.UnexpectedClientMessage,
        decodeRequest(frame),
    );
}
