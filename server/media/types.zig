const std = @import("std");

/// Decoder options shared by every platform backend.
pub const Options = struct {
    sample_format: ?SampleFormat = null,
    layout: PcmLayout = .interleaved,
};

/// PCM container format exposed to media consumers.
pub const SampleFormat = enum {
    s16,
    s32,

    pub fn bytes(self: SampleFormat) usize {
        return switch (self) {
            .s16 => 2,
            .s32 => 4,
        };
    }

    pub fn bits(self: SampleFormat) u16 {
        return @intCast(self.bytes() * 8);
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

/// Backend-independent failures that callers may handle explicitly.
/// Backends may additionally return implementation and allocation errors.
pub const DecoderError = error{
    CouldNotOpenInput,
    NoAudioStream,
    DecoderNotFound,
    UnsupportedSampleFormat,
    UnsupportedSampleFormatConversion,
    SeekOutOfRange,
    SeekFailed,
};

test "shared media types describe interleaved PCM without platform headers" {
    const info = TrackInfo{
        .sample_rate = 48_000,
        .channels = 2,
        .duration_frames = 96_000,
        .valid_bits_per_sample = 24,
        .native_sample_format = .s32,
        .output_sample_format = .s32,
        .output_layout = .interleaved,
    };

    try std.testing.expectEqual(@as(usize, 8), info.bytesPerFrame());
    try std.testing.expectEqual(@as(u16, 32), SampleFormat.s32.bits());
}
