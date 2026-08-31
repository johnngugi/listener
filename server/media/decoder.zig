const backend = @import("../decoder.zig");
const types = @import("types.zig");

// Phase 2 keeps FFmpeg as the active backend while media consumers move to
// this platform-neutral facade. Platform selection will live here later.
pub const AudioDecoder = backend.AudioDecoder;

pub const Options = types.Options;
pub const SampleFormat = types.SampleFormat;
pub const TrackInfo = types.TrackInfo;
pub const ReadResult = types.ReadResult;
pub const PcmLayout = types.PcmLayout;
pub const DecoderError = types.DecoderError;
