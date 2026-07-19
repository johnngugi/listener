const std = @import("std");
const connection = @import("connection.zig");
const stdout = @import("stdout");

pub const BufferStatusEvent = connection.BufferStatusEvent;
pub const Hooks = connection.Hooks;
pub const StartStreamEvent = connection.StartStreamEvent;

const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;

pub const Config = struct {
    host: []const u8,
    port: u16,
};

pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    hooks: Hooks,
    config: Config,
) !void {
    const address = try std.Io.net.IpAddress.parse(config.host, config.port);

    var listener = try address.listen(io, .{
        .mode = Socket.Mode.stream,
        .protocol = Protocol.tcp,
        .reuse_address = true,
    });
    defer listener.deinit(io);

    stdout.print(
        io,
        "Listening on {s}:{d} ...\n",
        .{ config.host, config.port },
    );

    while (true) {
        const stream = try listener.accept(io);

        const thread = std.Thread.spawn(.{}, connection.handle, .{ io, stream, allocator, hooks }) catch |err| {
            stdout.print(io, "Failed to spawn connection: {}\n", .{err});
            stream.close(io);
            continue;
        };

        thread.detach();
    }
}
