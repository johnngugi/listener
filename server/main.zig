const std = @import("std");

const grpc_server = @import("grpc/server.zig");
const lstn_server = @import("lstn/server.zig");
const playback = @import("playback.zig");

const Config = struct {
    lstn_host: []const u8 = "127.0.0.1",
    lstn_port: u16 = 5778,
    grpc_address: [:0]const u8 = "127.0.0.1:5779",
};

pub fn main(init: std.process.Init) !void {
    const config = Config{};

    var controller = playback.Controller.init(init.gpa);

    var grpc = grpc_server.Server.init(.{
        .address = config.grpc_address,
    }) catch |err| {
        controller.deinit();
        return err;
    };

    const grpc_thread = std.Thread.spawn(
        .{},
        runGrpcControlLoop,
        .{ &grpc, init.gpa, &controller },
    ) catch |err| {
        grpc.deinit();
        controller.deinit();
        return err;
    };
    grpc_thread.detach();

    std.debug.print(
        "gRPC control listening on {s} ...\n",
        .{config.grpc_address},
    );

    try lstn_server.run(init.io, init.gpa, .{
        .context = &controller,
        .on_start_stream = onLstnStartStream,
        .on_buffer_status = onLstnBufferStatus,
    }, .{
        .host = config.lstn_host,
        .port = config.lstn_port,
    });
}

fn onLstnStartStream(
    context: ?*anyopaque,
    event: lstn_server.StartStreamEvent,
) anyerror!void {
    const controller: *playback.Controller = @ptrCast(@alignCast(context.?));
    _ = controller.bindStream(.{
        .playback_id = event.playback_id,
        .media_path = event.media_path,
        .stream_id = event.stream_id,
        .generation_id = event.generation_id,
        .start_frame = event.start_frame,
    }) catch |err| return switch (err) {
        error.PlaybackNotFound,
        error.InvalidState,
        error.UnsupportedOperation,
        => error.StartStreamRejected,
    };
}

fn onLstnBufferStatus(
    context: ?*anyopaque,
    event: lstn_server.BufferStatusEvent,
) void {
    const controller: *playback.Controller = @ptrCast(@alignCast(context.?));
    _ = controller.updateSession(.{
        .playback_id = event.playback_id,
        .current_frame = event.next_render_frame,
        .generation_id = event.generation_id,
    }) catch {};
}

fn runGrpcControlLoop(
    server: *grpc_server.Server,
    allocator: std.mem.Allocator,
    controller: *playback.Controller,
) void {
    server.runUnaryControlLoop(allocator, controller) catch |err| {
        std.debug.print("gRPC control loop stopped: {}\n", .{err});
    };
}
