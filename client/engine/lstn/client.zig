const std = @import("std");
const net = std.Io.net;

const lstn_protocol = @import("lstn_protocol");
const audio_backend = @import("audio_backend");
const ring_buffer = @import("audio_ring_buffer");

pub const ClientError = error{
    UnexpectedHelloAck,
    UnexpectedHelloAckBody,
    UnexpectedStreamInfo,
    UnexpectedStreamScope,
    UnexpectedStreamMessage,
    UnexpectedAudioFrameOffset,
    StartStreamRejected,
    OutputStopped,
};

pub const Config = struct {
    host: []const u8,
    port: u16,
};

pub const Connection = struct {
    shared: *SharedState,
    reader_thread: ?std.Thread = null,
    closed: bool = false,

    pub fn connect(
        io: std.Io,
        allocator: std.mem.Allocator,
        config: Config,
    ) !Connection {
        const address = try net.IpAddress.parse(config.host, config.port);
        const connection = try address.connect(io, .{
            .mode = net.Socket.Mode.stream,
            .protocol = net.Protocol.tcp,
        });

        const shared = try allocator.create(SharedState);
        shared.* = .{
            .io = io,
            .allocator = allocator,
            .connection = connection,
        };

        var result = Connection{
            .shared = shared,
        };
        errdefer result.close();

        try shared.sendHello();
        result.reader_thread = try std.Thread.spawn(.{}, readerMain, .{shared});
        try result.readHelloAck();
        return result;
    }

    pub fn close(self: *Connection) void {
        if (self.closed) return;
        self.shutdown();

        if (self.reader_thread) |thread| {
            thread.join();
            self.reader_thread = null;
        }
        self.shared.connection.close(self.shared.io);

        if (self.shared.pending_frame) |frame| {
            frame.deinit(self.shared.allocator);
            self.shared.pending_frame = null;
        }

        const allocator = self.shared.allocator;
        allocator.destroy(self.shared);
        self.closed = true;
    }

    /// Stops socket I/O and wakes frame consumers. The Connection remains
    /// allocated until close() joins its lifetime reader thread.
    pub fn shutdown(self: *Connection) void {
        if (self.closed) return;

        self.shared.state_mutex.lock(self.shared.io) catch {
            self.shared.connection.shutdown(self.shared.io, .both) catch {};
            return;
        };
        if (!self.shared.closing) {
            self.shared.closing = true;
            self.shared.changed.broadcast(self.shared.io);
            self.shared.connection.shutdown(self.shared.io, .both) catch {};
        }
        self.shared.state_mutex.unlock(self.shared.io);
    }

    pub fn isOpen(self: *Connection) bool {
        if (self.closed) return false;

        self.shared.state_mutex.lockUncancelable(self.shared.io);
        defer self.shared.state_mutex.unlock(self.shared.io);
        return !self.shared.closing and !self.shared.reader_done;
    }

    pub fn startStream(
        self: *Connection,
        message: lstn_protocol.StartStream,
    ) !StartedStream {
        const stream_id, const generation_id = ids: {
            try self.shared.outbound_mutex.lock(self.shared.io);
            defer self.shared.outbound_mutex.unlock(self.shared.io);

            const stream_id = self.shared.next_stream_id;
            const generation_id = self.shared.next_generation_id;
            var stream_writer = self.shared.connection.writer(self.shared.io, &.{});

            try sendStartStream(&stream_writer.interface, .{
                .message = message,
                .stream_id = stream_id,
                .generation_id = generation_id,
                .sequence = self.shared.next_client_sequence,
            });

            self.shared.next_client_sequence += 1;
            self.shared.next_stream_id += 1;
            self.shared.next_generation_id += 1;
            break :ids .{ stream_id, generation_id };
        };

        const frame = try self.shared.takeFrame();
        defer frame.deinit(self.shared.allocator);

        return .{
            .stream_id = stream_id,
            .generation_id = generation_id,
            .info = try decodeStreamInfo(frame, stream_id, generation_id),
        };
    }

    pub fn sendBufferStatus(
        self: *Connection,
        stream: StartedStream,
        buffer: *ring_buffer.SharedPcmRingBuffer,
        last_received_sequence: u64,
        paused: *const std.atomic.Value(bool),
    ) !void {
        try self.shared.outbound_mutex.lock(self.shared.io);
        defer self.shared.outbound_mutex.unlock(self.shared.io);

        var stream_writer = self.shared.connection.writer(self.shared.io, &.{});
        const writer = &stream_writer.interface;

        try self.sendBufferStatusWithWriter(
            writer,
            stream,
            buffer,
            last_received_sequence,
            paused.load(.acquire),
        );
    }

    pub fn readAudioIntoBuffer(
        self: *Connection,
        stream: StartedStream,
        output_format: audio_backend.OutputFormat,
        buffer: *ring_buffer.SharedPcmRingBuffer,
        expected_frame_offset: *u64,
    ) !ReadAudioResult {
        const frame = try self.shared.takeFrame();
        defer frame.deinit(self.shared.allocator);
        const header = frame.header;

        if (header.stream_id != stream.stream_id or
            header.generation_id != stream.generation_id)
        {
            return .ignored_message;
        }

        switch (header.message_type) {
            .audio_frame => {
                const audio_frame = try lstn_protocol.AudioFrame.decode(frame.body);
                if (audio_frame.frame_offset != expected_frame_offset.*) {
                    return ClientError.UnexpectedAudioFrameOffset;
                }

                writeAudioFrameToBuffer(output_format, buffer, audio_frame) catch |err| {
                    // The frame has already been consumed from the socket.
                    // Keep its offset accounted for while cancellation drains
                    // any audio queued before STREAM_END.
                    if (err == ClientError.OutputStopped) {
                        expected_frame_offset.* += audio_frame.frame_count;
                    }
                    return err;
                };
                expected_frame_offset.* += audio_frame.frame_count;

                return .{
                    .audio_frame = .{
                        .last_received_sequence = header.sequence,
                        .frame_count = audio_frame.frame_count,
                    },
                };
            },
            .stream_end => {
                if (header.body_len != 0) return error.InvalidBodyLength;
                try buffer.markEndOfStream();
                return .stream_end;
            },
            .protocol_error => {
                return ClientError.StartStreamRejected;
            },
            else => return ClientError.UnexpectedStreamMessage,
        }
    }

    pub fn stopStream(self: *Connection, stream: StartedStream) !void {
        try self.shared.outbound_mutex.lock(self.shared.io);
        defer self.shared.outbound_mutex.unlock(self.shared.io);

        var stream_writer = self.shared.connection.writer(self.shared.io, &.{});
        const writer = &stream_writer.interface;

        try sendCancelGeneration(
            writer,
            stream.stream_id,
            stream.generation_id,
            self.shared.next_client_sequence,
        );
        self.shared.next_client_sequence += 1;
    }

    fn sendBufferStatusWithWriter(
        self: *Connection,
        writer: *std.Io.Writer,
        stream: StartedStream,
        buffer: *ring_buffer.SharedPcmRingBuffer,
        last_received_sequence: u64,
        paused: bool,
    ) !void {
        const readable_frames = try buffer.readableFrames();
        const capacity_frames = try buffer.capacityFrames();
        const next_render_frame = try buffer.framesRead();

        const status = lstn_protocol.BufferStatus{
            .buffered_frames = saturatedU32(readable_frames),
            .credit_frames = if (paused) 0 else saturatedU32(capacity_frames),
            .next_render_frame = next_render_frame,
            .last_received_sequence = last_received_sequence,
            .underrun_count = 0,
        };
        const body = status.encode();

        const header = lstn_protocol.Header{
            .message_type = .buffer_status,
            .body_len = lstn_protocol.BufferStatus.wire_len,
            .stream_id = stream.stream_id,
            .generation_id = stream.generation_id,
            .sequence = self.shared.next_client_sequence,
        };
        const header_bytes = try header.encode();

        try writer.writeAll(&header_bytes);
        try writer.writeAll(&body);
        self.shared.next_client_sequence += 1;
    }

    fn readHelloAck(self: *Connection) !void {
        const frame = try self.shared.takeFrame();
        defer frame.deinit(self.shared.allocator);

        if (frame.header.message_type != .hello_ack) {
            return ClientError.UnexpectedHelloAck;
        }
        if (frame.body.len != 0) {
            return ClientError.UnexpectedHelloAckBody;
        }
    }
};

const IncomingFrame = struct {
    header: lstn_protocol.Header,
    body: []u8,

    fn deinit(self: IncomingFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

const SharedState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    connection: net.Stream,
    outbound_mutex: std.Io.Mutex = .init,
    state_mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    next_client_sequence: u64 = 2,
    next_stream_id: u64 = 1,
    next_generation_id: u64 = 1,
    pending_frame: ?IncomingFrame = null,
    closing: bool = false,
    reader_done: bool = false,
    reader_error: ?anyerror = null,

    fn sendHello(self: *SharedState) !void {
        var stream_writer = self.connection.writer(self.io, &.{});
        try sendHelloFrame(&stream_writer.interface);
    }

    fn sendPong(self: *SharedState) !void {
        try self.outbound_mutex.lock(self.io);
        defer self.outbound_mutex.unlock(self.io);

        var stream_writer = self.connection.writer(self.io, &.{});
        const header = lstn_protocol.Header{
            .message_type = .pong,
            .body_len = 0,
            .sequence = self.next_client_sequence,
        };
        const header_bytes = try header.encode();
        try stream_writer.interface.writeAll(&header_bytes);
        self.next_client_sequence += 1;
    }

    fn readLoop(self: *SharedState) !void {
        var read_buffer: [4096]u8 = undefined;
        var stream_reader = self.connection.reader(self.io, &read_buffer);

        while (true) {
            var header_bytes: [lstn_protocol.header_wire_len]u8 = undefined;
            try stream_reader.interface.readSliceAll(&header_bytes);
            const header = try lstn_protocol.Header.decode(&header_bytes);

            const body = try self.allocator.alloc(u8, @intCast(header.body_len));
            var body_owned = true;
            defer if (body_owned) self.allocator.free(body);
            try stream_reader.interface.readSliceAll(body);

            if (header.message_type == .ping) {
                if (body.len != 0) return error.InvalidBodyLength;
                try self.sendPong();
                continue;
            }

            try self.state_mutex.lock(self.io);
            defer self.state_mutex.unlock(self.io);

            while (self.pending_frame != null and !self.closing) {
                try self.changed.wait(self.io, &self.state_mutex);
            }
            if (self.closing) {
                return;
            }

            self.pending_frame = .{ .header = header, .body = body };
            body_owned = false;
            self.changed.broadcast(self.io);
        }
    }

    fn takeFrame(self: *SharedState) !IncomingFrame {
        try self.state_mutex.lock(self.io);
        defer self.state_mutex.unlock(self.io);

        while (self.pending_frame == null and !self.reader_done and !self.closing) {
            try self.changed.wait(self.io, &self.state_mutex);
        }

        if (self.pending_frame) |frame| {
            self.pending_frame = null;
            self.changed.broadcast(self.io);
            return frame;
        }
        if (self.reader_error) |err| return err;
        return error.EndOfStream;
    }
};

fn readerMain(shared: *SharedState) void {
    shared.readLoop() catch |err| {
        finishReader(shared, err);
        return;
    };
    finishReader(shared, null);
}

fn finishReader(shared: *SharedState, reader_error: ?anyerror) void {
    shared.state_mutex.lock(shared.io) catch return;
    defer shared.state_mutex.unlock(shared.io);
    shared.reader_done = true;
    if (!shared.closing) shared.reader_error = reader_error;
    shared.changed.broadcast(shared.io);
}

pub const StartedStream = struct {
    stream_id: u64,
    generation_id: u64,
    info: lstn_protocol.StreamInfo,
};

pub const ReadAudioResult = union(enum) {
    audio_frame: struct {
        last_received_sequence: u64,
        frame_count: u32,
    },
    stream_end,
    ignored_message,
};

const StartStreamRequest = struct {
    message: lstn_protocol.StartStream,
    stream_id: u64,
    generation_id: u64,
    sequence: u64,
};

fn sendHelloFrame(writer: *std.Io.Writer) !void {
    const header = lstn_protocol.Header{
        .message_type = lstn_protocol.MessageType.hello,
        .body_len = 0,
        .sequence = 1,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);
}

fn sendStartStream(
    writer: *std.Io.Writer,
    request: StartStreamRequest,
) !void {
    var body_storage: [lstn_protocol.StartStream.max_wire_len]u8 = undefined;
    const body = try request.message.encode(&body_storage);

    const header = lstn_protocol.Header{
        .message_type = .start_stream,
        .body_len = @intCast(body.len),
        .stream_id = request.stream_id,
        .generation_id = request.generation_id,
        .sequence = request.sequence,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);
    try writer.writeAll(body);
}

fn decodeStreamInfo(
    frame: IncomingFrame,
    stream_id: u64,
    generation_id: u64,
) !lstn_protocol.StreamInfo {
    const header = frame.header;
    if (header.stream_id != stream_id or header.generation_id != generation_id) {
        return ClientError.UnexpectedStreamScope;
    }

    switch (header.message_type) {
        .stream_info => {
            if (frame.body.len != lstn_protocol.StreamInfo.wire_len) {
                return error.InvalidBodyLength;
            }
            return try lstn_protocol.StreamInfo.decode(frame.body);
        },
        .protocol_error => return ClientError.StartStreamRejected,
        else => return ClientError.UnexpectedStreamInfo,
    }
}

fn writeAudioFrameToBuffer(
    output_format: audio_backend.OutputFormat,
    buffer: *ring_buffer.SharedPcmRingBuffer,
    audio_frame: lstn_protocol.AudioFrame,
) !void {
    const sample_bytes = try audio_backend.sample_format_bytes(output_format.sample_format);
    const frame_bytes = @as(usize, output_format.channels) * sample_bytes;
    const expected_len = @as(usize, audio_frame.frame_count) * frame_bytes;
    if (audio_frame.audio_data.len != expected_len) {
        return error.InvalidBodyLength;
    }

    var remaining = audio_frame.audio_data;
    while (remaining.len > 0) {
        const written_frames = try buffer.writeBlocking(remaining);
        if (written_frames == 0) return ClientError.OutputStopped;
        remaining = remaining[written_frames * frame_bytes ..];
    }
}

fn sendCancelGeneration(
    writer: *std.Io.Writer,
    stream_id: u64,
    generation_id: u64,
    sequence: u64,
) !void {
    const header = lstn_protocol.Header{
        .message_type = lstn_protocol.MessageType.cancel_generation,
        .body_len = 0,
        .stream_id = stream_id,
        .generation_id = generation_id,
        .sequence = sequence,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);
}

fn saturatedU32(value: usize) u32 {
    return std.math.cast(u32, value) orelse std.math.maxInt(u32);
}
