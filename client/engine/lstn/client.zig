const std = @import("std");
const net = std.Io.net;

const lstn_protocol = @import("lstn_protocol");

pub const ClientError = error{
    UnexpectedHelloAck,
    UnexpectedHelloAckBody,
};

pub const Config = struct {
    host: []const u8,
    port: u16,
};

pub const Connection = struct {
    io: std.Io,
    connection: net.Stream,

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
