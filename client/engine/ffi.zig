const std = @import("std");
const lstn = @import("lstn/client.zig");
const protocol = @import("lstn_protocol");
const backend = @import("audio_backend");
const ring_buffer = @import("audio_ring_buffer");
const selected_output = @import("selected_output");
const stdout = @import("stdout");

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
        stdout.print(engine.io(), "listener_engine_connect failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

pub export fn listener_engine_start_stream(
    engine_ptr: ?*Engine,
    requested_start_frame: u64,
    playback_id_ptr: ?[*]const u8,
    playback_id_len: usize,
) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;
    const playback_id_base = playback_id_ptr orelse return .invalid_argument;

    const start_stream = protocol.StartStream{
        .requested_start_frame = requested_start_frame,
        .playback_id = playback_id_base[0..playback_id_len],
    };

    start_stream.validate() catch |err| return status_from_error(err);

    engine.startStream(start_stream) catch |err| {
        stdout.print(engine.io(), "listener_engine_start_stream failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

pub export fn listener_engine_stop(engine_ptr: ?*Engine) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;

    engine.stopStream() catch |err| {
        stdout.print(engine.io(), "listener_engine_stop failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

pub export fn listener_engine_pause(engine_ptr: ?*Engine) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;

    engine.pauseStream() catch |err| {
        stdout.print(engine.io(), "listener_engine_pause failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

pub export fn listener_engine_resume(engine_ptr: ?*Engine) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;

    engine.resumeStream() catch |err| {
        stdout.print(engine.io(), "listener_engine_resume failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

pub export fn listener_engine_current_frame(engine_ptr: ?*Engine, out_frame: *u64) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;
    const stream = engine.active_stream orelse return .invalid_argument;
    const buffer = &(engine.playback_buffer orelse return .invalid_argument);

    const rendered = buffer.framesRead();
    out_frame.* = stream.info.actual_start_frame + rendered;
    return .ok;
}

pub export fn listener_engine_seek(engine_ptr: ?*Engine, target_frame: u64) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;

    engine.seekStream(target_frame) catch |err| {
        stdout.print(engine.io(), "listener_engine_seek failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

pub export fn listener_engine_set_event_callback(
    engine_ptr: ?*Engine,
    callback: ?PlaybackEventCallback,
    context: ?*anyopaque,
) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;
    engine.event_callback = callback;
    engine.event_context = context;
    return .ok;
}

const PlaybackEventCallback = *const fn (
    context: ?*anyopaque,
    event: u32,
) callconv(.c) void;

const PlaybackEvent = enum(u32) {
    ended = 1,
    failed = 2,
};

const Engine = struct {
    allocator: std.mem.Allocator,
    io_thread: std.Io.Threaded,
    lstn_connection: ?lstn.Connection = null,
    audio_backend: backend.OutputBackend,
    active_stream: ?lstn.StartedStream = null,
    playback_buffer: ?ring_buffer.SharedPcmRingBuffer = null,
    receive_thread: ?std.Thread = null,
    receiver_state: ?*ReceiverState = null,
    connection_host: ?[]u8 = null,
    connection_port: ?u16 = null,
    flow_control: FlowControlState = .{},
    event_callback: ?PlaybackEventCallback = null,
    event_context: ?*anyopaque = null,
    active_playback_id: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) Engine {
        var audio_backend = backend.OutputBackend{
            .name = selected_output.Backend.name,
            .impl = undefined,
        };
        selected_output.Backend.init(&audio_backend.impl);

        return .{
            .allocator = allocator,
            .io_thread = .init(allocator, .{}),
            .audio_backend = audio_backend,
        };
    }

    pub fn connect(self: *Engine, config: lstn.Config) !void {
        if (self.lstn_connection != null) return error.AlreadyConnected;

        const host = try self.allocator.dupe(u8, config.host);
        errdefer self.allocator.free(host);

        self.lstn_connection = try lstn.Connection.connect(
            self.io(),
            self.allocator,
            config,
        );
        self.connection_host = host;
        self.connection_port = config.port;
    }

    pub fn startStream(self: *Engine, message: protocol.StartStream) !void {
        if (self.active_stream != null or
            self.playback_buffer != null or
            self.receive_thread != null or
            self.receiver_state != null)
        {
            return error.AlreadyStreaming;
        }

        try self.ensureConnection();
        const conn = &self.lstn_connection.?;

        const playback_id = try self.allocator.dupe(u8, message.playback_id);
        errdefer self.allocator.free(playback_id);

        const started_stream = try conn.startStream(message);

        var receiver_started = false;
        var discard_connection = false;
        errdefer if (discard_connection) {
            conn.close();
            self.lstn_connection = null;
        };
        errdefer if (!receiver_started) conn.stopStream(started_stream) catch {
            conn.shutdown();
            discard_connection = true;
        };

        const stream_info = started_stream.info;
        const output_format = backend.OutputFormat{
            .sample_format = stream_info.format,
            .sample_rate = stream_info.sample_rate,
            .channels = stream_info.channels,
        };

        const capacity_frames: usize = if (stream_info.recommended_buffer_frames > 0)
            @intCast(stream_info.recommended_buffer_frames)
        else
            @intCast(stream_info.sample_rate / 2);

        const startup_frames = startupBufferFrames(capacity_frames);

        self.playback_buffer = try ring_buffer.SharedPcmRingBuffer.init(
            self.io(),
            self.allocator,
            output_format,
            capacity_frames,
        );
        errdefer {
            self.playback_buffer.?.deinit();
            self.playback_buffer = null;
        }

        try self.audio_backend.impl.open(
            output_format,
            self.playback_buffer.?.outputSource(),
        );
        errdefer self.audio_backend.impl.close();

        const receiver_state = try self.allocator.create(ReceiverState);
        receiver_state.* = ReceiverState.init(self.io());
        self.receiver_state = receiver_state;
        errdefer {
            self.allocator.destroy(receiver_state);
            self.receiver_state = null;
        }

        self.flow_control.paused.store(false, .release);
        self.flow_control.last_received_sequence.store(0, .release);

        try conn.sendBufferStatus(
            started_stream,
            &self.playback_buffer.?,
            0,
            &self.flow_control.paused,
        );

        self.receive_thread = try std.Thread.spawn(.{}, receiveAudioMain, .{
            conn,
            output_format,
            started_stream,
            &self.playback_buffer.?,
            &self.flow_control,
            receiver_state,
            self.event_callback,
            self.event_context,
        });
        receiver_started = true;
        errdefer {
            conn.stopStream(started_stream) catch {
                conn.shutdown();
                discard_connection = true;
            };
            self.playback_buffer.?.stop() catch {};
            self.receive_thread.?.join();
            self.receive_thread = null;
        }

        receiver_state.waitForStartup(startup_frames) catch |err| {
            discard_connection = true;
            return err;
        };

        try self.audio_backend.impl.start();
        errdefer self.audio_backend.impl.stop() catch {};

        receiver_state.enableFailureEvents() catch |err| {
            discard_connection = true;
            return err;
        };
        self.active_stream = started_stream;
        self.active_playback_id = playback_id;
    }

    pub fn stopStream(self: *Engine) !void {
        const started_stream = self.active_stream orelse return;
        const conn = if (self.lstn_connection) |*conn| conn else return error.ExpectedHello;

        var cleanup_error: ?anyerror = null;
        var connection_closed = !conn.isOpen();
        const playback_ended = if (self.playback_buffer) |*buffer|
            buffer.isDrained() catch |err| ended: {
                cleanup_error = err;
                break :ended false;
            }
        else
            false;

        if (!playback_ended and !connection_closed) {
            conn.stopStream(started_stream) catch {
                conn.shutdown();
                connection_closed = true;
            };
        }

        if (self.playback_buffer) |*buffer| {
            buffer.stop() catch |err| {
                if (cleanup_error == null) cleanup_error = err;
            };
        }

        if (self.receive_thread) |thread| {
            thread.join();
            self.receive_thread = null;
        }

        if (self.receiver_state) |receiver_state| {
            if (receiver_state.failure()) |err| {
                if (!connection_closed) {
                    if (cleanup_error == null) cleanup_error = err;
                    conn.shutdown();
                    connection_closed = true;
                }
            }
            self.allocator.destroy(receiver_state);
            self.receiver_state = null;
        }

        self.audio_backend.impl.stop() catch {};
        self.audio_backend.impl.close();

        if (self.playback_buffer) |*buffer| {
            buffer.deinit();
            self.playback_buffer = null;
        }

        self.active_stream = null;
        if (self.active_playback_id) |active_playback_id| {
            self.allocator.free(active_playback_id);
            self.active_playback_id = null;
        }

        if (connection_closed) {
            conn.close();
            self.lstn_connection = null;
        }
        if (cleanup_error) |err| return err;
    }

    pub fn pauseStream(self: *Engine) !void {
        const started_stream = self.active_stream orelse return;
        const conn = if (self.lstn_connection) |*conn| conn else return error.ExpectedHello;
        const buffer = if (self.playback_buffer) |*buffer| buffer else return error.AlreadyStreaming;

        if (self.flow_control.paused.swap(true, .acq_rel)) return;
        errdefer self.flow_control.paused.store(false, .release);

        try conn.sendBufferStatus(
            started_stream,
            buffer,
            self.flow_control.last_received_sequence.load(.acquire),
            &self.flow_control.paused,
        );
        self.audio_backend.impl.pause_playback() catch |err| {
            self.flow_control.paused.store(false, .release);
            conn.sendBufferStatus(
                started_stream,
                buffer,
                self.flow_control.last_received_sequence.load(.acquire),
                &self.flow_control.paused,
            ) catch {};
            return err;
        };
    }

    pub fn resumeStream(self: *Engine) !void {
        const started_stream = self.active_stream orelse return;
        const conn = if (self.lstn_connection) |*conn| conn else return error.ExpectedHello;
        const buffer = if (self.playback_buffer) |*buffer| buffer else return error.AlreadyStreaming;

        if (!self.flow_control.paused.load(.acquire)) return;
        try self.audio_backend.impl.resume_playback();

        self.flow_control.paused.store(false, .release);
        conn.sendBufferStatus(
            started_stream,
            buffer,
            self.flow_control.last_received_sequence.load(.acquire),
            &self.flow_control.paused,
        ) catch |err| {
            self.flow_control.paused.store(true, .release);
            self.audio_backend.impl.pause_playback() catch {};
            return err;
        };
    }

    pub fn seekStream(self: *Engine, target_frame: u64) !void {
        const active_stream = self.active_stream orelse
            return error.NoActiveStream;

        // A failed seek must never leave either the old or replacement stream
        // rendering after the caller has transitioned to an error state.
        errdefer self.stopStream() catch {};

        const active_playback_id = self.active_playback_id orelse
            return error.NoActiveStream;

        if (active_stream.info.total_frames != 0 and
            target_frame > active_stream.info.total_frames)
        {
            return error.InvalidSeekFrame;
        }

        const playback_id = try self.allocator.dupe(u8, active_playback_id);
        defer self.allocator.free(playback_id);

        const was_paused = self.flow_control.paused.load(.acquire);

        try self.stopStream();
        try self.startStream(.{
            .playback_id = playback_id,
            .requested_start_frame = target_frame,
        });

        if (was_paused) {
            try self.pauseStream();
        }
    }

    pub fn deinit(self: *Engine) void {
        self.stopStream() catch {};

        if (self.receive_thread) |thread| {
            thread.join();
            self.receive_thread = null;
        }

        if (self.receiver_state) |receiver_state| {
            self.allocator.destroy(receiver_state);
            self.receiver_state = null;
        }

        self.audio_backend.impl.stop() catch {};
        self.audio_backend.impl.close();

        if (self.playback_buffer) |*buffer| {
            buffer.deinit();
            self.playback_buffer = null;
        }

        if (self.lstn_connection) |*conn| {
            conn.close();
        }

        if (self.connection_host) |host| {
            self.allocator.free(host);
            self.connection_host = null;
        }

        if (self.active_playback_id) |active_playback_id| {
            self.allocator.free(active_playback_id);
            self.active_playback_id = null;
        }

        self.io_thread.deinit();
    }

    fn ensureConnection(self: *Engine) !void {
        if (self.lstn_connection) |*conn| {
            if (conn.isOpen()) return;
            conn.close();
            self.lstn_connection = null;
        }

        const host = self.connection_host orelse return error.ExpectedHello;
        const port = self.connection_port orelse return error.ExpectedHello;
        self.lstn_connection = try lstn.Connection.connect(
            self.io(),
            self.allocator,
            .{ .host = host, .port = port },
        );
    }

    pub fn io(self: *Engine) std.Io {
        return self.io_thread.io();
    }
};

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
    no_active_stream = 9,
    invalid_seek_frame = 10,
    unexpected = 255,
};

const ReceiverState = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    buffered_frames: usize = 0,
    stream_ended: bool = false,
    finished: bool = false,
    terminal_error: ?anyerror = null,
    failure_events_enabled: bool = false,

    fn init(io: std.Io) ReceiverState {
        return .{ .io = io };
    }

    fn acceptedFrames(self: *ReceiverState, frame_count: u32) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.buffered_frames = std.math.add(
            usize,
            self.buffered_frames,
            frame_count,
        ) catch std.math.maxInt(usize);
        self.changed.broadcast(self.io);
    }

    fn reachedStreamEnd(self: *ReceiverState) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.stream_ended = true;
        self.changed.broadcast(self.io);
    }

    fn finish(self: *ReceiverState, terminal_error: ?anyerror) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (self.finished) return false;

        self.finished = true;
        self.terminal_error = terminal_error;
        self.changed.broadcast(self.io);

        return terminal_error != null and self.failure_events_enabled;
    }

    fn waitForStartup(self: *ReceiverState, target_frames: usize) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        while (self.buffered_frames < target_frames and
            !self.stream_ended and
            !self.finished)
        {
            try self.changed.wait(self.io, &self.mutex);
        }

        if (self.terminal_error) |err| return err;
        if (self.finished and !self.stream_ended) return error.EndOfStream;
    }

    fn enableFailureEvents(self: *ReceiverState) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        if (self.terminal_error) |err| return err;
        self.failure_events_enabled = true;
    }

    fn failure(self: *ReceiverState) ?anyerror {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        return self.terminal_error;
    }
};

fn startupBufferFrames(capacity_frames: usize) usize {
    return @max(1, capacity_frames / 2);
}

fn receiveAudioMain(
    lstn_connection: *lstn.Connection,
    output_format: backend.OutputFormat,
    started_stream: lstn.StartedStream,
    playback_buffer: *ring_buffer.SharedPcmRingBuffer,
    flow_control: *FlowControlState,
    receiver_state: *ReceiverState,
    event_callback: ?PlaybackEventCallback,
    event_context: ?*anyopaque,
) void {
    receive_audio_frame(
        lstn_connection,
        output_format,
        started_stream,
        playback_buffer,
        flow_control,
        receiver_state,
        event_callback,
        event_context,
    ) catch |err| {
        playback_buffer.stop() catch {};
        if (receiver_state.finish(err)) {
            if (event_callback) |callback| {
                callback(event_context, @intFromEnum(PlaybackEvent.failed));
            }
        }
        return;
    };

    _ = receiver_state.finish(null);
}

fn receive_audio_frame(
    lstn_connection: *lstn.Connection,
    output_format: backend.OutputFormat,
    started_stream: lstn.StartedStream,
    playback_buffer: *ring_buffer.SharedPcmRingBuffer,
    flow_control: *FlowControlState,
    receiver_state: ?*ReceiverState,
    event_callback: ?PlaybackEventCallback,
    event_context: ?*anyopaque,
) !void {
    var last_received_sequence: u64 = 0;
    var expected_frame_offset = started_stream.info.actual_start_frame;

    receive: while (true) {
        const read_result = lstn_connection.readAudioIntoBuffer(
            started_stream,
            output_format,
            playback_buffer,
            &expected_frame_offset,
        ) catch |err| switch (err) {
            // stopStream wakes a producer that may be blocked on a full
            // playback buffer. The audio frame has already been consumed
            // from the socket at this point, so keep reading until the
            // server's STREAM_END cancellation acknowledgement is consumed.
            // Otherwise that stale frame is mistaken for the next stream's
            // STREAM_INFO when playback starts again.
            error.OutputStopped => continue :receive,
            else => return err,
        };

        switch (read_result) {
            .audio_frame => |frame| {
                last_received_sequence = frame.last_received_sequence;
                flow_control.last_received_sequence.store(last_received_sequence, .release);
                try lstn_connection.sendBufferStatus(
                    started_stream,
                    playback_buffer,
                    last_received_sequence,
                    &flow_control.paused,
                );
                if (receiver_state) |state| {
                    state.acceptedFrames(frame.frame_count);
                }
            },
            .stream_end => {
                if (receiver_state) |state| {
                    state.reachedStreamEnd();
                }
                break :receive;
            },
            .ignored_message => {},
        }
    }

    if (try playback_buffer.waitUntilDrained()) {
        if (event_callback) |callback| {
            callback(event_context, @intFromEnum(PlaybackEvent.ended));
        }
    }
}

const FlowControlState = struct {
    paused: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    last_received_sequence: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
};

fn status_from_error(err: anyerror) ListenerStatus {
    return switch (err) {
        error.AlreadyConnected => .already_connected,
        error.InvalidPlaybackId => .invalid_argument,

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
        error.UnexpectedStreamInfo,
        error.UnexpectedStreamScope,
        error.UnexpectedStreamMessage,
        error.UnexpectedAudioFrameOffset,
        error.StartStreamRejected,
        error.InvalidMagic,
        error.InvalidFlags,
        error.UnsupportedVersion,
        error.InvalidHeaderLength,
        error.InvalidBodyLength,
        error.BodyTooLarge,
        error.InvalidMessageType,
        => .protocol_error,

        error.NoActiveStream => .no_active_stream,
        error.InvalidSeekFrame => .invalid_seek_frame,

        error.OutOfMemory => .out_of_memory,

        else => .unexpected,
    };
}

test "engine streams network audio to the selected output backend" {
    try expectEngineStreamsNetworkAudio(.one_at_a_time);
}

test "engine preserves back-to-back audio frames from one socket write" {
    try expectEngineStreamsNetworkAudio(.back_to_back);
}

test "pause advertises zero credit and resume restores stream credit" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    selected_output.reset(allocator);
    defer selected_output.reset(allocator);

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = PauseResumeFakeLstnServer{
        .io = io,
        .listener = &listener,
    };
    const server_thread = try std.Thread.spawn(.{}, PauseResumeFakeLstnServer.run, .{&server});
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var engine = Engine.init(allocator);
    defer engine.deinit();
    try engine.connect(.{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });
    try engine.startStream(.{
        .requested_start_frame = 0,
        .playback_id = "pause-resume-test",
    });

    try waitForAtomicBool(&server.initial_status_received, 100_000);
    try engine.pauseStream();
    try engine.resumeStream();
    try engine.stopStream();

    server_thread.join();
    server_joined = true;
    try server.result;
}

test "receiver failure during startup is returned and fully cleaned up" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    selected_output.reset(allocator);
    defer selected_output.reset(allocator);

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = StartupFailureFakeLstnServer{
        .io = io,
        .listener = &listener,
    };
    const server_thread = try std.Thread.spawn(.{}, StartupFailureFakeLstnServer.run, .{&server});
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var engine = Engine.init(allocator);
    defer engine.deinit();
    try engine.connect(.{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });

    try std.testing.expectError(
        error.UnexpectedAudioFrameOffset,
        engine.startStream(.{
            .requested_start_frame = 0,
            .playback_id = "startup-failure-test",
        }),
    );

    try std.testing.expect(!selected_output.isStarted());
    try std.testing.expect(engine.lstn_connection == null);
    try std.testing.expect(engine.active_stream == null);
    try std.testing.expect(engine.playback_buffer == null);
    try std.testing.expect(engine.receive_thread == null);
    try std.testing.expect(engine.receiver_state == null);

    server_thread.join();
    server_joined = true;
    try server.result;
}

test "receiver failure after startup is reported as an engine event" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    selected_output.reset(allocator);
    defer selected_output.reset(allocator);

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = RuntimeFailureFakeLstnServer{
        .io = io,
        .listener = &listener,
    };
    const server_thread = try std.Thread.spawn(.{}, RuntimeFailureFakeLstnServer.run, .{&server});
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var engine = Engine.init(allocator);
    defer engine.deinit();
    var received_event = std.atomic.Value(u32).init(0);
    engine.event_callback = &recordAnyPlaybackEvent;
    engine.event_context = &received_event;

    try engine.connect(.{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });
    try engine.startStream(.{
        .requested_start_frame = 0,
        .playback_id = "runtime-failure-test",
    });
    try std.testing.expect(selected_output.isStarted());

    server.release_failure.store(true, .release);
    try waitForAtomicU32(
        &received_event,
        @intFromEnum(PlaybackEvent.failed),
        100_000,
    );

    try std.testing.expectError(
        error.UnexpectedAudioFrameOffset,
        engine.stopStream(),
    );
    try std.testing.expect(engine.lstn_connection == null);
    try std.testing.expect(engine.receive_thread == null);
    try std.testing.expect(engine.receiver_state == null);

    server_thread.join();
    server_joined = true;
    try server.result;
}

test "persistent reader consumes stream end and answers idle ping before restart" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = RestartFakeLstnServer{
        .io = io,
        .listener = &listener,
    };
    const server_thread = try std.Thread.spawn(.{}, RestartFakeLstnServer.run, .{&server});
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var connection = try lstn.Connection.connect(io, allocator, .{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });
    defer connection.close();

    const first_stream = try connection.startStream(.{
        .requested_start_frame = 0,
        .playback_id = "playback-1",
    });
    const output_format = backend.OutputFormat{
        .sample_format = first_stream.info.format,
        .sample_rate = first_stream.info.sample_rate,
        .channels = first_stream.info.channels,
    };

    var playback_buffer = try ring_buffer.SharedPcmRingBuffer.init(
        io,
        allocator,
        output_format,
        1,
    );
    defer playback_buffer.deinit();
    try playback_buffer.stop();
    var flow_control = FlowControlState{};

    try receive_audio_frame(
        &connection,
        output_format,
        first_stream,
        &playback_buffer,
        &flow_control,
        null,
        null,
        null,
    );

    _ = try connection.startStream(.{
        .requested_start_frame = 0,
        .playback_id = "playback-2",
    });

    server_thread.join();
    server_joined = true;
    try server.result;
}

test "engine reconnects before starting after an idle disconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = IdleReconnectFakeLstnServer{
        .io = io,
        .listener = &listener,
    };
    const server_thread = try std.Thread.spawn(
        .{},
        IdleReconnectFakeLstnServer.run,
        .{&server},
    );
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var engine = Engine.init(allocator);
    defer engine.deinit();
    try engine.connect(.{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });

    try waitForAtomicBool(&server.first_connection_closed, 100_000);
    var remaining: usize = 100_000;
    while (remaining > 0) : (remaining -= 1) {
        if (!engine.lstn_connection.?.isOpen()) break;
        std.Thread.yield() catch {};
    }
    try std.testing.expect(remaining > 0);

    try std.testing.expectError(
        lstn.ClientError.StartStreamRejected,
        engine.startStream(.{
            .requested_start_frame = 0,
            .playback_id = "reconnect-test",
        }),
    );

    server_thread.join();
    server_joined = true;
    try server.result;
}

test "stopping after a playback disconnect is successful local cleanup" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    selected_output.reset(allocator);
    defer selected_output.reset(allocator);

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = PlaybackDisconnectFakeLstnServer{
        .io = io,
        .listener = &listener,
    };
    const server_thread = try std.Thread.spawn(
        .{},
        PlaybackDisconnectFakeLstnServer.run,
        .{&server},
    );
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var engine = Engine.init(allocator);
    defer engine.deinit();
    try engine.connect(.{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });
    try engine.startStream(.{
        .requested_start_frame = 0,
        .playback_id = "disconnect-during-playback",
    });

    server.release_disconnect.store(true, .release);
    try waitForAtomicBool(&server.disconnected, 100_000);
    var remaining: usize = 100_000;
    while (remaining > 0) : (remaining -= 1) {
        if (!engine.lstn_connection.?.isOpen()) break;
        std.Thread.yield() catch {};
    }
    try std.testing.expect(remaining > 0);

    try engine.stopStream();
    try std.testing.expect(engine.lstn_connection == null);
    try std.testing.expect(engine.active_stream == null);
    try std.testing.expect(engine.playback_buffer == null);
    try std.testing.expect(engine.receive_thread == null);
    try std.testing.expect(engine.receiver_state == null);

    server_thread.join();
    server_joined = true;
    try server.result;
}

const AudioDelivery = enum {
    one_at_a_time,
    back_to_back,
};

fn expectEngineStreamsNetworkAudio(audio_delivery: AudioDelivery) !void {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const expected_audio = &[_]u8{
        0x00, 0x00, 0x00, 0x00,
        0x00, 0xff, 0xff, 0x7f,
        0x00, 0x56, 0x34, 0x12,
        0x00, 0x00, 0x00, 0x80,
        0x00, 0xaa, 0xcb, 0xed,
        0x00, 0x01, 0x00, 0x00,
    };

    selected_output.reset(allocator);
    defer selected_output.reset(allocator);

    var listen_address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try listen_address.listen(io, .{
        .mode = std.Io.net.Socket.Mode.stream,
        .protocol = std.Io.net.Protocol.tcp,
    });
    defer listener.deinit(io);

    var server = FakeLstnServer{
        .io = io,
        .listener = &listener,
        .expected_audio = expected_audio,
        .audio_delivery = audio_delivery,
    };
    const server_thread = try std.Thread.spawn(.{}, FakeLstnServer.run, .{&server});
    var server_joined = false;
    defer if (!server_joined) server_thread.join();

    var engine = Engine.init(allocator);
    defer engine.deinit();

    var playback_ended = std.atomic.Value(bool).init(false);
    engine.event_callback = &recordPlaybackEvent;
    engine.event_context = &playback_ended;

    try engine.connect(.{
        .host = "127.0.0.1",
        .port = listener.socket.address.getPort(),
    });
    try engine.startStream(.{
        .requested_start_frame = 0,
        .playback_id = "client-test",
    });

    try selected_output.waitForCapturedBytes(expected_audio.len, 100_000);
    try waitForPlaybackEnded(&playback_ended, 100_000);
    try engine.stopStream();

    server_thread.join();
    server_joined = true;
    try server.result;

    const captured = try selected_output.capturedBytes(allocator);
    defer allocator.free(captured);

    try std.testing.expectEqualSlices(u8, expected_audio, captured);
}

fn recordPlaybackEvent(context: ?*anyopaque, event: u32) callconv(.c) void {
    if (event != @intFromEnum(PlaybackEvent.ended)) return;
    const playback_ended: *std.atomic.Value(bool) = @ptrCast(@alignCast(context.?));
    playback_ended.store(true, .release);
}

fn recordAnyPlaybackEvent(context: ?*anyopaque, event: u32) callconv(.c) void {
    const received_event: *std.atomic.Value(u32) = @ptrCast(@alignCast(context.?));
    received_event.store(event, .release);
}

fn waitForPlaybackEnded(
    playback_ended: *const std.atomic.Value(bool),
    max_yields: usize,
) !void {
    var remaining = max_yields;
    while (remaining > 0) : (remaining -= 1) {
        if (playback_ended.load(.acquire)) return;
        std.Thread.yield() catch {};
    }

    return error.Timeout;
}

fn waitForAtomicBool(value: *const std.atomic.Value(bool), max_yields: usize) !void {
    var remaining = max_yields;
    while (remaining > 0) : (remaining -= 1) {
        if (value.load(.acquire)) return;
        std.Thread.yield() catch {};
    }
    return error.Timeout;
}

fn waitForAtomicU32(
    value: *const std.atomic.Value(u32),
    expected: u32,
    max_yields: usize,
) !void {
    var remaining = max_yields;
    while (remaining > 0) : (remaining -= 1) {
        if (value.load(.acquire) == expected) return;
        std.Thread.yield() catch {};
    }
    return error.Timeout;
}

const PauseResumeFakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    initial_status_received: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    result: anyerror!void = {},

    fn run(self: *PauseResumeFakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *PauseResumeFakeLstnServer) !void {
        const stream = try self.listener.accept(self.io);
        defer stream.close(self.io);

        var read_buffer: [1024]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &.{});
        var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

        const hello = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
        try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

        const start = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.start_stream, start.header.message_type);
        try sendTestStreamInfo(&writer.interface, 2, start.header);

        const initial = try readClientFrame(&reader.interface, &body_storage);
        const initial_status = try expectBufferStatus(initial, start.header);
        try std.testing.expect(initial_status.credit_frames > 0);
        self.initial_status_received.store(true, .release);

        try sendAudioFrame(
            &writer.interface,
            3,
            start.header.stream_id,
            start.header.generation_id,
            0,
            1,
            &[_]u8{0} ** 4,
        );
        const startup_ack = try readClientFrame(&reader.interface, &body_storage);
        try expectBufferStatusAck(
            startup_ack,
            start.header.stream_id,
            start.header.generation_id,
            3,
        );

        const paused = try readClientFrame(&reader.interface, &body_storage);
        const paused_status = try expectBufferStatus(paused, start.header);
        try std.testing.expectEqual(@as(u32, 0), paused_status.credit_frames);

        const resumed = try readClientFrame(&reader.interface, &body_storage);
        const resumed_status = try expectBufferStatus(resumed, start.header);
        try std.testing.expect(resumed_status.credit_frames > 0);

        const cancel = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.cancel_generation, cancel.header.message_type);
        try sendEmptyServerMessage(
            &writer.interface,
            .stream_end,
            4,
            start.header.stream_id,
            start.header.generation_id,
        );
    }

    fn expectBufferStatus(
        frame: ClientFrame,
        start_header: protocol.Header,
    ) !protocol.BufferStatus {
        try std.testing.expectEqual(protocol.MessageType.buffer_status, frame.header.message_type);
        try std.testing.expectEqual(start_header.stream_id, frame.header.stream_id);
        try std.testing.expectEqual(start_header.generation_id, frame.header.generation_id);
        return protocol.BufferStatus.decode(frame.body);
    }
};

const StartupFailureFakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    result: anyerror!void = {},

    fn run(self: *StartupFailureFakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *StartupFailureFakeLstnServer) !void {
        const stream = try self.listener.accept(self.io);
        defer stream.close(self.io);

        var read_buffer: [1024]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &.{});
        var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

        const hello = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
        try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

        const start = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.start_stream, start.header.message_type);

        const stream_info = protocol.StreamInfo{
            .format = .pcm_s24le_in_s32le,
            .sample_rate = 48_000,
            .channels = 2,
            .channel_layout = 0,
            .total_frames = 100,
            .actual_start_frame = 0,
            .recommended_buffer_frames = 8,
        };
        const stream_info_body = stream_info.encode();
        try sendServerMessage(
            &writer.interface,
            .stream_info,
            2,
            start.header.stream_id,
            start.header.generation_id,
            &stream_info_body,
        );

        const initial_status = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.buffer_status, initial_status.header.message_type);

        // Startup expects offset zero. This malformed first frame must wake
        // startStream with the receiver error instead of leaving it blocked.
        try sendAudioFrame(
            &writer.interface,
            3,
            start.header.stream_id,
            start.header.generation_id,
            1,
            1,
            &[_]u8{0} ** 8,
        );
    }
};

const RuntimeFailureFakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    release_failure: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    result: anyerror!void = {},

    fn run(self: *RuntimeFailureFakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *RuntimeFailureFakeLstnServer) !void {
        const stream = try self.listener.accept(self.io);
        defer stream.close(self.io);

        var read_buffer: [1024]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &.{});
        var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

        const hello = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
        try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

        const start = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.start_stream, start.header.message_type);

        const stream_info = protocol.StreamInfo{
            .format = .pcm_s16le,
            .sample_rate = 48_000,
            .channels = 2,
            .channel_layout = 0,
            .total_frames = 100,
            .actual_start_frame = 0,
            .recommended_buffer_frames = 2,
        };
        const stream_info_body = stream_info.encode();
        try sendServerMessage(
            &writer.interface,
            .stream_info,
            2,
            start.header.stream_id,
            start.header.generation_id,
            &stream_info_body,
        );

        const initial_status = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.buffer_status, initial_status.header.message_type);

        try sendAudioFrame(
            &writer.interface,
            3,
            start.header.stream_id,
            start.header.generation_id,
            0,
            1,
            &[_]u8{0} ** 4,
        );
        const startup_ack = try readClientFrame(&reader.interface, &body_storage);
        try expectBufferStatusAck(
            startup_ack,
            start.header.stream_id,
            start.header.generation_id,
            3,
        );

        try waitForAtomicBool(&self.release_failure, 100_000);
        try sendAudioFrame(
            &writer.interface,
            4,
            start.header.stream_id,
            start.header.generation_id,
            2,
            1,
            &[_]u8{0} ** 4,
        );

        const cancel = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.cancel_generation, cancel.header.message_type);
    }
};

const RestartFakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    result: anyerror!void = {},

    fn run(self: *RestartFakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *RestartFakeLstnServer) !void {
        const stream = try self.listener.accept(self.io);
        defer stream.close(self.io);

        var read_buffer: [1024]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &.{});
        var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

        const hello = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
        try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

        const first_start = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.start_stream, first_start.header.message_type);
        try sendTestStreamInfo(&writer.interface, 2, first_start.header);

        const audio = [_]u8{ 0, 0, 0, 0 };
        try sendAudioFrame(
            &writer.interface,
            3,
            first_start.header.stream_id,
            first_start.header.generation_id,
            0,
            1,
            &audio,
        );
        try sendAudioFrame(
            &writer.interface,
            4,
            first_start.header.stream_id,
            first_start.header.generation_id,
            1,
            1,
            &audio,
        );
        try sendEmptyServerMessage(
            &writer.interface,
            .stream_end,
            5,
            first_start.header.stream_id,
            first_start.header.generation_id,
        );

        // The connection-lifetime reader must keep servicing heartbeats after
        // STREAM_END, even though the per-stream receiver has exited.
        try sendEmptyServerMessage(&writer.interface, .ping, 6, 0, 0);

        var saw_pong = false;
        var second_start_header: ?protocol.Header = null;
        while (!saw_pong or second_start_header == null) {
            const frame = try readClientFrame(&reader.interface, &body_storage);
            switch (frame.header.message_type) {
                .pong => {
                    try std.testing.expectEqual(@as(u32, 0), frame.header.body_len);
                    saw_pong = true;
                },
                .start_stream => second_start_header = frame.header,
                else => return error.UnexpectedClientMessage,
            }
        }

        try sendTestStreamInfo(&writer.interface, 7, second_start_header.?);
    }
};

const IdleReconnectFakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    first_connection_closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    result: anyerror!void = {},

    fn run(self: *IdleReconnectFakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *IdleReconnectFakeLstnServer) !void {
        {
            const stream = try self.listener.accept(self.io);
            defer stream.close(self.io);

            var read_buffer: [1024]u8 = undefined;
            var reader = stream.reader(self.io, &read_buffer);
            var writer = stream.writer(self.io, &.{});
            var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

            const hello = try readClientFrame(&reader.interface, &body_storage);
            try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
            try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);
        }
        self.first_connection_closed.store(true, .release);

        const stream = try self.listener.accept(self.io);
        defer stream.close(self.io);

        var read_buffer: [1024]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &.{});
        var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

        const hello = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
        try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

        const start = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.start_stream, start.header.message_type);
        try sendEmptyServerMessage(
            &writer.interface,
            .protocol_error,
            2,
            start.header.stream_id,
            start.header.generation_id,
        );
    }
};

const PlaybackDisconnectFakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    release_disconnect: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    disconnected: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    result: anyerror!void = {},

    fn run(self: *PlaybackDisconnectFakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *PlaybackDisconnectFakeLstnServer) !void {
        {
            const stream = try self.listener.accept(self.io);
            defer stream.close(self.io);

            var read_buffer: [1024]u8 = undefined;
            var reader = stream.reader(self.io, &read_buffer);
            var writer = stream.writer(self.io, &.{});
            var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

            const hello = try readClientFrame(&reader.interface, &body_storage);
            try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
            try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

            const start = try readClientFrame(&reader.interface, &body_storage);
            try std.testing.expectEqual(protocol.MessageType.start_stream, start.header.message_type);
            try sendTestStreamInfo(&writer.interface, 2, start.header);

            const initial_status = try readClientFrame(&reader.interface, &body_storage);
            try std.testing.expectEqual(
                protocol.MessageType.buffer_status,
                initial_status.header.message_type,
            );

            try sendAudioFrame(
                &writer.interface,
                3,
                start.header.stream_id,
                start.header.generation_id,
                0,
                1,
                &[_]u8{0} ** 4,
            );
            const startup_ack = try readClientFrame(&reader.interface, &body_storage);
            try expectBufferStatusAck(
                startup_ack,
                start.header.stream_id,
                start.header.generation_id,
                3,
            );

            try waitForAtomicBool(&self.release_disconnect, 100_000);
        }
        self.disconnected.store(true, .release);
    }
};

fn sendTestStreamInfo(
    writer: *std.Io.Writer,
    sequence: u64,
    request_header: protocol.Header,
) !void {
    const stream_info = protocol.StreamInfo{
        .format = .pcm_s16le,
        .sample_rate = 48_000,
        .channels = 2,
        .channel_layout = 0,
        .total_frames = 1,
        .actual_start_frame = 0,
        .recommended_buffer_frames = 1,
    };
    const body = stream_info.encode();
    try sendServerMessage(
        writer,
        .stream_info,
        sequence,
        request_header.stream_id,
        request_header.generation_id,
        &body,
    );
}

const FakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    expected_audio: []const u8,
    audio_delivery: AudioDelivery,
    result: anyerror!void = {},

    fn run(self: *FakeLstnServer) void {
        self.result = self.runInner();
    }

    fn runInner(self: *FakeLstnServer) !void {
        const stream = try self.listener.accept(self.io);
        defer stream.close(self.io);

        var read_buffer: [1024]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &.{});

        var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

        const hello = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.hello, hello.header.message_type);
        try std.testing.expectEqual(@as(u32, 0), hello.header.body_len);
        try sendEmptyServerMessage(&writer.interface, .hello_ack, 1, 0, 0);

        const start = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.start_stream, start.header.message_type);
        const start_stream = try protocol.StartStream.decode(start.body);
        try std.testing.expectEqualStrings("client-test", start_stream.playback_id);

        const stream_id = start.header.stream_id;
        const generation_id = start.header.generation_id;
        const stream_info = protocol.StreamInfo{
            .format = .pcm_s24le_in_s32le,
            .sample_rate = 96_000,
            .channels = 2,
            .channel_layout = 0,
            .total_frames = 3,
            .actual_start_frame = 0,
            .recommended_buffer_frames = 8,
        };
        const stream_info_body = stream_info.encode();
        try sendServerMessage(
            &writer.interface,
            .stream_info,
            2,
            stream_id,
            generation_id,
            &stream_info_body,
        );

        const initial_status = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.buffer_status, initial_status.header.message_type);
        const status = try protocol.BufferStatus.decode(initial_status.body);
        try std.testing.expect(status.credit_frames >= stream_info.total_frames);
        try std.testing.expectEqual(@as(u64, 0), status.next_render_frame);

        const frame_bytes = try backend.sample_format_bytes(stream_info.format) * stream_info.channels;
        try std.testing.expectEqual(@as(usize, 0), self.expected_audio.len % frame_bytes);

        switch (self.audio_delivery) {
            .one_at_a_time => try sendAudioFrame(
                &writer.interface,
                3,
                stream_id,
                generation_id,
                0,
                1,
                self.expected_audio[0..frame_bytes],
            ),
            .back_to_back => {
                var batch_storage: [256]u8 = undefined;
                var batch_writer: std.Io.Writer = .fixed(&batch_storage);

                try sendAudioFrame(
                    &batch_writer,
                    3,
                    stream_id,
                    generation_id,
                    0,
                    1,
                    self.expected_audio[0..frame_bytes],
                );
                try sendAudioFrame(
                    &batch_writer,
                    4,
                    stream_id,
                    generation_id,
                    1,
                    2,
                    self.expected_audio[frame_bytes..],
                );

                // A single socket write makes the next frame available for
                // read-ahead while the client is decoding the first frame.
                try writer.interface.writeAll(batch_writer.buffered());
            },
        }

        const first_ack = try readClientFrame(&reader.interface, &body_storage);
        try expectBufferStatusAck(first_ack, stream_id, generation_id, 3);

        if (self.audio_delivery == .one_at_a_time) {
            try sendAudioFrame(
                &writer.interface,
                4,
                stream_id,
                generation_id,
                1,
                2,
                self.expected_audio[frame_bytes..],
            );
        }

        const second_ack = try readClientFrame(&reader.interface, &body_storage);
        try expectBufferStatusAck(second_ack, stream_id, generation_id, 4);

        // The track is shorter than the startup threshold, so output must
        // remain stopped until STREAM_END releases the startup wait.
        try std.testing.expect(!selected_output.isStarted());

        try sendEmptyServerMessage(
            &writer.interface,
            .ping,
            5,
            0,
            0,
        );

        const pong = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.pong, pong.header.message_type);
        try std.testing.expectEqual(@as(u32, 0), pong.header.body_len);
        try std.testing.expectEqual(@as(u64, 0), pong.header.stream_id);
        try std.testing.expectEqual(@as(u64, 0), pong.header.generation_id);

        try sendEmptyServerMessage(
            &writer.interface,
            .stream_end,
            6,
            stream_id,
            generation_id,
        );
    }
};

const ClientFrame = struct {
    header: protocol.Header,
    body: []const u8,
};

fn readClientFrame(reader: *std.Io.Reader, body_storage: []u8) !ClientFrame {
    var header_bytes: [protocol.header_wire_len]u8 = undefined;
    try reader.readSliceAll(&header_bytes);

    const header = try protocol.Header.decode(&header_bytes);
    const body_len: usize = @intCast(header.body_len);
    if (body_len > body_storage.len) return error.BodyBufferTooSmall;

    const body = body_storage[0..body_len];
    try reader.readSliceAll(body);

    return .{
        .header = header,
        .body = body,
    };
}

fn sendEmptyServerMessage(
    writer: *std.Io.Writer,
    message_type: protocol.MessageType,
    sequence: u64,
    stream_id: u64,
    generation_id: u64,
) !void {
    try sendServerMessage(
        writer,
        message_type,
        sequence,
        stream_id,
        generation_id,
        "",
    );
}

fn sendAudioFrame(
    writer: *std.Io.Writer,
    sequence: u64,
    stream_id: u64,
    generation_id: u64,
    frame_offset: u64,
    frame_count: u32,
    audio_data: []const u8,
) !void {
    const audio_frame = protocol.AudioFrame{
        .frame_offset = frame_offset,
        .frame_count = frame_count,
        .audio_data = audio_data,
    };
    var body_storage: [protocol.AudioFrame.max_wire_len]u8 = undefined;
    const body = try audio_frame.encode(&body_storage);

    try sendServerMessage(
        writer,
        .audio_frame,
        sequence,
        stream_id,
        generation_id,
        body,
    );
}

fn sendServerMessage(
    writer: *std.Io.Writer,
    message_type: protocol.MessageType,
    sequence: u64,
    stream_id: u64,
    generation_id: u64,
    body: []const u8,
) !void {
    const header = protocol.Header{
        .message_type = message_type,
        .body_len = @intCast(body.len),
        .stream_id = stream_id,
        .generation_id = generation_id,
        .sequence = sequence,
    };
    const header_bytes = try header.encode();

    try writer.writeAll(&header_bytes);
    try writer.writeAll(body);
}

fn expectBufferStatusAck(
    frame: ClientFrame,
    stream_id: u64,
    generation_id: u64,
    expected_sequence: u64,
) !void {
    try std.testing.expectEqual(protocol.MessageType.buffer_status, frame.header.message_type);
    try std.testing.expectEqual(stream_id, frame.header.stream_id);
    try std.testing.expectEqual(generation_id, frame.header.generation_id);

    const status = try protocol.BufferStatus.decode(frame.body);
    try std.testing.expectEqual(expected_sequence, status.last_received_sequence);
}
