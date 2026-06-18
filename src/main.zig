const std = @import("std");
const net = std.Io.net;

const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
});

const decoder = @import("decoder.zig");
const server = @import("server.zig");
const protocol = @import("protocol.zig");
const request = @import("request.zig");

pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.DebugAllocator(.{}){};
    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    const host = "127.0.0.1";
    const port = 5778;

    var s = try server.Server.init(init.io, host, port);
    var net_server = try s.listen();
    defer net_server.deinit(init.io);

    std.debug.print("Listening on {s}:{d} ...\n", .{ host, port });

    while (true) {
        const stream = try net_server.accept(init.io);

        const thread = std.Thread.spawn(.{}, handleClient, .{ init.io, stream }) catch |err| {
            std.debug.print("Failed to spawn thread: {}\n", .{err});
            stream.close(init.io);
            continue;
        };

        thread.detach();
    }
}

fn handleClient(io: std.Io, stream: net.Stream) !void {
    defer stream.close(io);

    var stream_buffer: [1024]u8 = undefined;
    var stream_reader = stream.reader(io, &stream_buffer);
    const reader = &stream_reader.interface;

    var stream_writer = stream.writer(io, &.{});
    const writer = &stream_writer.interface;

    var body_buffer: [protocol.BufferStatus.wire_len]u8 = undefined;
    var hello_received = false;

    while (true) {
        const frame = request.read(reader, &body_buffer) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const request_obj = try request.decodeRequest(frame);

        switch (request_obj.message) {
            .hello => {
                if (hello_received) return error.UnexpectedHello;
                try handleHello(writer);
                hello_received = true;
            },
            else => {
                if (!hello_received) return error.ExpectedHello;
                std.debug.print("todo: {}\n", .{request_obj.message});
            },
        }
    }
}

fn handleHello(writer: *std.Io.Writer) !void {
    const response_header = protocol.Header{
        .message_type = protocol.MessageType.hello_ack,
        .body_len = 0,
    };

    const response_bytes = try response_header.encode();
    try writer.writeAll(&response_bytes);
}
