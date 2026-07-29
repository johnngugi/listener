const std = @import("std");

const decoder = @import("../decoder.zig");
const protocol = @import("lstn_protocol");
const request = @import("request.zig");

pub const StartStreamEvent = struct {
    playback_id: []const u8,
    stream_id: u64,
    generation_id: u64,
    start_frame: u64,
};

pub const BufferStatusEvent = struct {
    playback_id: []const u8,
    stream_id: u64,
    generation_id: u64,
    next_render_frame: u64,
};

pub const HookError = error{
    StartStreamRejected,
};

pub const Hooks = struct {
    context: ?*anyopaque = null,
    resolve_media_path: ?*const fn (
        context: ?*anyopaque,
        event: StartStreamEvent,
    ) anyerror![]const u8 = null,
    on_start_stream: ?*const fn (
        context: ?*anyopaque,
        event: StartStreamEvent,
    ) anyerror!void = null,
    on_buffer_status: ?*const fn (
        context: ?*anyopaque,
        event: BufferStatusEvent,
    ) void = null,
};

pub fn handle(
    io: std.Io,
    stream: std.Io.net.Stream,
    allocator: std.mem.Allocator,
    hooks: Hooks,
) !void {
    defer stream.close(io);

    var read_buffer: [1024]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);

    var stream_writer = stream.writer(io, &.{});

    var session = Session{
        .allocator = allocator,
        .hooks = hooks,
    };
    defer session.deinit();

    session.run(
        io,
        &stream_reader.interface,
        &stream_writer.interface,
        .{},
    ) catch |err| {
        if (isExpectedConnectionClose(
            err,
            stream_reader.err,
            stream_writer.err,
        )) return;

        return err;
    };
}

const HeartbeatConfig = struct {
    ping_interval: std.Io.Clock.Duration = durationSeconds(30),
    pong_timeout: std.Io.Clock.Duration = durationSeconds(10),
};

fn durationSeconds(seconds: u64) std.Io.Clock.Duration {
    return .{
        .raw = .{ .nanoseconds = @as(i96, seconds) * std.time.ns_per_s },
        .clock = .awake,
    };
}

fn durationMilliseconds(milliseconds: u64) std.Io.Clock.Duration {
    return .{
        .raw = .{ .nanoseconds = @as(i96, milliseconds) * std.time.ns_per_ms },
        .clock = .awake,
    };
}

const Session = struct {
    allocator: std.mem.Allocator,
    hooks: Hooks = .{},
    hello_received: bool = false,
    awaiting_pong: bool = false,
    heartbeat_generation: u64 = 0,
    next_server_sequence: u64 = 1,
    active_stream: ?ActiveStream = null,

    const ActiveStream = struct {
        decoder: decoder.AudioDecoder,
        playback_id: []u8,
        stream_id: u64,
        generation_id: u64,
        next_frame_offset: u64,
        sent_audio: std.ArrayList(SentAudio) = .empty,
        eof_reached: bool = false,

        fn deinit(self: *ActiveStream, allocator: std.mem.Allocator) void {
            self.decoder.deinit();
            allocator.free(self.playback_id);
            self.sent_audio.deinit(allocator);
        }
    };

    const SentAudio = struct {
        sequence: u64,
        frame_count: u32,
    };

    fn deinit(self: *Session) void {
        if (self.active_stream) |*active| {
            active.deinit(self.allocator);
        }
    }

    fn run(
        self: *Session,
        io: std.Io,
        reader: *std.Io.Reader,
        writer: *std.Io.Writer,
        heartbeat: HeartbeatConfig,
    ) !void {
        var body_buffer: [protocol.StartStream.max_wire_len]u8 = undefined;

        const Event = union(enum) {
            frame: anyerror!request.Frame,
            heartbeat: HeartbeatTimer,
        };
        var event_buffer: [3]Event = undefined;
        var select: std.Io.Select(Event) = .init(io, &event_buffer);
        defer select.cancelDiscard();

        select.async(.frame, request.read, .{ reader, &body_buffer });
        select.async(
            .heartbeat,
            waitHeartbeat,
            .{ io, heartbeat.ping_interval, HeartbeatTimer.Kind.interval, self.heartbeat_generation },
        );

        while (true) {
            const event = try select.await();
            switch (event) {
                .frame => |frame_result| {
                    const frame = frame_result catch |err| switch (err) {
                        error.EndOfStream => return,
                        else => return err,
                    };
                    const request_obj = request.decodeRequest(frame) catch |err| {
                        const failure = protocolFailure(err) orelse return err;
                        try self.sendProtocolError(writer, frame.header, failure);
                        select.async(.frame, request.read, .{ reader, &body_buffer });
                        continue;
                    };

                    const hello_was_received = self.hello_received;
                    const was_awaiting_pong = self.awaiting_pong;

                    self.handleRequest(writer, request_obj) catch |err| {
                        const failure = protocolFailure(err) orelse return err;
                        try self.sendProtocolError(writer, frame.header, failure);
                    };

                    const hello_just_arrived =
                        !hello_was_received and self.hello_received;

                    const pong_just_arrived =
                        was_awaiting_pong and !self.awaiting_pong;

                    if (hello_just_arrived or pong_just_arrived) {
                        self.heartbeat_generation += 1;
                        select.async(
                            .heartbeat,
                            waitHeartbeat,
                            .{
                                io,
                                heartbeat.ping_interval,
                                HeartbeatTimer.Kind.interval,
                                self.heartbeat_generation,
                            },
                        );
                    }

                    select.async(.frame, request.read, .{ reader, &body_buffer });
                },
                .heartbeat => |timer| {
                    try timer.result;
                    if (timer.generation != self.heartbeat_generation) continue;

                    switch (timer.kind) {
                        .interval => {
                            if (!self.hello_received) return error.HandshakeTimeout;

                            try self.sendPing(writer);
                            self.awaiting_pong = true;
                            select.async(
                                .heartbeat,
                                waitHeartbeat,
                                .{
                                    io,
                                    heartbeat.pong_timeout,
                                    HeartbeatTimer.Kind.pong_timeout,
                                    self.heartbeat_generation,
                                },
                            );
                        },
                        .pong_timeout => {
                            if (self.awaiting_pong) return error.HeartbeatTimeout;
                        },
                    }
                },
            }
        }
    }

    fn handleRequest(
        self: *Session,
        writer: *std.Io.Writer,
        request_obj: request.Request,
    ) !void {
        switch (request_obj.message) {
            .hello => {
                if (self.hello_received) return error.UnexpectedHello;

                try self.handleHello(writer);
                self.hello_received = true;
            },
            .start_stream => {
                try self.requireHello();
                try self.handleStartStream(writer, request_obj);
            },
            .buffer_status => {
                try self.requireHello();
                try self.handleBufferStatus(
                    writer,
                    request_obj,
                );
            },
            .cancel_generation => {
                try self.requireHello();
                try self.handleCancelGeneration(writer, request_obj);
            },
            .ping => {
                try self.requireHello();
                try self.sendPong(writer);
            },
            .pong => {
                try self.requireHello();
                self.awaiting_pong = false;
            },
        }
    }

    fn requireHello(self: *const Session) !void {
        if (!self.hello_received) return error.ExpectedHello;
    }

    fn handleHello(
        self: *Session,
        writer: *std.Io.Writer,
    ) !void {
        try self.sendEmptyMessage(writer, .hello_ack);
    }

    fn sendPing(self: *Session, writer: *std.Io.Writer) !void {
        try self.sendEmptyMessage(writer, .ping);
    }

    fn sendPong(self: *Session, writer: *std.Io.Writer) !void {
        try self.sendEmptyMessage(writer, .pong);
    }

    fn sendEmptyMessage(
        self: *Session,
        writer: *std.Io.Writer,
        message_type: protocol.MessageType,
    ) !void {
        const header = protocol.Header{
            .message_type = message_type,
            .body_len = 0,
            .sequence = self.next_server_sequence,
        };

        const header_bytes = try header.encode();
        try writer.writeAll(&header_bytes);
        self.next_server_sequence += 1;
    }

    fn handleStartStream(
        self: *Session,
        writer: *std.Io.Writer,
        request_obj: request.Request,
    ) !void {
        const start_stream = request_obj.message.start_stream;

        const playback_id = try self.allocator.dupe(u8, start_stream.playback_id);
        errdefer self.allocator.free(playback_id);

        const event = StartStreamEvent{
            .playback_id = start_stream.playback_id,
            .stream_id = request_obj.stream_id,
            .generation_id = request_obj.generation_id,
            .start_frame = start_stream.requested_start_frame,
        };

        const media_path = if (self.hooks.resolve_media_path) |resolve|
            try resolve(self.hooks.context, event)
        else
            return error.StartStreamRejected;

        const path = try self.allocator.dupeSentinel(
            u8,
            media_path,
            0,
        );
        defer self.allocator.free(path);

        var audio_decoder = try decoder.AudioDecoder.open(
            self.allocator,
            path,
            .{},
        );
        errdefer audio_decoder.deinit();

        if (start_stream.requested_start_frame != 0) {
            try audio_decoder.seekToFrame(start_stream.requested_start_frame);
        }

        const track = audio_decoder.trackInfo();
        const format = try protocolSampleFormat(track);
        const channels = std.math.cast(u16, track.channels) orelse
            return error.TooManyChannels;

        if (self.hooks.on_start_stream) |on_start_stream| {
            try on_start_stream(self.hooks.context, event);
        }

        const stream_info = protocol.StreamInfo{
            .format = format,
            .sample_rate = track.sample_rate,
            .channels = channels,
            .channel_layout = 0,
            .total_frames = track.duration_frames orelse 0,
            .actual_start_frame = start_stream.requested_start_frame,
            .recommended_buffer_frames = track.sample_rate / 2,
        };
        const body = stream_info.encode();

        const header = protocol.Header{
            .message_type = .stream_info,
            .body_len = protocol.StreamInfo.wire_len,
            .stream_id = request_obj.stream_id,
            .generation_id = request_obj.generation_id,
            .sequence = self.next_server_sequence,
        };
        const header_bytes = try header.encode();

        try writer.writeAll(&header_bytes);
        try writer.writeAll(&body);
        self.next_server_sequence += 1;

        if (self.active_stream) |*active| {
            active.deinit(self.allocator);
        }

        self.active_stream = .{
            .decoder = audio_decoder,
            .playback_id = playback_id,
            .stream_id = request_obj.stream_id,
            .generation_id = request_obj.generation_id,
            .next_frame_offset = start_stream.requested_start_frame,
            .sent_audio = .empty,
            .eof_reached = false,
        };
    }

    fn handleBufferStatus(
        self: *Session,
        writer: *std.Io.Writer,
        request_obj: request.Request,
    ) !void {
        const status = request_obj.message.buffer_status;

        const active = if (self.active_stream) |*active|
            active
        else
            return error.NoActiveStream;

        // Ignore messages belonging to an obsolete stream or generation.
        if (request_obj.stream_id != active.stream_id or request_obj.generation_id != active.generation_id) {
            return;
        }

        if (status.last_received_sequence >= self.next_server_sequence) {
            return error.InvalidAcknowledgment;
        }

        acknowledgeAudio(active, status.last_received_sequence);

        if (self.hooks.on_buffer_status) |on_buffer_status| {
            on_buffer_status(self.hooks.context, .{
                .playback_id = active.playback_id,
                .stream_id = active.stream_id,
                .generation_id = active.generation_id,
                .next_render_frame = status.next_render_frame,
            });
        }

        var unacknowledged_frames: u64 = 0;
        for (active.sent_audio.items) |sent| {
            unacknowledged_frames += sent.frame_count;
        }

        const credit: u64 = status.credit_frames;
        if (unacknowledged_frames >= credit) {
            return;
        }

        var remaining_credit = credit - unacknowledged_frames;
        while (remaining_credit > 0) {
            const frames_credit: u32 = @intCast(remaining_credit);

            const sent_frames = try self.sendNextAudioFrame(writer, frames_credit) orelse {
                return;
            };

            remaining_credit -= sent_frames;
        }
    }

    fn handleCancelGeneration(
        self: *Session,
        writer: *std.Io.Writer,
        request_obj: request.Request,
    ) !void {
        const active = if (self.active_stream) |*active|
            active
        else
            return;

        if (request_obj.stream_id != active.stream_id or request_obj.generation_id != active.generation_id) {
            return;
        }

        try sendStreamEnd(
            writer,
            active,
            self.next_server_sequence,
        );
        self.next_server_sequence += 1;

        active.deinit(self.allocator);
        self.active_stream = null;
    }

    fn sendProtocolError(
        self: *Session,
        writer: *std.Io.Writer,
        offending_header: protocol.Header,
        failure: ProtocolFailure,
    ) !void {
        const error_body = protocol.ProtocolErrorBody{
            .error_code = failure.code,
            .offending_message_type = @intFromEnum(
                offending_header.message_type,
            ),
            .offending_sequence = offending_header.sequence,
            .detail = failure.detail,
        };

        var body_storage: [protocol.ProtocolErrorBody.max_wire_len]u8 = undefined;
        const body = try error_body.encode(&body_storage);

        const header = protocol.Header{
            .message_type = .protocol_error,
            .body_len = @intCast(body.len),
            .stream_id = offending_header.stream_id,
            .generation_id = offending_header.generation_id,
            .sequence = self.next_server_sequence,
        };
        const header_bytes = try header.encode();

        try writer.writeAll(&header_bytes);
        try writer.writeAll(body);
        self.next_server_sequence += 1;
    }

    fn sendNextAudioFrame(
        self: *Session,
        writer: *std.Io.Writer,
        max_frames: u32,
    ) !?u32 {
        const active = if (self.active_stream) |*active|
            active
        else
            return error.NoActiveStream;

        if (active.eof_reached) return null;
        if (max_frames == 0) return null;

        var audio_buffer: [protocol.AudioFrame.max_data_len]u8 = undefined;

        const bytes_per_frame = active.decoder.trackInfo().bytesPerFrame();
        const max_frames_per_message = audio_buffer.len / bytes_per_frame;
        const frames_to_read = @min(@as(usize, max_frames), max_frames_per_message);

        // A single PCM frame cannot fit in an AUDIO_FRAME message.
        if (frames_to_read == 0) {
            return error.AudioFrameTooLarge;
        }

        const usable_len = frames_to_read * bytes_per_frame;
        const read_result = try active.decoder.read(audio_buffer[0..usable_len]);
        if (read_result.bytes == 0) {
            try sendStreamEnd(
                writer,
                active,
                self.next_server_sequence,
            );
            self.next_server_sequence += 1;
            active.eof_reached = true;
            return null;
        }

        const frame_count = std.math.cast(u32, read_result.frames) orelse
            return error.TooManyFrames;

        const sequence = self.next_server_sequence;

        try active.sent_audio.ensureUnusedCapacity(self.allocator, 1);

        const audio_frame = protocol.AudioFrame{
            .frame_offset = active.next_frame_offset,
            .frame_count = frame_count,
            .audio_data = audio_buffer[0..read_result.bytes],
        };

        var body_storage: [protocol.AudioFrame.max_wire_len]u8 = undefined;
        const body = try audio_frame.encode(&body_storage);

        const header = protocol.Header{
            .message_type = .audio_frame,
            .body_len = @intCast(body.len),
            .stream_id = active.stream_id,
            .generation_id = active.generation_id,
            .sequence = self.next_server_sequence,
        };
        const header_bytes = try header.encode();

        try writer.writeAll(&header_bytes);
        try writer.writeAll(body);

        active.sent_audio.appendAssumeCapacity(.{
            .sequence = sequence,
            .frame_count = frame_count,
        });

        active.next_frame_offset += frame_count;
        self.next_server_sequence += 1;

        if (read_result.end_of_stream) {
            try sendStreamEnd(
                writer,
                active,
                self.next_server_sequence,
            );
            self.next_server_sequence += 1;
            active.eof_reached = true;
        }

        return frame_count;
    }
};

const HeartbeatTimer = struct {
    const Kind = enum {
        interval,
        pong_timeout,
    };

    kind: Kind,
    generation: u64,
    result: std.Io.Cancelable!void,
};

fn waitHeartbeat(
    io: std.Io,
    duration: std.Io.Clock.Duration,
    kind: HeartbeatTimer.Kind,
    generation: u64,
) HeartbeatTimer {
    return .{
        .kind = kind,
        .generation = generation,
        .result = duration.sleep(io),
    };
}

fn sendStreamEnd(
    writer: *std.Io.Writer,
    active: *const Session.ActiveStream,
    sequence: u64,
) !void {
    const header = protocol.Header{
        .message_type = .stream_end,
        .body_len = 0,
        .stream_id = active.stream_id,
        .generation_id = active.generation_id,
        .sequence = sequence,
    };
    const header_bytes = try header.encode();

    try writer.writeAll(&header_bytes);
}

const ProtocolFailure = struct {
    code: protocol.ProtocolErrorCode,
    detail: []const u8,
};

fn protocolFailure(err: anyerror) ?ProtocolFailure {
    return switch (err) {
        error.InvalidBodyLength => .{
            .code = .invalid_body,
            .detail = "invalid message body",
        },
        error.InvalidPlaybackId => .{
            .code = .invalid_body,
            .detail = "invalid playback id",
        },
        error.UnexpectedClientMessage => .{
            .code = .unexpected_message,
            .detail = "message type is not valid from a client",
        },
        error.ExpectedHello => .{
            .code = .invalid_state,
            .detail = "HELLO must be sent first",
        },
        error.UnexpectedHello => .{
            .code = .invalid_state,
            .detail = "HELLO has already been received",
        },
        error.NoActiveStream => .{
            .code = .invalid_state,
            .detail = "no active stream",
        },
        error.InvalidAcknowledgment => .{
            .code = .invalid_body,
            .detail = "acknowledgment exceeds the latest server sequence",
        },
        error.SeekNotImplemented => .{
            .code = .unsupported_operation,
            .detail = "seeking is not implemented",
        },
        error.StartStreamRejected => .{
            .code = .invalid_state,
            .detail = "start stream was rejected",
        },
        error.CouldNotOpenInput,
        error.CouldNotFindStreamInfo,
        error.DecoderNotFound,
        error.NoAudioStream,
        error.CouldNotOpenDecoder,
        error.UnsupportedSampleFormat,
        error.UnsupportedSampleFormatConversion,
        error.TooManyChannels,
        => .{
            .code = .stream_unavailable,
            .detail = "media stream could not be opened",
        },
        else => null,
    };
}

fn isExpectedConnectionClose(
    err: anyerror,
    read_err: ?std.Io.net.Stream.Reader.Error,
    write_err: ?std.Io.net.Stream.Writer.Error,
) bool {
    return switch (err) {
        error.EndOfStream,
        error.HandshakeTimeout,
        error.HeartbeatTimeout,
        => true,
        error.ReadFailed => if (read_err) |actual|
            actual == error.ConnectionResetByPeer
        else
            false,
        error.WriteFailed => if (write_err) |actual|
            actual == error.ConnectionResetByPeer
        else
            false,
        else => false,
    };
}

test "connection timeouts close only their session" {
    try std.testing.expect(isExpectedConnectionClose(
        error.HandshakeTimeout,
        null,
        null,
    ));
    try std.testing.expect(isExpectedConnectionClose(
        error.HeartbeatTimeout,
        null,
        null,
    ));
}

fn acknowledgeAudio(active: *Session.ActiveStream, last_received_sequence: u64) void {
    var acknowledged_count: usize = 0;

    while (acknowledged_count < active.sent_audio.items.len) {
        const sent = active.sent_audio.items[acknowledged_count];

        if (sent.sequence > last_received_sequence) {
            break;
        }

        acknowledged_count += 1;
    }

    if (acknowledged_count == 0) {
        return;
    }

    const remaining = active.sent_audio.items[acknowledged_count..];

    @memmove(active.sent_audio.items[0..remaining.len], remaining);

    active.sent_audio.items.len = remaining.len;
}

test "ping receives pong" {
    var session = Session{
        .allocator = std.testing.allocator,
        .hello_received = true,
    };
    defer session.deinit();

    var response_storage: [protocol.header_wire_len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&response_storage);

    try session.handleRequest(&writer, .{
        .stream_id = 0,
        .generation_id = 0,
        .sequence = 1,
        .message = .{ .ping = {} },
    });

    const header = try protocol.Header.decode(writer.buffered());
    try std.testing.expectEqual(protocol.MessageType.pong, header.message_type);
    try std.testing.expectEqual(@as(u32, 0), header.body_len);
    try std.testing.expectEqual(@as(u64, 1), header.sequence);
}

test "pong completes an outstanding heartbeat" {
    var session = Session{
        .allocator = std.testing.allocator,
        .hello_received = true,
        .awaiting_pong = true,
    };
    defer session.deinit();

    var response_storage: [protocol.header_wire_len]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&response_storage);

    try session.handleRequest(&writer, .{
        .stream_id = 0,
        .generation_id = 0,
        .sequence = 1,
        .message = .{ .pong = {} },
    });

    try std.testing.expect(!session.awaiting_pong);
    try std.testing.expectEqual(@as(usize, 0), writer.buffered().len);
}

test "missing pong closes the session after the heartbeat timeout" {
    const io = std.testing.io;
    var handles: [2]std.posix.socket_t = undefined;
    if (std.posix.errno(std.posix.system.socketpair(
        std.posix.AF.UNIX,
        std.posix.SOCK.STREAM,
        0,
        &handles,
    )) != .SUCCESS) {
        return error.SocketPairFailed;
    }
    const sockets = [2]std.Io.net.Socket{
        .{ .handle = handles[0], .address = .{ .ip4 = .loopback(0) } },
        .{ .handle = handles[1], .address = .{ .ip4 = .loopback(0) } },
    };
    defer sockets[0].close(io);
    defer sockets[1].close(io);

    const server_stream = std.Io.net.Stream{ .socket = sockets[0] };
    const client_stream = std.Io.net.Stream{ .socket = sockets[1] };

    var server_read_buffer: [1024]u8 = undefined;
    var server_reader = server_stream.reader(io, &server_read_buffer);
    var server_writer = server_stream.writer(io, &.{});

    var session = Session{ .allocator = std.testing.allocator };
    defer session.deinit();

    var server_future = try std.Io.concurrent(
        io,
        Session.run,
        .{
            &session,
            io,
            &server_reader.interface,
            &server_writer.interface,
            HeartbeatConfig{
                .ping_interval = durationMilliseconds(10),
                .pong_timeout = durationMilliseconds(10),
            },
        },
    );

    var client_writer = client_stream.writer(io, &.{});
    const hello = try (protocol.Header{
        .message_type = .hello,
        .body_len = 0,
        .sequence = 1,
    }).encode();
    try client_writer.interface.writeAll(&hello);

    var client_read_buffer: [1024]u8 = undefined;
    var client_reader = client_stream.reader(io, &client_read_buffer);
    var body_storage: [protocol.StartStream.max_wire_len]u8 = undefined;

    const hello_ack = try request.read(&client_reader.interface, &body_storage);
    try std.testing.expectEqual(protocol.MessageType.hello_ack, hello_ack.header.message_type);

    const ping = try request.read(&client_reader.interface, &body_storage);
    try std.testing.expectEqual(protocol.MessageType.ping, ping.header.message_type);

    try std.testing.expectError(error.HeartbeatTimeout, server_future.await(io));
}

test "server sends decoded fixture PCM as contiguous audio frames" {
    try expectFixtureAudio(.{
        .name = "strict-s16le-stereo",
        .flac_path = "testdata/fixtures/strict-s16le-stereo.flac",
        .expected_pcm = @embedFile("../testdata/fixtures/strict-s16le-stereo.expected.pcm"),
        .expected_format = .pcm_s16le,
        .expected_sample_rate = 44_100,
        .expected_channels = 2,
    });

    try expectFixtureAudio(.{
        .name = "strict-s24le-stereo",
        .flac_path = "testdata/fixtures/strict-s24le-stereo.flac",
        .expected_pcm = @embedFile("../testdata/fixtures/strict-s24le-stereo.expected-24in32.pcm"),
        .expected_format = .pcm_s24le_in_s32le,
        .expected_sample_rate = 96_000,
        .expected_channels = 2,
    });
}

test "server streams fixture PCM from requested start frame" {
    try expectFixtureAudio(.{
        .name = "seekable-s16le-stereo",
        .flac_path = "testdata/fixtures/seekable-s16le-stereo.flac",
        .expected_pcm = @embedFile("../testdata/fixtures/seekable-s16le-stereo.expected.pcm"),
        .expected_format = .pcm_s16le,
        .expected_sample_rate = 44_100,
        .expected_channels = 2,
        .start_frame = 6_000,
    });
}

const AudioFixture = struct {
    name: []const u8,
    flac_path: []const u8,
    expected_pcm: []const u8,
    expected_format: protocol.SampleFormat,
    expected_sample_rate: u32,
    expected_channels: u16,
    start_frame: u64 = 0,
};

fn expectFixtureAudio(fixture: AudioFixture) !void {
    const allocator = std.testing.allocator;
    const stream_id: u64 = 41;
    const generation_id: u64 = 7;

    var session = Session{
        .allocator = allocator,
        .hello_received = true,
        .hooks = .{
            .context = @ptrCast(@constCast(&fixture)),
            .resolve_media_path = resolveFixtureMediaPath,
        },
    };
    defer session.deinit();

    var response_storage: [64 * 1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&response_storage);

    try session.handleRequest(&writer, .{
        .stream_id = stream_id,
        .generation_id = generation_id,
        .sequence = 2,
        .message = .{ .start_stream = .{
            .requested_start_frame = fixture.start_frame,
            .playback_id = fixture.name,
        } },
    });

    var offset: usize = 0;
    const stream_info_frame = try readServerFrame(writer.buffered(), &offset);
    try expectServerFrameScope(stream_info_frame.header, stream_id, generation_id);
    try std.testing.expectEqual(protocol.MessageType.stream_info, stream_info_frame.header.message_type);

    const stream_info = try protocol.StreamInfo.decode(stream_info_frame.body);
    try std.testing.expectEqual(fixture.expected_format, stream_info.format);
    try std.testing.expectEqual(fixture.expected_sample_rate, stream_info.sample_rate);
    try std.testing.expectEqual(fixture.expected_channels, stream_info.channels);
    try std.testing.expectEqual(fixture.start_frame, stream_info.actual_start_frame);

    const bytes_per_frame = try protocolBytesPerFrame(stream_info.format, stream_info.channels);
    const start_frame: usize = @intCast(fixture.start_frame);
    const start_byte = start_frame * bytes_per_frame;

    try std.testing.expect(start_byte <= fixture.expected_pcm.len);
    try std.testing.expectEqual(@as(usize, 0), fixture.expected_pcm.len % bytes_per_frame);

    const expected_seeked_pcm = fixture.expected_pcm[start_byte..];
    const expected_frames = fixture.expected_pcm.len / bytes_per_frame;
    try std.testing.expectEqual(@as(u64, @intCast(expected_frames)), stream_info.total_frames);

    try session.handleRequest(&writer, .{
        .stream_id = stream_id,
        .generation_id = generation_id,
        .sequence = 3,
        .message = .{ .buffer_status = .{
            .buffered_frames = 0,
            .credit_frames = @intCast(expected_frames),
            .next_render_frame = 0,
            .last_received_sequence = stream_info_frame.header.sequence,
            .underrun_count = 0,
        } },
    });

    var received_pcm: std.ArrayList(u8) = .empty;
    defer received_pcm.deinit(allocator);

    var expected_frame_offset: u64 = fixture.start_frame;
    var saw_stream_end = false;

    while (offset < writer.buffered().len) {
        const frame = try readServerFrame(writer.buffered(), &offset);
        try expectServerFrameScope(frame.header, stream_id, generation_id);

        switch (frame.header.message_type) {
            .audio_frame => {
                const audio_frame = try protocol.AudioFrame.decode(frame.body);
                try std.testing.expectEqual(expected_frame_offset, audio_frame.frame_offset);
                try std.testing.expectEqual(
                    @as(usize, audio_frame.frame_count) * bytes_per_frame,
                    audio_frame.audio_data.len,
                );

                try received_pcm.appendSlice(allocator, audio_frame.audio_data);
                expected_frame_offset += audio_frame.frame_count;
            },
            .stream_end => {
                try std.testing.expectEqual(@as(u32, 0), frame.header.body_len);
                saw_stream_end = true;
            },
            else => return error.UnexpectedServerMessage,
        }
    }

    try std.testing.expect(saw_stream_end);
    try std.testing.expectEqual(
        @as(u64, @intCast(expected_frames)),
        expected_frame_offset,
    );
    try std.testing.expectEqualSlices(u8, expected_seeked_pcm, received_pcm.items);
}

fn resolveFixtureMediaPath(
    context: ?*anyopaque,
    event: StartStreamEvent,
) anyerror![]const u8 {
    _ = event;
    const fixture: *const AudioFixture = @ptrCast(@alignCast(context.?));
    return fixture.flac_path;
}

const ServerFrame = struct {
    header: protocol.Header,
    body: []const u8,
};

fn readServerFrame(bytes: []const u8, offset: *usize) !ServerFrame {
    if (bytes.len - offset.* < protocol.header_wire_len) {
        return error.TruncatedHeader;
    }

    const header_start = offset.*;
    const header_end = header_start + protocol.header_wire_len;
    const header = try protocol.Header.decode(bytes[header_start..header_end]);

    const body_start = header_end;
    const body_end = body_start + @as(usize, header.body_len);
    if (body_end > bytes.len) return error.TruncatedBody;

    offset.* = body_end;
    return .{
        .header = header,
        .body = bytes[body_start..body_end],
    };
}

fn expectServerFrameScope(
    header: protocol.Header,
    stream_id: u64,
    generation_id: u64,
) !void {
    try std.testing.expectEqual(stream_id, header.stream_id);
    try std.testing.expectEqual(generation_id, header.generation_id);
}

fn protocolBytesPerFrame(format: protocol.SampleFormat, channels: u16) !usize {
    const bytes_per_sample: usize = switch (format) {
        .pcm_s16le => 2,
        .pcm_s24le_packed => 3,
        .pcm_s24le_in_s32le,
        .pcm_s32le,
        .pcm_f32le,
        => 4,
    };
    return bytes_per_sample * @as(usize, channels);
}

fn protocolSampleFormat(track: decoder.TrackInfo) !protocol.SampleFormat {
    return switch (track.output_sample_format) {
        .s16 => if (track.valid_bits_per_sample == 16)
            .pcm_s16le
        else
            error.UnsupportedSampleFormat,
        .s32 => switch (track.valid_bits_per_sample) {
            24 => .pcm_s24le_in_s32le,
            32 => .pcm_s32le,
            else => error.UnsupportedSampleFormat,
        },
    };
}
