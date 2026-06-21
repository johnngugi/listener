const std = @import("std");

const decoder = @import("decoder.zig");
const protocol = @import("protocol.zig");
const request = @import("request.zig");

pub fn handle(
    io: std.Io,
    stream: std.Io.net.Stream,
    allocator: std.mem.Allocator,
) !void {
    defer stream.close(io);

    var read_buffer: [1024]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);

    var stream_writer = stream.writer(io, &.{});

    var session = Session{
        .allocator = allocator,
    };
    defer session.deinit();

    try session.run(
        &stream_reader.interface,
        &stream_writer.interface,
    );
}

const Session = struct {
    allocator: std.mem.Allocator,
    hello_received: bool = false,
    next_server_sequence: u64 = 1,
    active_stream: ?ActiveStream = null,

    const ActiveStream = struct {
        decoder: decoder.AudioDecoder,
        stream_id: u64,
        generation_id: u64,
        next_frame_offset: u64,
        sent_audio: std.ArrayList(SentAudio) = .empty,
        eof_reached: bool = false,

        fn deinit(self: *ActiveStream, allocator: std.mem.Allocator) void {
            self.decoder.deinit();
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
        reader: *std.Io.Reader,
        writer: *std.Io.Writer,
    ) !void {
        var body_buffer: [protocol.StartStream.max_wire_len]u8 = undefined;

        while (true) {
            const frame = request.read(reader, &body_buffer) catch |err| switch (err) {
                error.EndOfStream => return,
                else => return err,
            };
            const request_obj = try request.decodeRequest(frame);

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
                    try self.handleCancelGeneration(request_obj);
                },
                else => {
                    try self.requireHello();
                    std.debug.print("todo: {}\n", .{request_obj.message});
                },
            }
        }
    }

    fn requireHello(self: *const Session) !void {
        if (!self.hello_received) return error.ExpectedHello;
    }

    fn handleHello(
        self: *Session,
        writer: *std.Io.Writer,
    ) !void {
        _ = self;

        const response_header = protocol.Header{
            .message_type = .hello_ack,
            .body_len = 0,
        };

        const response_bytes = try response_header.encode();
        try writer.writeAll(&response_bytes);
    }

    fn handleStartStream(
        self: *Session,
        writer: *std.Io.Writer,
        request_obj: request.Request,
    ) !void {
        const start_stream = request_obj.message.start_stream;
        if (start_stream.requested_start_frame != 0) {
            return error.SeekNotImplemented;
        }

        const path = try self.allocator.dupeSentinel(
            u8,
            start_stream.media_path,
            0,
        );
        defer self.allocator.free(path);

        var audio_decoder = try decoder.AudioDecoder.open(
            self.allocator,
            path,
            .{},
        );
        errdefer audio_decoder.deinit();

        const track = audio_decoder.trackInfo();
        const format: protocol.SampleFormat = switch (track.output_sample_format) {
            .s16 => .pcm_s16le,
            .s32 => .pcm_s32le,
        };
        const channels = std.math.cast(u16, track.channels) orelse
            return error.TooManyChannels;

        const stream_info = protocol.StreamInfo{
            .format = format,
            .sample_rate = track.sample_rate,
            .channels = channels,
            .channel_layout = 0,
            .total_frames = track.duration_frames orelse 0,
            .actual_start_frame = 0,
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
            .stream_id = request_obj.stream_id,
            .generation_id = request_obj.generation_id,
            .next_frame_offset = 0,
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
        request_obj: request.Request,
    ) !void {
        const active = if (self.active_stream) |*active|
            active
        else
            return;

        if (request_obj.stream_id != active.stream_id or request_obj.generation_id != active.generation_id) {
            return;
        }

        active.deinit(self.allocator);
        self.active_stream = null;
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
        active.eof_reached = read_result.end_of_stream;
        self.next_server_sequence += 1;

        return frame_count;
    }
};

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
