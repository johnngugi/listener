const std = @import("std");
const types = @import("../types.zig");

pub const Options = types.Options;
pub const SampleFormat = types.SampleFormat;
pub const TrackInfo = types.TrackInfo;
pub const ReadResult = types.ReadResult;
pub const PcmLayout = types.PcmLayout;
pub const DecoderError = types.DecoderError;

// These narrow declarations avoid importing the full Xcode framework headers,
// which contain unrelated Objective-C block declarations that Zig's C
// translator cannot currently represent.
const CFIndex = isize;
const CFURL = opaque {};
const CFURLRef = *const CFURL;
const ExtAudioFile = opaque {};
const ExtAudioFileRef = *ExtAudioFile;
const AudioFile = opaque {};
const AudioFileID = *AudioFile;
const FILE = opaque {};
const OSStatus = i32;
const AudioFormatID = u32;
const AudioFormatFlags = u32;
const ExtAudioFilePropertyID = u32;

const AudioStreamBasicDescription = extern struct {
    mSampleRate: f64,
    mFormatID: AudioFormatID,
    mFormatFlags: AudioFormatFlags,
    mBytesPerPacket: u32,
    mFramesPerPacket: u32,
    mBytesPerFrame: u32,
    mChannelsPerFrame: u32,
    mBitsPerChannel: u32,
    mReserved: u32,
};

const AudioBuffer = extern struct {
    mNumberChannels: u32,
    mDataByteSize: u32,
    mData: ?*anyopaque,
};

const AudioBufferList = extern struct {
    mNumberBuffers: u32,
    mBuffers: [1]AudioBuffer,
};

const kAudioFormatLinearPCM: AudioFormatID = 0x6c70636d; // 'lpcm'
const kAudioFormatFlagIsSignedInteger: AudioFormatFlags = 1 << 2;
const kAudioFormatFlagIsPacked: AudioFormatFlags = 1 << 3;
const kExtAudioFileProperty_FileDataFormat: ExtAudioFilePropertyID = 0x66666d74; // 'ffmt'
const kExtAudioFileProperty_ClientDataFormat: ExtAudioFilePropertyID = 0x63666d74; // 'cfmt'
const kExtAudioFileProperty_FileLengthFrames: ExtAudioFilePropertyID = 0x2366726d; // '#frm'
const kExtAudioFileProperty_AudioFile: ExtAudioFilePropertyID = 0x6166696c; // 'afil'
const kAudioFilePropertySourceBitDepth: u32 = 0x73627464; // 'sbtd'

extern var kCFAllocatorDefault: ?*const anyopaque;

extern fn CFURLCreateFromFileSystemRepresentation(
    allocator: ?*const anyopaque,
    buffer: [*]const u8,
    buffer_length: CFIndex,
    is_directory: u8,
) callconv(.c) ?CFURLRef;
extern fn CFRelease(value: *const anyopaque) callconv(.c) void;

extern fn ExtAudioFileOpenURL(url: CFURLRef, out_file: *?ExtAudioFileRef) callconv(.c) OSStatus;
extern fn ExtAudioFileDispose(file: ExtAudioFileRef) callconv(.c) OSStatus;
extern fn ExtAudioFileRead(
    file: ExtAudioFileRef,
    frame_count: *u32,
    data: *AudioBufferList,
) callconv(.c) OSStatus;
extern fn ExtAudioFileSeek(file: ExtAudioFileRef, frame_offset: i64) callconv(.c) OSStatus;
extern fn ExtAudioFileGetProperty(
    file: ExtAudioFileRef,
    property_id: ExtAudioFilePropertyID,
    data_size: *u32,
    data: *anyopaque,
) callconv(.c) OSStatus;
extern fn ExtAudioFileSetProperty(
    file: ExtAudioFileRef,
    property_id: ExtAudioFilePropertyID,
    data_size: u32,
    data: *const anyopaque,
) callconv(.c) OSStatus;
extern fn AudioFileGetProperty(
    file: AudioFileID,
    property_id: u32,
    data_size: *u32,
    data: *anyopaque,
) callconv(.c) OSStatus;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*FILE;
extern fn fread(buffer: *anyopaque, size: usize, count: usize, file: *FILE) callconv(.c) usize;
extern fn fclose(file: *FILE) callconv(.c) c_int;

/// A fixed upper bound keeps read-ahead memory independent of encoded input
/// and large enough to amortize calls into Extended Audio File Services.
const pending_capacity = 64 * 1024;

pub const AudioDecoder = struct {
    ext_audio_file: ?ExtAudioFileRef,
    info: TrackInfo,

    pending: [pending_capacity]u8 = undefined,
    pending_offset: usize = 0,
    pending_len: usize = 0,
    end_of_file: bool = false,

    pub fn open(
        allocator: std.mem.Allocator,
        path: [:0]const u8,
        options: Options,
    ) !AudioDecoder {
        _ = allocator;

        if (std.mem.indexOfScalar(u8, path, 0) != null) return error.CouldNotOpenInput;

        const path_length = std.math.cast(CFIndex, path.len) orelse
            return error.CouldNotOpenInput;
        const url = CFURLCreateFromFileSystemRepresentation(
            kCFAllocatorDefault,
            path.ptr,
            path_length,
            0,
        ) orelse return error.CouldNotOpenInput;
        defer CFRelease(url);

        var optional_file: ?ExtAudioFileRef = null;
        if (ExtAudioFileOpenURL(url, &optional_file) != 0) {
            if (optional_file) |file| _ = ExtAudioFileDispose(file);
            return openEmptyFlac(path, options) orelse error.CouldNotOpenInput;
        }
        const file = optional_file orelse return error.CouldNotOpenInput;
        errdefer _ = ExtAudioFileDispose(file);

        var source_format: AudioStreamBasicDescription = std.mem.zeroes(AudioStreamBasicDescription);
        var source_format_size: u32 = @sizeOf(AudioStreamBasicDescription);
        if (ExtAudioFileGetProperty(
            file,
            kExtAudioFileProperty_FileDataFormat,
            &source_format_size,
            &source_format,
        ) != 0 or source_format_size != @sizeOf(AudioStreamBasicDescription)) {
            return error.CouldNotOpenInput;
        }

        const source = try inspectSourceFormat(source_format, try sourceBitDepth(file));
        const output_format = options.sample_format orelse source.container_format;
        if (output_format != source.container_format) {
            return error.UnsupportedSampleFormatConversion;
        }

        const client_format = makeClientFormat(
            source.sample_rate,
            source.channels,
            output_format,
        );
        if (client_format.mBytesPerFrame == 0 or
            client_format.mBytesPerFrame > pending_capacity)
        {
            return error.UnsupportedSampleFormat;
        }

        if (ExtAudioFileSetProperty(
            file,
            kExtAudioFileProperty_ClientDataFormat,
            @sizeOf(AudioStreamBasicDescription),
            &client_format,
        ) != 0) {
            return error.UnsupportedSampleFormatConversion;
        }

        return .{
            .ext_audio_file = file,
            .info = .{
                .sample_rate = source.sample_rate,
                .channels = source.channels,
                .duration_frames = fileLengthFrames(file),
                .valid_bits_per_sample = source.valid_bits,
                .native_sample_format = source.container_format,
                .output_sample_format = output_format,
                .output_layout = options.layout,
            },
        };
    }

    pub fn deinit(self: *AudioDecoder) void {
        if (self.ext_audio_file) |file| _ = ExtAudioFileDispose(file);
        self.* = undefined;
    }

    pub fn trackInfo(self: *const AudioDecoder) TrackInfo {
        return self.info;
    }

    pub fn read(self: *AudioDecoder, out: []u8) !ReadResult {
        if (out.len == 0) {
            return .{ .frames = 0, .bytes = 0, .end_of_stream = self.endOfStream() };
        }

        var written: usize = 0;
        while (written < out.len) {
            written += self.drainPending(out[written..]);
            if (written == out.len or self.end_of_file) break;
            try self.fillPending();
        }

        // Read one block ahead when the caller ends exactly at a pending-buffer
        // boundary. This lets the final full read report EOF immediately.
        if (written == out.len and self.pending_len == 0 and !self.end_of_file) {
            try self.fillPending();
        }

        return .{
            .frames = written / self.info.bytesPerFrame(),
            .bytes = written,
            .end_of_stream = self.endOfStream(),
        };
    }

    pub fn seekToFrame(self: *AudioDecoder, target_frame: u64) !void {
        if (self.info.duration_frames) |duration| {
            if (target_frame > duration) return error.SeekOutOfRange;
        }
        const signed_target = std.math.cast(i64, target_frame) orelse
            return error.SeekOutOfRange;
        const file = self.ext_audio_file orelse {
            if (target_frame == 0) {
                self.end_of_file = false;
                return;
            }
            return error.SeekOutOfRange;
        };
        if (ExtAudioFileSeek(file, signed_target) != 0) {
            return error.SeekFailed;
        }

        self.pending_offset = 0;
        self.pending_len = 0;
        self.end_of_file = false;
    }

    fn fillPending(self: *AudioDecoder) !void {
        std.debug.assert(self.pending_len == 0);

        const bytes_per_frame = self.info.bytesPerFrame();
        var requested_frames: u32 = @intCast(pending_capacity / bytes_per_frame);
        const byte_capacity: u32 = @intCast(@as(usize, requested_frames) * bytes_per_frame);
        var buffers = AudioBufferList{
            .mNumberBuffers = 1,
            .mBuffers = .{.{
                .mNumberChannels = self.info.channels,
                .mDataByteSize = byte_capacity,
                .mData = @ptrCast(&self.pending),
            }},
        };

        const file = self.ext_audio_file orelse {
            self.end_of_file = true;
            return;
        };
        if (ExtAudioFileRead(file, &requested_frames, &buffers) != 0) {
            return error.ReadFrameFailed;
        }
        if (requested_frames == 0) {
            self.end_of_file = true;
            return;
        }

        const returned_bytes = @as(usize, requested_frames) * bytes_per_frame;
        if (returned_bytes > pending_capacity or buffers.mBuffers[0].mDataByteSize < returned_bytes) {
            return error.InvalidReadSize;
        }
        self.pending_offset = 0;
        self.pending_len = returned_bytes;
    }

    fn drainPending(self: *AudioDecoder, out: []u8) usize {
        const count = @min(out.len, self.pending_len);
        @memcpy(out[0..count], self.pending[self.pending_offset..][0..count]);
        self.pending_offset += count;
        self.pending_len -= count;
        if (self.pending_len == 0) self.pending_offset = 0;
        return count;
    }

    fn endOfStream(self: *const AudioDecoder) bool {
        return self.end_of_file and self.pending_len == 0;
    }
};

const SourceFormat = struct {
    sample_rate: u32,
    channels: u32,
    valid_bits: u16,
    container_format: SampleFormat,
};

fn inspectSourceFormat(format: AudioStreamBasicDescription, source_bits: u16) !SourceFormat {
    if (!std.math.isFinite(format.mSampleRate) or
        format.mSampleRate <= 0 or
        format.mSampleRate > std.math.maxInt(u32) or
        @floor(format.mSampleRate) != format.mSampleRate)
    {
        return error.UnsupportedSampleFormat;
    }
    if (format.mChannelsPerFrame == 0) return error.NoAudioStream;

    const container_format: SampleFormat = switch (source_bits) {
        1...16 => .s16,
        17...32 => .s32,
        else => return error.UnsupportedSampleFormat,
    };

    return .{
        .sample_rate = @intFromFloat(format.mSampleRate),
        .channels = format.mChannelsPerFrame,
        .valid_bits = source_bits,
        .container_format = container_format,
    };
}

fn makeClientFormat(
    sample_rate: u32,
    channels: u32,
    sample_format: SampleFormat,
) AudioStreamBasicDescription {
    const bytes_per_sample: u32 = @intCast(sample_format.bytes());
    return .{
        .mSampleRate = @floatFromInt(sample_rate),
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = channels * bytes_per_sample,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = channels * bytes_per_sample,
        .mChannelsPerFrame = channels,
        .mBitsPerChannel = sample_format.bits(),
        .mReserved = 0,
    };
}

fn fileLengthFrames(file: ExtAudioFileRef) ?u64 {
    var frames: i64 = 0;
    var size: u32 = @sizeOf(i64);
    if (ExtAudioFileGetProperty(
        file,
        kExtAudioFileProperty_FileLengthFrames,
        &size,
        &frames,
    ) != 0 or size != @sizeOf(i64) or frames < 0) {
        return null;
    }
    return @intCast(frames);
}

fn sourceBitDepth(file: ExtAudioFileRef) !u16 {
    var audio_file: ?AudioFileID = null;
    var audio_file_size: u32 = @sizeOf(?AudioFileID);
    if (ExtAudioFileGetProperty(
        file,
        kExtAudioFileProperty_AudioFile,
        &audio_file_size,
        @ptrCast(&audio_file),
    ) != 0 or audio_file_size != @sizeOf(?AudioFileID)) {
        return error.UnsupportedSampleFormat;
    }

    var depth: i32 = 0;
    var depth_size: u32 = @sizeOf(i32);
    if (AudioFileGetProperty(
        audio_file orelse return error.UnsupportedSampleFormat,
        kAudioFilePropertySourceBitDepth,
        &depth_size,
        &depth,
    ) != 0 or depth_size != @sizeOf(i32) or depth <= 0) {
        return error.UnsupportedSampleFormat;
    }
    return std.math.cast(u16, depth) orelse error.UnsupportedSampleFormat;
}

/// AudioToolbox rejects a valid FLAC containing STREAMINFO but no audio
/// frames. Read only the fixed-size marker/header/STREAMINFO prefix so this
/// compatibility case stays bounded and cannot allocate from file lengths.
fn openEmptyFlac(path: [:0]const u8, options: Options) ?AudioDecoder {
    const file = fopen(path.ptr, "rb") orelse return null;
    defer _ = fclose(file);

    var prefix: [42]u8 = undefined;
    if (fread(&prefix, 1, prefix.len, file) != prefix.len) return null;
    if (!std.mem.eql(u8, prefix[0..4], "fLaC")) return null;
    if ((prefix[4] & 0x7f) != 0 or !std.mem.eql(u8, prefix[5..8], "\x00\x00\x22")) return null;

    const packed_value = std.mem.readInt(u64, prefix[18..26], .big);
    const sample_rate: u32 = @intCast((packed_value >> 44) & 0xfffff);
    const channels: u32 = @intCast(((packed_value >> 41) & 0x7) + 1);
    const valid_bits: u16 = @intCast(((packed_value >> 36) & 0x1f) + 1);
    const total_samples = packed_value & 0x0000000fffffffff;
    if (sample_rate == 0 or total_samples != 0) return null;

    const native_format: SampleFormat = switch (valid_bits) {
        1...16 => .s16,
        17...32 => .s32,
        else => return null,
    };
    const output_format = options.sample_format orelse native_format;
    if (output_format != native_format) return null;

    return .{
        .ext_audio_file = null,
        .info = .{
            .sample_rate = sample_rate,
            .channels = channels,
            .duration_frames = 0,
            .valid_bits_per_sample = valid_bits,
            .native_sample_format = native_format,
            .output_sample_format = output_format,
            .output_layout = options.layout,
        },
    };
}
