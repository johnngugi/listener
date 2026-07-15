const std = @import("std");

var mutex: std.Io.Mutex = .init;

pub fn print(io: std.Io, comptime format: []const u8, args: anytype) void {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);

    var buffer: [256]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(io, &buffer);
    const writer = &file_writer.interface;
    writer.print(format, args) catch return;
    writer.flush() catch {};
}

pub fn printGlobal(comptime format: []const u8, args: anytype) void {
    print(std.Io.Threaded.global_single_threaded.io(), format, args);
}
