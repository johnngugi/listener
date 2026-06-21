const std = @import("std");

const server = @import("server.zig");

pub fn main(init: std.process.Init) !void {
    try server.run(init.io, init.gpa, .{
        .host = "127.0.0.1",
        .port = 5778,
    });
}
