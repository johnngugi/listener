const std = @import("std");

const grpc_server = @import("grpc/server.zig");
const lstn_server = @import("lstn/server.zig");
const playback = @import("playback.zig");
const library_scan = @import("library/scan.zig");
const library_service = @import("library/service.zig");
const sqlite = @import("library/sqlite.zig");
const stdout = @import("stdout");

const Config = struct {
    lstn_host: []const u8 = "127.0.0.1",
    lstn_port: u16 = 5778,
    grpc_address: [:0]const u8 = "127.0.0.1:5779",
    data_dir: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    const config = Config{};

    const home_dir = init.environ_map.get("HOME") orelse return error.HomeNotSet;
    const library_root = try std.fs.path.join(init.gpa, &.{ home_dir, "Music" });
    defer init.gpa.free(library_root);

    const configured_data_dir = config.data_dir orelse init.environ_map.get("LISTENER_DATA_DIR");

    const data_dir = if (configured_data_dir) |path|
        try init.gpa.dupe(u8, path)
    else blk: {
        break :blk try std.fs.path.join(init.gpa, &.{
            home_dir,
            "Library",
            "Application Support",
            "Listener",
        });
    };
    defer init.gpa.free(data_dir);

    if (!std.fs.path.isAbsolute(data_dir)) {
        return error.DataDirMustBeAbsolute;
    }

    try std.Io.Dir.cwd().createDirPath(init.io, data_dir);

    const database_path = try std.fs.path.joinZ(init.gpa, &.{
        data_dir,
        "listener.db",
    });
    defer init.gpa.free(database_path);

    const artwork_dir = try std.fs.path.join(init.gpa, &.{
        data_dir,
        "artwork",
        "original",
    });
    defer init.gpa.free(artwork_dir);

    try std.Io.Dir.cwd().createDirPath(init.io, artwork_dir);

    var library_db = try sqlite.open(init.gpa, database_path, .{});
    defer library_db.deinit();

    try library_db.migrate();
    try library_scan.scanLibrary(library_root, init.io, init.gpa, library_db, artwork_dir);

    var library_api = library_service.Service.init(library_db, init.io, artwork_dir);

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
        .{ &grpc, init.io, init.gpa, &controller, &library_api },
    ) catch |err| {
        grpc.deinit();
        controller.deinit();
        return err;
    };
    grpc_thread.detach();

    stdout.print(
        init.io,
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
    io: std.Io,
    allocator: std.mem.Allocator,
    controller: *playback.Controller,
    library_api: *const library_service.Service,
) void {
    server.runUnaryControlLoop(allocator, controller, library_api) catch |err| {
        stdout.print(io, "gRPC control loop stopped: {}\n", .{err});
    };
}
