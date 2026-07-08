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
    io: std.Io,
    connection: net.Stream,
    outbound_mutex: std.Io.Mutex = .init,
    next_client_sequence: u64 = 2,
    next_stream_id: u64 = 1,
    next_generation_id: u64 = 1,

    pub fn connect(io: std.Io, config: Config) !Connection {
        const address = try net.IpAddress.parse(config.host, config.port);
        const connection = try address.connect(io, .{
            .mode = net.Socket.Mode.stream,
            .protocol = net.Protocol.tcp,
        });

        var result = Connection{
            .io = io,
            .connection = connection,
        };
        errdefer result.connection.close(io);

        try result.handshake();
        return result;
    }

    pub fn close(self: *Connection) void {
        self.connection.close(self.io);
    }

    pub fn startStream(
        self: *Connection,
        message: lstn_protocol.StartStream,
    ) !StartedStream {
        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        var stream_reader = self.connection.reader(self.io, &.{});
        const reader = &stream_reader.interface;

        const stream_id = self.next_stream_id;
        const generation_id = self.next_generation_id;

        try sendStartStream(writer, .{
            .message = message,
            .stream_id = stream_id,
            .generation_id = generation_id,
            .sequence = self.next_client_sequence,
        });

        self.next_client_sequence += 1;
        self.next_stream_id += 1;
        self.next_generation_id += 1;

        const info = try readStreamInfo(reader, stream_id, generation_id);
        return .{
            .stream_id = stream_id,
            .generation_id = generation_id,
            .info = info,
        };
    }

    pub fn sendBufferStatus(
        self: *Connection,
        stream: StartedStream,
        buffer: *ring_buffer.SharedPcmRingBuffer,
        last_received_sequence: u64,
    ) !void {
        try self.outbound_mutex.lock(self.io);
        defer self.outbound_mutex.unlock(self.io);

        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        try self.sendBufferStatusWithWriter(
            writer,
            stream,
            buffer,
            last_received_sequence,
        );
    }

    pub fn sendPong(self: *Connection) !void {
        try self.outbound_mutex.lock(self.io);
        defer self.outbound_mutex.unlock(self.io);

        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        const header = lstn_protocol.Header{
            .message_type = .pong,
            .body_len = 0,
            .sequence = self.next_client_sequence,
        };
        const header_bytes = try header.encode();

        try writer.writeAll(&header_bytes);
        self.next_client_sequence += 1;
    }

    pub fn readAudioIntoBuffer(
        self: *Connection,
        stream: StartedStream,
        output_format: audio_backend.OutputFormat,
        buffer: *ring_buffer.SharedPcmRingBuffer,
        expected_frame_offset: *u64,
    ) !ReadAudioResult {
        var stream_reader = self.connection.reader(self.io, &.{});
        const reader = &stream_reader.interface;

        var header_bytes: [lstn_protocol.header_wire_len]u8 = undefined;
        try reader.readSliceAll(&header_bytes);

        const header = try lstn_protocol.Header.decode(&header_bytes);
        if (header.message_type == .ping) {
            if (header.body_len != 0) return error.InvalidBodyLength;
            return .ping;
        }

        if (header.stream_id != stream.stream_id or
            header.generation_id != stream.generation_id)
        {
            try discardBody(reader, header.body_len);
            return .ignored_message;
        }

        switch (header.message_type) {
            .audio_frame => {
                var body: [lstn_protocol.AudioFrame.max_wire_len]u8 = undefined;
                if (header.body_len > body.len) return error.InvalidBodyLength;
                try reader.readSliceAll(body[0..header.body_len]);

                const audio_frame = try lstn_protocol.AudioFrame.decode(body[0..header.body_len]);
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
                try discardBody(reader, header.body_len);
                return ClientError.StartStreamRejected;
            },
            else => {
                try discardBody(reader, header.body_len);
                return ClientError.UnexpectedStreamMessage;
            },
        }
    }

    pub fn stopStream(self: *Connection, stream: StartedStream) !void {
        try self.outbound_mutex.lock(self.io);
        defer self.outbound_mutex.unlock(self.io);

        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        try sendCancelGeneration(
            writer,
            stream.stream_id,
            stream.generation_id,
            self.next_client_sequence,
        );
        self.next_client_sequence += 1;
    }

    fn sendBufferStatusWithWriter(
        self: *Connection,
        writer: *std.Io.Writer,
        stream: StartedStream,
        buffer: *ring_buffer.SharedPcmRingBuffer,
        last_received_sequence: u64,
    ) !void {
        const readable_frames = try buffer.readableFrames();
        const capacity_frames = try buffer.capacityFrames();
        const next_render_frame = try buffer.framesRead();

        const status = lstn_protocol.BufferStatus{
            .buffered_frames = saturatedU32(readable_frames),
            .credit_frames = saturatedU32(capacity_frames),
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
            .sequence = self.next_client_sequence,
        };
        const header_bytes = try header.encode();

        try writer.writeAll(&header_bytes);
        try writer.writeAll(&body);
        self.next_client_sequence += 1;
    }

    fn handshake(self: *Connection) !void {
        var stream_writer = self.connection.writer(self.io, &.{});
        const writer = &stream_writer.interface;

        var stream_reader = self.connection.reader(self.io, &.{});
        const reader = &stream_reader.interface;

        try sendHello(writer);
        try readHelloAck(reader);
    }
};

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
    ping,
    ignored_message,
};

const StartStreamRequest = struct {
    message: lstn_protocol.StartStream,
    stream_id: u64,
    generation_id: u64,
    sequence: u64,
};

fn sendHello(writer: *std.Io.Writer) !void {
    const header = lstn_protocol.Header{
        .message_type = lstn_protocol.MessageType.hello,
        .body_len = 0,
        .sequence = 1,
    };

    const header_bytes = try header.encode();
    try writer.writeAll(&header_bytes);
}

fn readHelloAck(reader: *std.Io.Reader) !void {
    var header_bytes: [lstn_protocol.header_wire_len]u8 = undefined;
    try reader.readSliceAll(&header_bytes);

    const header = try lstn_protocol.Header.decode(&header_bytes);
    if (header.message_type != .hello_ack) {
        return ClientError.UnexpectedHelloAck;
    }
    if (header.body_len != 0) {
        return ClientError.UnexpectedHelloAckBody;
    }
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

fn readStreamInfo(
    reader: *std.Io.Reader,
    stream_id: u64,
    generation_id: u64,
) !lstn_protocol.StreamInfo {
    var header_bytes: [lstn_protocol.header_wire_len]u8 = undefined;
    try reader.readSliceAll(&header_bytes);

    const header = try lstn_protocol.Header.decode(&header_bytes);
    if (header.stream_id != stream_id or header.generation_id != generation_id) {
        return ClientError.UnexpectedStreamScope;
    }

    switch (header.message_type) {
        .stream_info => {
            var body: [lstn_protocol.StreamInfo.wire_len]u8 = undefined;
            if (header.body_len != body.len) {
                return error.InvalidBodyLength;
            }

            try reader.readSliceAll(&body);
            return try lstn_protocol.StreamInfo.decode(&body);
        },
        .protocol_error => {
            var body: [lstn_protocol.ProtocolErrorBody.max_wire_len]u8 = undefined;
            if (header.body_len > body.len) {
                return error.InvalidBodyLength;
            }

            try reader.readSliceAll(body[0..header.body_len]);
            return ClientError.StartStreamRejected;
        },
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

fn discardBody(reader: *std.Io.Reader, body_len: u32) !void {
    var remaining: usize = body_len;
    var scratch: [1024]u8 = undefined;

    while (remaining > 0) {
        const chunk_len = @min(remaining, scratch.len);
        try reader.readSliceAll(scratch[0..chunk_len]);
        remaining -= chunk_len;
    }
}

fn saturatedU32(value: usize) u32 {
    return std.math.cast(u32, value) orelse std.math.maxInt(u32);
}
