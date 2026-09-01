const backend = @import("macos/decoder.zig");
const types = @import("types.zig");

/// The macOS implementation uses AudioToolbox.
pub const AudioDecoder = backend.AudioDecoder;

pub const Options = types.Options;
pub const SampleFormat = types.SampleFormat;
pub const TrackInfo = types.TrackInfo;
pub const ReadResult = types.ReadResult;
pub const PcmLayout = types.PcmLayout;
pub const DecoderError = types.DecoderError;
