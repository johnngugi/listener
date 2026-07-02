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

pub fn connect(io: std.Io, config: Config) !void {
    const address = try net.IpAddress.parse(config.host, config.port);
    var connection = try address.connect(io, .{
        .mode = net.Socket.Mode.stream,
        .protocol = net.Protocol.tcp,
    });
    defer connection.close(io);

    std.debug.print(
        "Connected to {s}:{d} ...\n",
        .{ config.host, config.port },
    );

    var stream_writer = connection.writer(io, &.{});
    var writer = &stream_writer.interface;

    var read_buffer: [1024]u8 = undefined;
    var stream_reader = connection.reader(io, &read_buffer);

    // send hello for a start
    const header = lstn_protocol.Header{
        .message_type = lstn_protocol.MessageType.hello,
        .body_len = 0,
        .sequence = 1,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);

    try readHelloAck(&stream_reader.interface);
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
