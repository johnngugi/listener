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

pub export fn listener_engine_stop(engine_ptr: ?*Engine) ListenerStatus {
    const engine = engine_ptr orelse return .null_engine;

    engine.stopStream() catch |err| {
        std.debug.print("listener_engine_stop failed: {}\n", .{err});
        return status_from_error(err);
    };

    return .ok;
}

const Engine = struct {
    allocator: std.mem.Allocator,
    io_thread: std.Io.Threaded,
    lstn_connection: ?lstn.Connection = null,
    audio_backend: backend.OutputBackend,
    active_stream: ?lstn.StartedStream = null,
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

        if (self.active_stream != null or
            self.playback_buffer != null or
            self.receive_thread != null)
        {
            return error.AlreadyStreaming;
        }

        const started_stream = try conn.startStream(message);
        errdefer conn.stopStream(started_stream) catch {};

        const stream_info = started_stream.info;
        const output_format = backend.OutputFormat{
            .sample_format = stream_info.format,
            .sample_rate = stream_info.sample_rate,
            .channels = stream_info.channels,
        };

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
        errdefer self.audio_backend.impl.close();

        try self.audio_backend.impl.start();
        try conn.sendBufferStatus(started_stream, &self.playback_buffer.?, 0);

        self.receive_thread = try std.Thread.spawn(.{}, receive_audio_frame, .{
            conn,
            output_format,
            started_stream,
            &self.playback_buffer.?,
        });
        self.active_stream = started_stream;
    }

    pub fn stopStream(self: *Engine) !void {
        const started_stream = self.active_stream orelse return;
        const conn = if (self.lstn_connection) |*conn| conn else return error.ExpectedHello;

        var cleanup_error: ?anyerror = null;
        var connection_closed = false;

        conn.stopStream(started_stream) catch |err| {
            cleanup_error = err;
            conn.close();
            connection_closed = true;
        };

        if (self.playback_buffer) |*buffer| {
            buffer.stop() catch |err| {
                if (cleanup_error == null) cleanup_error = err;
            };
        }

        if (self.receive_thread) |thread| {
            thread.join();
            self.receive_thread = null;
        }

        self.audio_backend.impl.stop() catch {};
        self.audio_backend.impl.close();

        if (self.playback_buffer) |*buffer| {
            buffer.deinit();
            self.playback_buffer = null;
        }

        self.active_stream = null;
        if (connection_closed) {
            self.lstn_connection = null;
        }
        if (cleanup_error) |err| return err;
    }

    pub fn deinit(self: *Engine) void {
        self.stopStream() catch {};

        if (self.receive_thread) |thread| {
            thread.join();
            self.receive_thread = null;
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
        const read_result = lstn_connection.readAudioIntoBuffer(
            started_stream,
            output_format,
            playback_buffer,
            &expected_frame_offset,
        ) catch |err| switch (err) {
            error.OutputStopped => continue,
            else => return err,
        };

        switch (read_result) {
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

test "engine streams network audio to the selected output backend" {
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
    };
    const server_thread = try std.Thread.spawn(.{}, FakeLstnServer.run, .{&server});
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
        .playback_id = "client-test",
        .media_path = "strict-s24le-stereo.flac",
    });

    try selected_output.waitForCapturedBytes(expected_audio.len, 100_000);
    try engine.stopStream();

    server_thread.join();
    server_joined = true;
    try server.result;

    const captured = try selected_output.capturedBytes(allocator);
    defer allocator.free(captured);

    try std.testing.expectEqualSlices(u8, expected_audio, captured);
}

const FakeLstnServer = struct {
    io: std.Io,
    listener: *std.Io.net.Server,
    expected_audio: []const u8,
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
        try std.testing.expectEqualStrings("strict-s24le-stereo.flac", start_stream.media_path);

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

        try sendAudioFrame(
            &writer.interface,
            3,
            stream_id,
            generation_id,
            0,
            1,
            self.expected_audio[0..frame_bytes],
        );

        const first_ack = try readClientFrame(&reader.interface, &body_storage);
        try expectBufferStatusAck(first_ack, stream_id, generation_id, 3);

        try sendAudioFrame(
            &writer.interface,
            4,
            stream_id,
            generation_id,
            1,
            2,
            self.expected_audio[frame_bytes..],
        );

        const second_ack = try readClientFrame(&reader.interface, &body_storage);
        try expectBufferStatusAck(second_ack, stream_id, generation_id, 4);

        try sendEmptyServerMessage(
            &writer.interface,
            .stream_end,
            5,
            stream_id,
            generation_id,
        );

        const cancel = try readClientFrame(&reader.interface, &body_storage);
        try std.testing.expectEqual(protocol.MessageType.cancel_generation, cancel.header.message_type);
        try std.testing.expectEqual(stream_id, cancel.header.stream_id);
        try std.testing.expectEqual(generation_id, cancel.header.generation_id);
        try std.testing.expectEqual(@as(u32, 0), cancel.header.body_len);
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
