const std = @import("std");
const lstn = @import("lstn/client.zig");

pub export fn listener_engine_abi_version() u32 {
    return 1;
}

pub export fn listener_engine_create() ?*Engine {
    const allocator = std.heap.smp_allocator;
    const engine = allocator.create(Engine) catch return null;
    engine.* = Engine.init(allocator);
    return engine;
}

pub export fn listener_engine_destroy(engine_ptr: ?*Engine) void {
    const engine = engine_ptr orelse return;
    const allocator = engine.allocator;
    engine.deinit();
    allocator.destroy(engine);
}

pub export fn listener_engine_connect(
    engine_ptr: ?*Engine,
    host_ptr: [*]const u8,
    host_len: usize,
    port: u16,
) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;
    if (host_len == 0) return .invalid_argument;

    const host = host_ptr[0..host_len];
    const config = lstn.Config{
        .host = host,
        .port = port,
    };

    engine.connect(config) catch |err| {
        std.debug.print("listener_engine_connect failed: {}\n", .{err});
        return status_from_error(err);
    };

    std.debug.print(
        "Connected to {s}:{d} ...\n",
        .{ config.host, config.port },
    );

    return .ok;
}

fn status_from_error(err: anyerror) ListenerStatus {
    return switch (err) {
        error.AlreadyConnected => .already_connected,

        error.InvalidEnd,
        error.InvalidCharacter,
        error.Overflow,
        error.Incomplete,
        error.NonCanonical,
        error.ParseFailed,
        error.UnresolvedScope,
        => .invalid_host,

        error.AddressUnavailable,
        error.AddressFamilyUnsupported,
        error.ConnectionPending,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.HostUnreachable,
        error.NetworkUnreachable,
        error.Timeout,
        error.OptionUnsupported,
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        error.ProtocolUnsupportedBySystem,
        error.ProtocolUnsupportedByAddressFamily,
        error.SocketModeUnsupported,
        error.AccessDenied,
        error.WouldBlock,
        error.NetworkDown,
        error.SystemResources,
        => .connect_failed,

        error.EndOfStream,
        error.ReadFailed,
        error.WriteFailed,
        error.SocketUnconnected,
        => .handshake_failed,

        error.UnexpectedHelloAck,
        error.UnexpectedHelloAckBody,
        error.InvalidMagic,
        error.InvalidFlags,
        error.UnsupportedVersion,
        error.InvalidHeaderLength,
        error.InvalidBodyLength,
        error.BodyTooLarge,
        error.InvalidMessageType,
        => .protocol_error,

        error.OutOfMemory => .out_of_memory,

        else => .unexpected,
    };
}

pub const ListenerStatus = enum(u32) {
    ok = 0,
    null_engine = 1,
    invalid_argument = 2,
    already_connected = 3,
    invalid_host = 4,
    connect_failed = 5,
    handshake_failed = 6,
    protocol_error = 7,
    out_of_memory = 8,
    unexpected = 255,
};

const Engine = struct {
    allocator: std.mem.Allocator,
    io_thread: std.Io.Threaded,
    lstn_connection: ?lstn.Connection = null,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .allocator = allocator,
            .io_thread = .init(allocator, .{}),
        };
    }

    pub fn connect(self: *Engine, config: lstn.Config) !void {
        if (self.lstn_connection != null) return error.AlreadyConnected;
        self.lstn_connection = try lstn.Connection.connect(self.io(), config);
    }

    pub fn deinit(self: *Engine) void {
        if (self.lstn_connection) |*conn| {
            conn.close();
        }

        self.io_thread.deinit();
    }

    pub fn io(self: *Engine) std.Io {
        return self.io_thread.io();
    }
};
