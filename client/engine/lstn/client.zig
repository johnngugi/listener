const std = @import("std");
const net = std.Io.net;

const lstn_protocol = @import("lstn_protocol");

pub const ClientError = error{
    UnexpectedHelloAck,
    UnexpectedHelloAckBody,
    UnexpectedStreamInfo,
    UnexpectedStreamScope,
    StartStreamRejected,
};

pub const Config = struct {
    host: []const u8,
    port: u16,
};

pub const Connection = struct {
    io: std.Io,
    connection: net.Stream,
    next_client_sequence: u64 = 2,
    next_stream_id: u64 = 1,
    next_generation_id: u64 = 1,

    pub fn connect(io: std.Io, config: Config) !Connection {
        const address = try net.IpAddress.parse(config.host, config.port);
        const connection = try address.connect(io, .{
            .mode = net.Socket.Mode.stream,
            .protocol = net.Protocol.tcp,
        });

        var result = Connection{
            .io = io,
            .connection = connection,
        };
        errdefer result.connection.close(io);

        try result.handshake();
        return result;
    }

    pub fn close(self: *Connection) void {
        self.connection.close(self.io);
    }

    pub fn startStream(
        self: *Connection,
        message: lstn_protocol.StartStream,
    ) !lstn_protocol.StreamInfo {
        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        var read_buffer: [1024]u8 = undefined;
        var stream_reader = self.connection.reader(self.io, &read_buffer);
        const reader = &stream_reader.interface;

        const stream_id = self.next_stream_id;
        const generation_id = self.next_generation_id;

        try sendStartStream(writer, .{
            .message = message,
            .stream_id = stream_id,
            .generation_id = generation_id,
            .sequence = self.next_client_sequence,
        });

        self.next_client_sequence += 1;
        self.next_stream_id += 1;
        self.next_generation_id += 1;

        return try readStreamInfo(reader, stream_id, generation_id);
    }

    fn handshake(self: *Connection) !void {
        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        var read_buffer: [1024]u8 = undefined;
        var stream_reader = self.connection.reader(self.io, &read_buffer);
        const reader = &stream_reader.interface;

        try sendHello(writer);
        try readHelloAck(reader);
        std.debug.print("Received HELLO_ACK\n", .{});
    }

};

const StartStreamRequest = struct {
    message: lstn_protocol.StartStream,
    stream_id: u64,
    generation_id: u64,
    sequence: u64,
};

fn sendHello(writer: *std.Io.Writer) !void {
    const header = lstn_protocol.Header{
        .message_type = lstn_protocol.MessageType.hello,
        .body_len = 0,
        .sequence = 1,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);
}

fn readHelloAck(reader: *std.Io.Reader) !void {
    var header_bytes: [lstn_protocol.header_wire_len]u8 = undefined;
    try reader.readSliceAll(&header_bytes);

    const header = try lstn_protocol.Header.decode(&header_bytes);
    if (header.message_type != .hello_ack) {
        return ClientError.UnexpectedHelloAck;
    }
    if (header.body_len != 0) {
        return ClientError.UnexpectedHelloAckBody;
    }
}

fn sendStartStream(
    writer: *std.Io.Writer,
    request: StartStreamRequest,
) !void {
    var body_storage: [lstn_protocol.StartStream.max_wire_len]u8 = undefined;
    const body = try request.message.encode(&body_storage);

    const header = lstn_protocol.Header{
        .message_type = .start_stream,
        .body_len = @intCast(body.len),
        .stream_id = request.stream_id,
        .generation_id = request.generation_id,
        .sequence = request.sequence,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);
    try writer.writeAll(body);
}

fn readStreamInfo(
    reader: *std.Io.Reader,
    stream_id: u64,
    generation_id: u64,
) !lstn_protocol.StreamInfo {
    var header_bytes: [lstn_protocol.header_wire_len]u8 = undefined;
    try reader.readSliceAll(&header_bytes);

    const header = try lstn_protocol.Header.decode(&header_bytes);
    if (header.stream_id != stream_id or header.generation_id != generation_id) {
        return ClientError.UnexpectedStreamScope;
    }

    switch (header.message_type) {
        .stream_info => {
            var body: [lstn_protocol.StreamInfo.wire_len]u8 = undefined;
            if (header.body_len != body.len) {
                return error.InvalidBodyLength;
            }

            try reader.readSliceAll(&body);
            return try lstn_protocol.StreamInfo.decode(&body);
        },
        .protocol_error => {
            var body: [lstn_protocol.ProtocolErrorBody.max_wire_len]u8 = undefined;
            if (header.body_len > body.len) {
                return error.InvalidBodyLength;
            }

            try reader.readSliceAll(body[0..header.body_len]);
            return ClientError.StartStreamRejected;
        },
        else => return ClientError.UnexpectedStreamInfo,
    }
}
