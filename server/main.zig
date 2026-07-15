const std = @import("std");

const grpc_server = @import("grpc/server.zig");
const lstn_server = @import("lstn/server.zig");
const playback = @import("playback.zig");
const library_scan = @import("library/scan.zig");
const library_service = @import("library/service.zig");
const sqlite = @import("library/sqlite.zig");

const Config = struct {
    lstn_host: []const u8 = "127.0.0.1",
    lstn_port: u16 = 5778,
    grpc_address: [:0]const u8 = "127.0.0.1:5779",
    library_database_path: [:0]const u8 = "listener.db",
};

pub fn main(init: std.process.Init) !void {
    const config = Config{};

    const home = init.environ_map.get("HOME") orelse return error.HomeNotSet;
    const library_root = try std.fs.path.join(init.gpa, &.{ home, "Music" });
    defer init.gpa.free(library_root);

    var library_db = try sqlite.open(init.gpa, config.library_database_path, .{});
    defer library_db.deinit();
    try library_db.migrate();
    try library_scan.scanLibrary(library_root, init.io, init.gpa, library_db);

    var library_api = library_service.Service.init(library_db);

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
        .{ &grpc, init.gpa, &controller, &library_api },
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
    library_api: *const library_service.Service,
) void {
    server.runUnaryControlLoop(allocator, controller, library_api) catch |err| {
        std.debug.print("gRPC control loop stopped: {}\n", .{err});
    };
}
