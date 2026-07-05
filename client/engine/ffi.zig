const std = @import("std");
const lstn = @import("lstn/client.zig");
const protocol = @import("lstn_protocol");
const backend = @import("audio_backend");
const ring_buffer = @import("audio_ring_buffer");
const selected_output = @import("selected_output");

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

pub export fn listener_engine_start_stream(
    engine_ptr: ?*Engine,
    requested_start_frame: u64,
    playback_id_ptr: ?[*]const u8,
    playback_id_len: usize,
    media_path_ptr: ?[*]const u8,
    media_path_len: usize,
) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;
    const playback_id_base = playback_id_ptr orelse return .invalid_argument;
    const media_path_base = media_path_ptr orelse return .invalid_argument;

    const start_stream = protocol.StartStream{
        .requested_start_frame = requested_start_frame,
        .playback_id = playback_id_base[0..playback_id_len],
        .media_path = media_path_base[0..media_path_len],
    };

    start_stream.validate() catch |err| return status_from_error(err);

    engine.startStream(start_stream) catch |err| {
        std.debug.print("listener_engine_start_stream failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

const Engine = struct {
    allocator: std.mem.Allocator,
    io_thread: std.Io.Threaded,
    lstn_connection: ?lstn.Connection = null,
    audio_backend: backend.OutputBackend,
    playback_buffer: ?ring_buffer.SharedPcmRingBuffer = null,
    receive_thread: ?std.Thread = null,

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
        self.lstn_connection = try lstn.Connection.connect(self.io(), config);
    }

    pub fn startStream(self: *Engine, message: protocol.StartStream) !void {
        const conn = if (self.lstn_connection) |*conn|
            conn
        else
            return error.ExpectedHello;

        const started_stream = try conn.startStream(message);
        const stream_info = started_stream.info;
        const output_format = backend.OutputFormat{
            .sample_format = stream_info.format,
            .sample_rate = stream_info.sample_rate,
            .channels = stream_info.channels,
        };

        if (self.playback_buffer != null) return error.AlreadyStreaming;

        const capacity_frames = if (stream_info.recommended_buffer_frames > 0)
            stream_info.recommended_buffer_frames
        else
            stream_info.sample_rate / 2;

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
        try self.audio_backend.impl.start();
        try conn.sendBufferStatus(started_stream, &self.playback_buffer.?, 0);

        self.receive_thread = try std.Thread.spawn(.{}, receive_audio_frame, .{
            conn,
            output_format,
            started_stream,
            &self.playback_buffer.?,
        });
    }

    pub fn deinit(self: *Engine) void {
        if (self.playback_buffer) |*buffer| {
            buffer.stop() catch {};
        }

        if (self.lstn_connection) |*conn| {
            conn.close();
        }

        if (self.receive_thread) |thread| {
            thread.join();
            self.receive_thread = null;
        }

        if (self.playback_buffer) |*buffer| {
            buffer.deinit();
            self.playback_buffer = null;
        }

        self.io_thread.deinit();
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
    unexpected = 255,
};

fn receive_audio_frame(
    lstn_connection: *lstn.Connection,
    output_format: backend.OutputFormat,
    started_stream: lstn.StartedStream,
    playback_buffer: *ring_buffer.SharedPcmRingBuffer,
) !void {
    var last_received_sequence: u64 = 0;
    var expected_frame_offset = started_stream.info.actual_start_frame;

    while (true) {
        switch (try lstn_connection.readAudioIntoBuffer(
            started_stream,
            output_format,
            playback_buffer,
            &expected_frame_offset,
        )) {
            .audio_frame => |frame| {
                last_received_sequence = frame.last_received_sequence;
                try lstn_connection.sendBufferStatus(started_stream, playback_buffer, last_received_sequence);
            },
            .stream_end => break,
            .ignored_message => {},
        }
    }
}

fn status_from_error(err: anyerror) ListenerStatus {
    return switch (err) {
        error.AlreadyConnected => .already_connected,
        error.InvalidPlaybackId,
        error.InvalidMediaPath,
        => .invalid_argument,

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

        error.OutOfMemory => .out_of_memory,

        else => .unexpected,
    };
}
