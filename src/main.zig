const std = @import("std");
const net = std.Io.net;

const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
});

const decoder = @import("decoder.zig");
const server = @import("server.zig");
const protocol = @import("protocol.zig");
const request = @import("request.zig");

pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.DebugAllocator(.{}){};
    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    const host = "127.0.0.1";
    const port = 5778;

    var s = try server.Server.init(init.io, host, port);
    var net_server = try s.listen();
    defer net_server.deinit(init.io);

    std.debug.print("Listening on {s}:{d} ...\n", .{ host, port });

    while (true) {
        const stream = try net_server.accept(init.io);

        const thread = std.Thread.spawn(.{}, handleClient, .{ init.io, stream, init.gpa }) catch |err| {
            std.debug.print("Failed to spawn thread: {}\n", .{err});
            stream.close(init.io);
            continue;
        };

        thread.detach();
    }
}

fn handleClient(
    io: std.Io,
    stream: net.Stream,
    allocator: std.mem.Allocator,
) !void {
    defer stream.close(io);

    var stream_buffer: [1024]u8 = undefined;
    var stream_reader = stream.reader(io, &stream_buffer);
    const reader = &stream_reader.interface;

    var stream_writer = stream.writer(io, &.{});
    const writer = &stream_writer.interface;

    var body_buffer: [protocol.StartStream.max_wire_len]u8 = undefined;
    var hello_received = false;
    var next_server_sequence: u64 = 1;
    var next_frame_offset: u64 = 0;

    var active_decoder: ?decoder.AudioDecoder = null;
    defer if (active_decoder) |*current| current.deinit();

    while (true) {
        const frame = request.read(reader, &body_buffer) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const request_obj = try request.decodeRequest(frame);

        switch (request_obj.message) {
            .hello => {
                if (hello_received) return error.UnexpectedHello;
                try handleHello(writer);
                hello_received = true;
            },
            .start_stream => {
                if (!hello_received) return error.ExpectedHello;

                // Create the replacement first. If this fails, the existing
                // active decoder remains valid and is cleaned up by defer.
                const new_decoder = try handleStartStream(
                    allocator,
                    writer,
                    request_obj.message.start_stream,
                    request_obj.stream_id,
                    request_obj.generation_id,
                    next_server_sequence,
                );
                next_server_sequence += 1;

                // The new stream was successfully opened, so the previous
                // decoder can now be released.
                if (active_decoder) |*oldDecoder| {
                    oldDecoder.deinit();
                }

                active_decoder = new_decoder;
                next_frame_offset = 0;

                const current = &active_decoder.?;
                const sent = try handleAudioFrame(
                    current,
                    writer,
                    request_obj.stream_id,
                    request_obj.generation_id,
                    next_server_sequence,
                    &next_frame_offset,
                );

                if (sent) {
                    next_server_sequence += 1;
                }
            },
            else => {
                if (!hello_received) return error.ExpectedHello;
                std.debug.print("todo: {}\n", .{request_obj.message});
            },
        }
    }
}

fn handleHello(writer: *std.Io.Writer) !void {
    const response_header = protocol.Header{
        .message_type = protocol.MessageType.hello_ack,
        .body_len = 0,
    };

    const response_bytes = try response_header.encode();
    try writer.writeAll(&response_bytes);
}

fn handleStartStream(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    start_stream_message: protocol.StartStream,
    stream_id: u64,
    generation_id: u64,
    response_sequence: u64,
) !decoder.AudioDecoder {
    if (start_stream_message.requested_start_frame != 0) {
        return error.SeekNotImplemented;
    }

    const path = try allocator.dupeSentinel(u8, start_stream_message.media_path, 0);
    defer allocator.free(path);

    var audio_decoder = try decoder.AudioDecoder.open(allocator, path, .{});
    errdefer audio_decoder.deinit();

    const track = audio_decoder.trackInfo();
    const format: protocol.SampleFormat = switch (track.output_sample_format) {
        .s16 => .pcm_s16le,
        .s32 => .pcm_s32le,
    };

    const channels = std.math.cast(u16, track.channels) orelse return error.TooManyChannels;

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
        .message_type = protocol.MessageType.stream_info,
        .body_len = protocol.StreamInfo.wire_len,
        .stream_id = stream_id,
        .generation_id = generation_id,
        .sequence = response_sequence,
    };
    const header_bytes = try header.encode();

    try writer.writeAll(&header_bytes);
    try writer.writeAll(&body);

    return audio_decoder;
}

fn handleAudioFrame(
    audio_decoder: *decoder.AudioDecoder,
    writer: *std.Io.Writer,
    stream_id: u64,
    generation_id: u64,
    sequence: u64,
    next_frame_offset: *u64,
) !bool {
    var audio_buffer: [protocol.AudioFrame.max_data_len]u8 = undefined;

    // Never split a PCM frame between messages.
    const bytes_per_frame = audio_decoder.trackInfo().bytesPerFrame();
    const usable_len = audio_buffer.len - (audio_buffer.len % bytes_per_frame);

    const read_result = try audio_decoder.read(audio_buffer[0..usable_len]);

    if (read_result.bytes == 0) {
        return false;
    }

    const frame_count = std.math.cast(u32, read_result.frames) orelse
        return error.TooManyFrames;

    const audio_frame = protocol.AudioFrame{
        .frame_offset = next_frame_offset.*,
        .frame_count = frame_count,
        .audio_data = audio_buffer[0..read_result.bytes],
    };

    var body_storage: [protocol.AudioFrame.max_wire_len]u8 = undefined;
    const body = try audio_frame.encode(&body_storage);

    const header = protocol.Header{
        .message_type = protocol.MessageType.audio_frame,
        .body_len = @intCast(body.len),
        .stream_id = stream_id,
        .generation_id = generation_id,
        .sequence = sequence,
    };
    const header_bytes = try header.encode();

    try writer.writeAll(&header_bytes);
    try writer.writeAll(body);

    next_frame_offset.* += frame_count;
    return true;
}
