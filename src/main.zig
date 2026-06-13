const std = @import("std");
const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
});

pub fn main() !void {
    // This represents the opened media container.
    // For a .flac file, this is the FLAC container/demuxer context.
    var avformat_context: [*c]c.AVFormatContext = null;

    // Open the input file and let FFmpeg detect the format.
    if (c.avformat_open_input(&avformat_context, "/Users/johnngugi/Music/Library/Dominik Hauser - Chevaliers de Sangreal (From _The Da Vinci Code_) [feat. Hans Zimmer].flac", null, null) != 0) {
        return error.CouldNotOpenInput;
    }
    defer c.avformat_close_input(&avformat_context);

    // Read enough header/stream metadata to discover streams, codecs,
    // duration, sample rate, channel layout, etc.
    if (c.avformat_find_stream_info(avformat_context, null) < 0) {
        return error.CouldNotFindStreamInfo;
    }

    // Find the first audio stream in the file.
    // Some media files can contain multiple streams: audio, video, subtitles, etc.
    var audio_stream_index: isize = -1;
    var i: usize = 0;
    while (i < avformat_context.*.nb_streams) : (i += 1) {
        const stream = avformat_context.*.streams[i];

        if (stream.*.codecpar.*.codec_type == c.AVMEDIA_TYPE_AUDIO) {
            audio_stream_index = @intCast(i);
            break;
        }
    }

    if (audio_stream_index < 0) {
        return error.NoAudioStream;
    }

    // Get the selected audio stream and its codec parameters.
    // codecpar describes the encoded stream: codec id, sample rate,
    // channel layout, sample format hints, etc.
    const audio_stream = avformat_context.*.streams[@intCast(audio_stream_index)];
    const codecpar = audio_stream.*.codecpar;

    // Ask FFmpeg for a decoder that can decode this stream's codec.
    // For a FLAC file, this should usually find the FLAC decoder.
    const decoder = c.avcodec_find_decoder(codecpar.*.codec_id);
    if (decoder == null) {
        return error.DecoderNotFound;
    }

    // Allocate a decoder context.
    // This holds decoder state while packets are being turned into PCM frames.
    var codec_ctx = c.avcodec_alloc_context3(decoder);
    if (codec_ctx == null) {
        return error.CouldNotAllocateCodecContext;
    }
    defer c.avcodec_free_context(&codec_ctx);

    // Copy stream codec parameters into the decoder context.
    if (c.avcodec_parameters_to_context(codec_ctx, codecpar) < 0) {
        return error.CouldNotCopyCodecParams;
    }

    // Give the decoder the stream time base.
    // Mostly useful if you care about timestamps later.
    codec_ctx.*.pkt_timebase = audio_stream.*.time_base;

    // Open/initialize the decoder.
    if (c.avcodec_open2(codec_ctx, decoder, null) < 0) {
        return error.CouldNotOpenDecoder;
    }

    // AVPacket holds encoded/compressed data read from the file.
    // For FLAC, packets contain compressed FLAC frames.
    var packet = c.av_packet_alloc();
    if (packet == null) return error.CouldNotAllocatePacket;
    defer c.av_packet_free(&packet);

    // AVFrame holds decoded audio.
    // After decoding, this is where PCM sample data appears.
    var frame = c.av_frame_alloc();
    if (frame == null) return error.CouldNotAllocateFrame;
    defer c.av_frame_free(&frame);

    // Read compressed packets from the container until EOF.
    while (c.av_read_frame(avformat_context, packet) >= 0) {
        // Release packet internals at the end of each loop iteration.
        defer c.av_packet_unref(packet);

        // ignore non audio streams
        if (packet.*.stream_index == audio_stream_index) {
            try decodePacket(codec_ctx, packet, frame);
        }
    }

    // Flush the decoder after EOF.
    try decodePacket(codec_ctx, null, frame);
}

fn decodePacket(
    codec_ctx: [*c]c.AVCodecContext,
    packet: [*c]const c.AVPacket,
    frame: [*c]c.AVFrame,
) !void {
    // Push one compressed packet into the decoder.
    // During flush, packet is null.
    var ret = c.avcodec_send_packet(codec_ctx, packet);
    if (ret < 0) return error.SendPacketFailed;

    while (true) {
        // Pull decoded frames out of the decoder.
        // One packet can produce zero, one, or multiple frames.
        ret = c.avcodec_receive_frame(codec_ctx, frame);

        // EAGAIN means the decoder needs another packet before it can output more.
        // AVERROR_EOF means flushing is complete.
        if (ret == c.AVERROR(c.EAGAIN) or ret == c.AVERROR_EOF) {
            return;
        }

        if (ret < 0) {
            return error.ReceiveFrameFailed;
        }

        // At this point, frame contains decoded PCM audio samples.
        try readPcmBytes(codec_ctx, frame);

        // Clear frame contents so FFmpeg can reuse the frame for the next decode.
        c.av_frame_unref(frame);
    }
}

fn readPcmBytes(codec_ctx: [*c]c.AVCodecContext, frame: [*c]c.AVFrame) !void {
    // The decoder tells us what sample format it produced.
    // Examples: s16, s16p, flt, fltp, s32, etc.
    const sample_fmt = codec_ctx.*.sample_fmt;

    // Number of bytes used by one sample for one channel.
    // For s16 this is 2 bytes. For f32/flt this is 4 bytes.
    const bytes_per_sample = c.av_get_bytes_per_sample(sample_fmt);
    if (bytes_per_sample <= 0) {
        return;
    }

    const channels: usize = @intCast(codec_ctx.*.ch_layout.nb_channels);
    const samples: usize = @intCast(frame.*.nb_samples);
    const bps: usize = @intCast(bytes_per_sample);

    // FFmpeg can output either planar or packed/interleaved audio.
    //
    // Packed/interleaved stereo:
    //   L R L R L R ...
    //
    // Planar stereo:
    //   plane 0: L L L L ...
    //   plane 1: R R R R ...
    const planar = c.av_sample_fmt_is_planar(sample_fmt) != 0;

    if (planar) {
        // In planar audio, each channel has its own buffer.
        var ch: usize = 0;
        while (ch < channels) : (ch += 1) {
            const ptr: [*]const u8 = @ptrCast(frame.*.extended_data[ch]);

            // One channel contains nb_samples samples.
            const pcm_bytes = ptr[0 .. samples * bps];

            std.debug.print("channel {d}: {d} PCM bytes\n", .{
                ch,
                pcm_bytes.len,
            });

            // This is where you would copy, inspect, write, or process
            // this channel's PCM bytes.
        }
    } else {
        // In packed/interleaved audio, all channels are in one buffer.
        const ptr: [*]const u8 = @ptrCast(frame.*.extended_data[0]);

        // Total bytes = samples per channel * channel count * bytes per sample.
        const pcm_bytes = ptr[0 .. samples * channels * bps];

        std.debug.print("interleaved PCM: {d} bytes\n", .{pcm_bytes.len});

        // This is where you would copy, inspect, write, or process
        // the interleaved PCM bytes.
    }
}
