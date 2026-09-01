const backend_options = @import("media_backend_options");
const backend = switch (backend_options.media_backend) {
    .ffmpeg => @import("../decoder.zig"),
    .native => @import("macos/decoder.zig"),
};
const types = @import("types.zig");

/// The implementation is selected at build time. Native is the macOS default;
/// FFmpeg remains temporarily available as the Phase 6 parity oracle.
pub const AudioDecoder = backend.AudioDecoder;

pub const Options = types.Options;
pub const SampleFormat = types.SampleFormat;
pub const TrackInfo = types.TrackInfo;
pub const ReadResult = types.ReadResult;
pub const PcmLayout = types.PcmLayout;
pub const DecoderError = types.DecoderError;
