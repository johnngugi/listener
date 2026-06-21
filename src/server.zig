const std = @import("std");
const connection = @import("connection.zig");

const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;

pub const Config = struct {
    host: []const u8,
    port: u16,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, config: Config) !void {
    const address = try std.Io.net.IpAddress.parse(config.host, config.port);

    var listener = try address.listen(io, .{
        .mode = Socket.Mode.stream,
        .protocol = Protocol.tcp,
    });
    defer listener.deinit(io);

    std.debug.print(
        "Listening on {s}:{d} ...\n",
        .{ config.host, config.port },
    );

    while (true) {
        const stream = try listener.accept(io);

        const thread = std.Thread.spawn(.{}, connection.handle, .{ io, stream, allocator }) catch |err| {
            std.debug.print("Failed to spawn connection: {}\n", .{err});
            stream.close(io);
            continue;
        };

        thread.detach();
    }
}
