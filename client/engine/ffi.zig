const std = @import("std");
const client = @import("lstn/client.zig");

pub export fn listener_engine_abi_version() u32 {
    return 1;
}

pub export fn listener_engine_send_hello() void {
    const allocator = std.heap.smp_allocator;
    var engine = Engine.init(allocator);
    defer engine.deinit();

    const io = engine.io();
    client.connect(io, .{
        .host = "127.0.0.1",
        .port = 5778,
    }) catch |err| {
        std.debug.print("listener_engine_send_hello failed: {}\n", .{err});
    };
}

const Engine = struct {
    allocator: std.mem.Allocator,
    threaded: std.Io.Threaded,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .allocator = allocator,
            .threaded = .init(allocator, .{}),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.threaded.deinit();
    }

    pub fn io(self: *Engine) std.Io {
        return self.threaded.io();
    }
};
