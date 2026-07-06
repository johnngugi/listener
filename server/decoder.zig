const std = @import("std");

const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavutil/samplefmt.h");
});

pub const AudioDecoder = struct {
    allocator: std.mem.Allocator,

    format_ctx: [*c]c.AVFormatContext,
    codec_ctx: [*c]c.AVCodecContext,
    packet: [*c]c.AVPacket,
    frame: [*c]c.AVFrame,

    // Holds decoded PCM that did not fit in the caller's output buffer.
    pending: std.ArrayListUnmanaged(u8) = .empty,
    pending_offset: usize = 0,

    audio_stream_index: c_int,
    info: TrackInfo,

    input_eof: bool = false,
    flush_sent: bool = false,
    decoder_eof: bool = false,

    pub fn open(allocator: std.mem.Allocator, path: [:0]const u8, options: Options) !AudioDecoder {
        // This represents the opened media container.
        // For a .flac file, this is the FLAC container/demuxer context.
        var avformat_context: [*c]c.AVFormatContext = null;

        const result = c.avformat_open_input(&avformat_context, path, null, null);
        if (result < 0) {
            return error.CouldNotOpenInput;
        }
        errdefer c.avformat_close_input(&avformat_context);

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
        errdefer c.avcodec_free_context(&codec_ctx);

        // Copy stream codec parameters into the decoder context.
        if (c.avcodec_parameters_to_context(codec_ctx, codecpar) < 0) {
            return error.CouldNotCopyCodecParams;
        }

        // Give the decoder the stream time base.
        // Mostly useful if you care about timestamps later.
        codec_ctx.*.pkt_timebase = audio_stream.*.time_base;
        if (options.sample_format) |sample_format| {
            codec_ctx.*.request_sample_fmt = sample_format.toAv();
        }

        // Open/initialize the decoder.
        if (c.avcodec_open2(codec_ctx, decoder, null) < 0) {
            return error.CouldNotOpenDecoder;
        }

        // AVPacket holds encoded/compressed data read from the file.
        // For FLAC, packets contain compressed FLAC frames.
        var packet = c.av_packet_alloc();
        if (packet == null) return error.CouldNotAllocatePacket;
        errdefer c.av_packet_free(&packet);

        // AVFrame holds decoded audio.
        // After decoding, this is where PCM sample data appears.
        var frame = c.av_frame_alloc();
        if (frame == null) return error.CouldNotAllocateFrame;
        errdefer c.av_frame_free(&frame);

        const native_sample_fmt = try SampleFormat.fromAv(codec_ctx.*.sample_fmt);
        const output_sample_fmt = options.sample_format orelse native_sample_fmt;
        if (native_sample_fmt != output_sample_fmt) {
            return error.UnsupportedSampleFormatConversion;
        }

        return .{
            .allocator = allocator,
            .format_ctx = avformat_context,
            .codec_ctx = codec_ctx,
            .packet = packet,
            .frame = frame,
            .audio_stream_index = @intCast(audio_stream_index),
            .info = .{
                .sample_rate = @intCast(codec_ctx.*.sample_rate),
                .channels = @intCast(codec_ctx.*.ch_layout.nb_channels),
                .duration_frames = durationFrames(audio_stream, codec_ctx.*.sample_rate),
                .valid_bits_per_sample = validBitsPerSample(codecpar, output_sample_fmt),
                .native_sample_format = native_sample_fmt,
                .output_sample_format = output_sample_fmt,
                .output_layout = options.layout,
            },
        };
    }

    pub fn deinit(self: *AudioDecoder) void {
        c.av_frame_free(&self.frame);
        c.av_packet_free(&self.packet);
        c.avcodec_free_context(&self.codec_ctx);
        c.avformat_close_input(&self.format_ctx);
        self.pending.deinit(self.allocator);
    }

    pub fn trackInfo(self: *const AudioDecoder) TrackInfo {
        return self.info;
    }

    pub fn read(self: *AudioDecoder, out: []u8) !ReadResult {
        var written: usize = 0;

        while (written < out.len) {
            written += self.drainPending(out[written..]);

            if (written == out.len or self.decoder_eof) break;

            try self.decodeOneFrameIntoPending();
        }

        // If the caller's buffer ended exactly at a decoded-frame boundary,
        // decode one frame ahead. This distinguishes "more PCM is available"
        // from "that was the final PCM" without requiring another read.
        // Any discovered PCM remains pending for the next call.
        if (written == out.len and self.pendingSlice().len == 0 and !self.decoder_eof) {
            try self.decodeOneFrameIntoPending();
        }

        return .{
            .bytes = written,
            .frames = written / self.info.bytesPerFrame(),
            .end_of_stream = self.decoder_eof and self.pendingSlice().len == 0,
        };
    }

    // pub fn seekToFrame(self: *AudioDecoder, frame: u64) !void {}

    fn decodeOneFrameIntoPending(self: *AudioDecoder) !void {
        while (true) {
            // Pull decoded frames out of the decoder.
            // One packet can produce zero, one, or multiple frames.
            const ret = c.avcodec_receive_frame(self.codec_ctx, self.frame);

            if (ret == 0) {
                // Clear frame contents so FFmpeg can reuse the frame for the next decode.
                defer c.av_frame_unref(self.frame);
                try self.appendFrame(self.frame);
                return;
            }

            // AVERROR_EOF means flushing is complete.
            if (ret == c.AVERROR_EOF) {
                self.decoder_eof = true;
                return;
            }

            // EAGAIN means the decoder needs another packet before it can output more.
            if (ret == c.AVERROR(c.EAGAIN)) {
                try self.sendNextPacketOrFlush();
                continue;
            }

            return error.ReceiveFrameFailed;
        }
    }

    fn sendNextPacketOrFlush(self: *AudioDecoder) !void {
        if (self.input_eof) {
            if (self.flush_sent) return;

            // FFMpeg treats avpkt == null as a signal to drain any buffered decoded frames
            const ret = c.avcodec_send_packet(self.codec_ctx, null);
            if (ret == c.AVERROR_EOF) {
                self.decoder_eof = true;
                return;
            }

            if (ret < 0) return error.SendPacketFailed;

            self.flush_sent = true;
            return;
        }

        // Read compressed packets from the container until EOF.
        while (true) {
            const ret = c.av_read_frame(self.format_ctx, self.packet);

            if (ret == c.AVERROR_EOF) {
                self.input_eof = true;
                return try self.sendNextPacketOrFlush();
            }

            if (ret < 0) return error.ReadFrameFailed;

            // ignore non audio streams
            if (self.packet.*.stream_index != self.audio_stream_index) {
                c.av_packet_unref(self.packet);
                continue;
            }

            // Push one compressed packet into the decoder.
            // During flush, packet is null.
            const send_ret = c.avcodec_send_packet(self.codec_ctx, self.packet);
            c.av_packet_unref(self.packet);
            if (send_ret < 0) return error.SendPacketFailed;

            return;
        }
    }

    fn appendFrame(self: *AudioDecoder, frame: [*c]c.struct_AVFrame) !void {
        // The decoder tells us what sample format it produced.
        // Examples: s16, s16p, flt, fltp, s32, etc.
        const sample_fmt = self.codec_ctx.*.sample_fmt;

        // Number of bytes used by one sample for one channel.
        // For s16 this is 2 bytes. For f32/flt this is 4 bytes.
        const bytes_per_sample = c.av_get_bytes_per_sample(sample_fmt);
        if (bytes_per_sample <= 0) {
            return error.UnsupportedSampleFormat;
        }

        const channels: usize = @intCast(self.codec_ctx.*.ch_layout.nb_channels);
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

        if (!planar) {
            // In packed/interleaved audio, all channels are in one buffer.
            const ptr: [*]const u8 = @ptrCast(frame.*.extended_data[0]);

            // Total bytes = samples per channel * channel count * bytes per sample.
            const pcm_bytes = ptr[0 .. samples * channels * bps];

            try self.pending.appendSlice(
                self.allocator,
                pcm_bytes,
            );
            return;
        }

        // Convert planar to interleaved:
        // plane 0: L L L ...
        // plane 1: R R R ...
        // output:  L R L R ...
        const start = self.pending.items.len;
        try self.pending.resize(self.allocator, start + samples * channels * bps);

        var sample: usize = 0;
        var dst = self.pending.items[start..];

        while (sample < samples) : (sample += 1) {
            // In planar audio, each channel has its own buffer.
            var ch: usize = 0;
            while (ch < channels) : (ch += 1) {
                const src: [*]const u8 = @ptrCast(frame.*.extended_data[ch]);
                const src_sample = src[sample * bps ..][0..bps];

                @memcpy(dst[0..bps], src_sample);
                dst = dst[bps..];
            }
        }
    }

    fn drainPending(self: *AudioDecoder, out: []u8) usize {
        const pending = self.pendingSlice();
        const n = @min(out.len, pending.len);

        @memcpy(out[0..n], pending[0..n]);

        self.pending_offset += n;
        if (self.pending_offset == self.pending.items.len) {
            self.pending.clearRetainingCapacity();
            self.pending_offset = 0;
        }

        return n;
    }

    fn pendingSlice(self: *const AudioDecoder) []const u8 {
        return self.pending.items[self.pending_offset..];
    }
};

pub const Options = struct {
    sample_format: ?SampleFormat = null,
    layout: PcmLayout = .interleaved,
};

pub const SampleFormat = enum {
    s16,
    s32,

    fn fromAv(sample_fmt: c.enum_AVSampleFormat) !SampleFormat {
        return switch (sample_fmt) {
            c.AV_SAMPLE_FMT_S16, c.AV_SAMPLE_FMT_S16P => .s16,
            c.AV_SAMPLE_FMT_S32, c.AV_SAMPLE_FMT_S32P => .s32,
            else => error.UnsupportedSampleFormat,
        };
    }

    fn bytes(self: SampleFormat) usize {
        return switch (self) {
            .s16 => 2,
            .s32 => 4,
        };
    }

    fn bits(self: SampleFormat) u16 {
        return @intCast(self.bytes() * 8);
    }

    fn toAv(self: SampleFormat) c.enum_AVSampleFormat {
        return switch (self) {
            .s16 => c.AV_SAMPLE_FMT_S16,
            .s32 => c.AV_SAMPLE_FMT_S32,
        };
    }
};

pub const TrackInfo = struct {
    sample_rate: u32,
    channels: u32,
    duration_frames: ?u64 = null,
    valid_bits_per_sample: u16,

    native_sample_format: SampleFormat,
    output_sample_format: SampleFormat,
    output_layout: PcmLayout,

    pub fn bytesPerFrame(self: TrackInfo) usize {
        return @as(usize, self.channels) * self.output_sample_format.bytes();
    }
};

pub const ReadResult = struct {
    /// Number of audio frames written.
    /// One frame = one sample per channel.
    frames: usize,

    /// Number of bytes written into the caller-provided buffer.
    bytes: usize,

    /// True when no more PCM will be produced after this result.
    end_of_stream: bool = false,
};

pub const PcmLayout = enum {
    /// Samples alternate by channel:
    /// stereo: L R L R L R ...
    interleaved,
};

fn durationFrames(stream: [*c]c.AVStream, sample_rate: c_int) ?u64 {
    if (stream.*.duration == c.AV_NOPTS_VALUE or sample_rate <= 0) return null;

    const duration: i128 = stream.*.duration;
    const num: i128 = stream.*.time_base.num;
    const den: i128 = stream.*.time_base.den;
    const rate: i128 = sample_rate;

    if (duration < 0 or num <= 0 or den <= 0) return null;

    return @intCast(@divTrunc(duration * num * rate, den));
}

fn validBitsPerSample(
    codecpar: [*c]const c.AVCodecParameters,
    sample_format: SampleFormat,
) u16 {
    if (codecpar.*.bits_per_raw_sample > 0) {
        return @intCast(codecpar.*.bits_per_raw_sample);
    }

    return sample_format.bits();
}
