const std = @import("std");

const client_engine = @import("client_engine");
const selected_output = @import("selected_output");
const server = @import("server");

test "client engine streams PCM from the real server implementation" {
    const allocator = std.testing.allocator;

    selected_output.reset(allocator);
    defer selected_output.reset(allocator);

    var server_io_thread: std.Io.Threaded = .init(allocator, .{});
    defer server_io_thread.deinit();

    const server_io = server_io_thread.io();
    const cwd = std.Io.Dir.cwd();
    const expected_pcm = try cwd.readFileAlloc(
        server_io,
        "server/testdata/fixtures/strict-s16le-stereo.expected.pcm",
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(expected_pcm);

    const listen_address = std.Io.net.IpAddress{ .ip4 = .loopback(0) };
    var listener = try listen_address.listen(server_io, .{
        .mode = .stream,
        .protocol = .tcp,
        .reuse_address = true,
    });
    var listener_closed = false;
    defer if (!listener_closed) listener.deinit(server_io);

    var test_server = TestServer{
        .io = server_io,
        .listener = &listener,
        .allocator = allocator,
    };
    const server_thread = try std.Thread.spawn(.{}, TestServer.acceptOne, .{&test_server});
    var server_thread_joined = false;
    defer if (!server_thread_joined) {
        if (!listener_closed) {
            listener.deinit(server_io);
            listener_closed = true;
        }
        server_thread.join();
    };

    const engine = client_engine.listener_engine_create() orelse return error.EngineCreateFailed;
    var engine_destroyed = false;
    defer if (!engine_destroyed) client_engine.listener_engine_destroy(engine);

    try expectStatusOk(client_engine.listener_engine_connect(
        engine,
        "127.0.0.1".ptr,
        "127.0.0.1".len,
        listener.socket.address.getPort(),
    ));

    const media_path = try cwd.realPathFileAlloc(
        server_io,
        "server/testdata/fixtures/strict-s16le-stereo.flac",
        allocator,
    );
    defer allocator.free(media_path);

    try expectStatusOk(client_engine.listener_engine_start_stream(
        engine,
        0,
        "integration-playback".ptr,
        "integration-playback".len,
        media_path.ptr,
        media_path.len,
    ));

    try selected_output.waitForCapturedBytes(expected_pcm.len, 1_000_000);
    try expectStatusOk(client_engine.listener_engine_stop(engine));

    const actual_pcm = try selected_output.capturedBytes(allocator);
    defer allocator.free(actual_pcm);

    try std.testing.expectEqualSlices(u8, expected_pcm, actual_pcm);

    client_engine.listener_engine_destroy(engine);
    engine_destroyed = true;

    server_thread.join();
    server_thread_joined = true;
    try test_server.result;
}

const TestServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    allocator: std.mem.Allocator,
    result: anyerror!void = {},

    fn acceptOne(self: *TestServer) void {
        self.result = acceptOneImpl(self);
    }

    fn acceptOneImpl(self: *TestServer) !void {
        const stream = try self.listener.accept(self.io);
        try server.connection.handle(self.io, stream, self.allocator, .{});
    }
};

fn expectStatusOk(status: client_engine.ListenerStatus) !void {
    try std.testing.expectEqual(client_engine.ListenerStatus.ok, status);
}
