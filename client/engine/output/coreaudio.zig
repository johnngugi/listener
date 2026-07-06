const std = @import("std");
const backend = @import("audio_backend");

const c = @cImport({
    @cInclude("CoreAudioTypes/CoreAudioBaseTypes.h");
});

const AudioComponent = ?*anyopaque;
const AudioUnit = ?*anyopaque;
const AudioUnitPropertyID = c.UInt32;
const AudioUnitScope = c.UInt32;
const AudioUnitElement = c.UInt32;
const AudioUnitRenderActionFlags = c.UInt32;

const AudioComponentDescription = extern struct {
    componentType: c.OSType,
    componentSubType: c.OSType,
    componentManufacturer: c.OSType,
    componentFlags: c.UInt32,
    componentFlagsMask: c.UInt32,
};

const AURenderCallback = *const fn (
    in_ref_con: ?*anyopaque,
    io_action_flags: [*c]AudioUnitRenderActionFlags,
    in_time_stamp: [*c]const c.AudioTimeStamp,
    in_bus_number: c.UInt32,
    in_number_frames: c.UInt32,
    io_data: [*c]c.AudioBufferList,
) callconv(.c) c.OSStatus;

const AURenderCallbackStruct = extern struct {
    inputProc: ?AURenderCallback,
    inputProcRefCon: ?*anyopaque,
};

extern fn AudioComponentFindNext(
    in_component: AudioComponent,
    in_desc: *const AudioComponentDescription,
) callconv(.c) AudioComponent;

extern fn AudioComponentInstanceNew(
    in_component: AudioComponent,
    out_instance: *AudioUnit,
) callconv(.c) c.OSStatus;

extern fn AudioComponentInstanceDispose(
    in_instance: AudioUnit,
) callconv(.c) c.OSStatus;

extern fn AudioUnitSetProperty(
    in_unit: AudioUnit,
    in_id: AudioUnitPropertyID,
    in_scope: AudioUnitScope,
    in_element: AudioUnitElement,
    in_data: *const anyopaque,
    in_data_size: c.UInt32,
) callconv(.c) c.OSStatus;

extern fn AudioUnitInitialize(in_unit: AudioUnit) callconv(.c) c.OSStatus;

extern fn AudioUnitUninitialize(in_unit: AudioUnit) callconv(.c) c.OSStatus;

extern fn AudioOutputUnitStart(in_unit: AudioUnit) callconv(.c) c.OSStatus;

extern fn AudioOutputUnitStop(in_unit: AudioUnit) callconv(.c) c.OSStatus;

const kAudioUnitType_Output = fourCC("auou");
const kAudioUnitSubType_DefaultOutput = fourCC("def ");
const kAudioUnitManufacturer_Apple = fourCC("appl");
const kAudioUnitProperty_StreamFormat: AudioUnitPropertyID = 8;
const kAudioUnitProperty_SetRenderCallback: AudioUnitPropertyID = 23;
const kAudioUnitScope_Input: AudioUnitScope = 1;

extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;

pub const Backend = backend.OutputBackendBootstrap{
    .name = "CoreAudio",
    .init = &coreAudioInit,
};

fn coreAudioInit(impl: *backend.OutputImpl) void {
    impl.*.open = &open;
    impl.*.start = &start;
    impl.*.stop = &stop;
    impl.*.close = &close;
}

var output_unit: AudioUnit = null;
var playback_state = PlaybackState{ .source = undefined };

const PlaybackState = struct {
    source: backend.OutputSource,
};

fn open(output_format: backend.OutputFormat, output_source: backend.OutputSource) !void {
    if (output_unit != null) return error.AlreadyOpen;
    playback_state.source = output_source;

    var stream_format = try makeStreamFormat(output_format);

    var description = AudioComponentDescription{
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_DefaultOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0,
    };

    const component = AudioComponentFindNext(null, &description) orelse
        return error.OutputComponentNotFound;

    var unit: AudioUnit = null;
    try checkStatus(AudioComponentInstanceNew(component, &unit));
    errdefer if (unit) |created_unit| {
        _ = AudioComponentInstanceDispose(created_unit);
    };

    try checkStatus(AudioUnitSetProperty(
        unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        0,
        &stream_format,
        @sizeOf(c.AudioStreamBasicDescription),
    ));

    var callback = AURenderCallbackStruct{
        .inputProc = &renderFromSource,
        .inputProcRefCon = &playback_state,
    };

    try checkStatus(AudioUnitSetProperty(
        unit,
        kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input,
        0,
        &callback,
        @sizeOf(AURenderCallbackStruct),
    ));

    try checkStatus(AudioUnitInitialize(unit));
    output_unit = unit;
}

fn renderFromSource(
    in_ref_con: ?*anyopaque,
    _: [*c]AudioUnitRenderActionFlags,
    _: [*c]const c.AudioTimeStamp,
    _: c.UInt32,
    in_number_frames: c.UInt32,
    io_data: [*c]c.AudioBufferList,
) callconv(.c) c.OSStatus {
    if (io_data == null) return c.noErr;
    const state: *PlaybackState = @ptrCast(@alignCast(in_ref_con orelse return c.noErr));
    const source = state.source;

    const buffers = @as(
        [*]c.AudioBuffer,
        @ptrCast(&io_data.*.mBuffers),
    )[0..io_data.*.mNumberBuffers];

    for (buffers) |buffer| {
        const data = buffer.mData orelse continue;
        const data_len: usize = @intCast(buffer.mDataByteSize);
        const data_slice = @as([*]u8, @ptrCast(data))[0..data_len];

        const requested_bytes = @min(
            data_len,
            @as(usize, @intCast(in_number_frames)) * source.frame_bytes,
        );
        const requested_frames = requested_bytes / source.frame_bytes;
        const written = source.readAvailable(
            source.context,
            requested_frames,
            data_slice[0 .. requested_frames * source.frame_bytes],
        );

        @memset(data_slice[written.len..], 0);
    }

    return c.noErr;
}

fn start() !void {
    try startUnit(output_unit);
}

fn stop() !void {
    const opened_unit = output_unit orelse return;
    try checkStatus(AudioOutputUnitStop(opened_unit));
}

fn close() void {
    const opened_unit = output_unit orelse return;

    _ = AudioOutputUnitStop(opened_unit);
    _ = AudioUnitUninitialize(opened_unit);
    _ = AudioComponentInstanceDispose(opened_unit);
    output_unit = null;
}

fn startUnit(unit: AudioUnit) !void {
    const opened_unit = unit orelse return error.NotOpen;
    try checkStatus(AudioOutputUnitStart(opened_unit));
}

fn makeStreamFormat(
    output_format: backend.OutputFormat,
) !c.AudioStreamBasicDescription {
    const sample_bytes: c.UInt32 = @intCast(try backend.sample_format_bytes(output_format.sample_format));
    const valid_bits = try validBitsPerChannel(output_format.sample_format);
    if (output_format.sample_rate == 0) return error.InvalidSampleRate;

    const channels: c.UInt32 = output_format.channels;
    if (channels == 0) return error.InvalidChannelCount;

    const bytes_per_frame = sample_bytes * channels;
    const total_bits = sample_bytes * 8;

    const packing_flag: c.AudioFormatFlags = if (valid_bits == total_bits)
        c.kAudioFormatFlagIsPacked
    else
        c.kAudioFormatFlagIsAlignedHigh;

    const numeric_flag: c.AudioFormatFlags = if (output_format.sample_format == .pcm_f32le)
        c.kAudioFormatFlagIsFloat
    else
        c.kAudioFormatFlagIsSignedInteger;

    return .{
        .mSampleRate = @floatFromInt(output_format.sample_rate),
        .mFormatID = c.kAudioFormatLinearPCM,
        .mFormatFlags = numeric_flag |
            packing_flag |
            c.kAudioFormatFlagsNativeEndian,
        .mBytesPerPacket = bytes_per_frame,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = bytes_per_frame,
        .mChannelsPerFrame = channels,
        .mBitsPerChannel = valid_bits,
        .mReserved = 0,
    };
}

fn validBitsPerChannel(sample_format: anytype) !c.UInt32 {
    return switch (sample_format) {
        .pcm_s16le => 16,
        .pcm_s24le_packed,
        .pcm_s24le_in_s32le,
        => 24,
        .pcm_s32le,
        .pcm_f32le,
        => 32,
    };
}

fn renderSilence(
    _: ?*anyopaque,
    _: [*c]AudioUnitRenderActionFlags,
    _: [*c]const c.AudioTimeStamp,
    _: c.UInt32,
    _: c.UInt32,
    io_data: [*c]c.AudioBufferList,
) callconv(.c) c.OSStatus {
    if (io_data == null) return c.noErr;

    const buffers = @as(
        [*]c.AudioBuffer,
        @ptrCast(&io_data.*.mBuffers),
    )[0..io_data.*.mNumberBuffers];

    for (buffers) |buffer| {
        if (buffer.mData) |data| {
            @memset(@as([*]u8, @ptrCast(data))[0..buffer.mDataByteSize], 0);
        }
    }

    return c.noErr;
}

fn checkStatus(status: c.OSStatus) !void {
    if (status == c.noErr) return;
    std.debug.print("CoreAudio call failed with OSStatus {d}\n", .{status});
    return error.CoreAudioCallFailed;
}

fn fourCC(comptime value: *const [4:0]u8) c.OSType {
    return (@as(c.OSType, value[0]) << 24) |
        (@as(c.OSType, value[1]) << 16) |
        (@as(c.OSType, value[2]) << 8) |
        @as(c.OSType, value[3]);
}

test "makeStreamFormat builds interleaved s16 PCM format" {
    const stream_format = try makeStreamFormat(.{
        .sample_format = .pcm_s16le,
        .sample_rate = 48_000,
        .channels = 2,
    });

    try std.testing.expectEqual(@as(c.Float64, 48_000), stream_format.mSampleRate);
    try std.testing.expectEqual(
        @as(c.AudioFormatID, @bitCast(c.kAudioFormatLinearPCM)),
        stream_format.mFormatID,
    );
    try std.testing.expect(stream_format.mFormatFlags & c.kAudioFormatFlagIsSignedInteger != 0);
    try std.testing.expect(stream_format.mFormatFlags & c.kAudioFormatFlagIsPacked != 0);
    try std.testing.expectEqual(@as(c.UInt32, 4), stream_format.mBytesPerPacket);
    try std.testing.expectEqual(@as(c.UInt32, 1), stream_format.mFramesPerPacket);
    try std.testing.expectEqual(@as(c.UInt32, 4), stream_format.mBytesPerFrame);
    try std.testing.expectEqual(@as(c.UInt32, 2), stream_format.mChannelsPerFrame);
    try std.testing.expectEqual(@as(c.UInt32, 16), stream_format.mBitsPerChannel);
}

test "makeStreamFormat builds high-aligned s24 in s32 PCM format" {
    const stream_format = try makeStreamFormat(.{
        .sample_format = .pcm_s24le_in_s32le,
        .sample_rate = 96_000,
        .channels = 2,
    });

    try std.testing.expect(stream_format.mFormatFlags & c.kAudioFormatFlagIsSignedInteger != 0);
    try std.testing.expect(stream_format.mFormatFlags & c.kAudioFormatFlagIsPacked == 0);
    try std.testing.expect(stream_format.mFormatFlags & c.kAudioFormatFlagIsAlignedHigh != 0);
    try std.testing.expectEqual(@as(c.UInt32, 8), stream_format.mBytesPerPacket);
    try std.testing.expectEqual(@as(c.UInt32, 8), stream_format.mBytesPerFrame);
    try std.testing.expectEqual(@as(c.UInt32, 24), stream_format.mBitsPerChannel);
}

test "renderSilence clears output buffers" {
    var data = [_]u8{0xff} ** 16;
    var buffer_list = c.AudioBufferList{
        .mNumberBuffers = 1,
        .mBuffers = .{.{
            .mNumberChannels = 2,
            .mDataByteSize = data.len,
            .mData = &data,
        }},
    };

    try std.testing.expectEqual(
        c.noErr,
        renderSilence(null, null, null, 0, 0, &buffer_list),
    );

    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &data);
}

test "renderFromSource copies available PCM and zero fills underrun" {
    const FakeSource = struct {
        bytes: []const u8,

        fn readAvailable(context: *anyopaque, _: usize, output_buffer: []u8) []u8 {
            const self: *@This() = @ptrCast(@alignCast(context));
            const copy_len = @min(self.bytes.len, output_buffer.len);
            @memcpy(output_buffer[0..copy_len], self.bytes[0..copy_len]);
            return output_buffer[0..copy_len];
        }
    };

    var fake = FakeSource{ .bytes = &.{ 1, 2, 3, 4 } };
    var state = PlaybackState{
        .source = .{
            .context = &fake,
            .frame_bytes = 4,
            .readAvailable = &FakeSource.readAvailable,
        },
    };

    var data = [_]u8{0xff} ** 8;
    var buffer_list = c.AudioBufferList{
        .mNumberBuffers = 1,
        .mBuffers = .{.{
            .mNumberChannels = 2,
            .mDataByteSize = data.len,
            .mData = &data,
        }},
    };

    try std.testing.expectEqual(
        c.noErr,
        renderFromSource(&state, null, null, 0, 2, &buffer_list),
    );

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 0, 0, 0, 0 }, &data);
}

test "start requires an open output unit" {
    try std.testing.expectError(error.NotOpen, startUnit(null));
}

test "open compiles without opening the device by default" {
    if (getenv("LISTENER_TEST_COREAUDIO_OPEN") != null) {
        const FakeSource = struct {
            fn readAvailable(_: *anyopaque, _: usize, output_buffer: []u8) []u8 {
                return output_buffer[0..0];
            }
        };
        var fake_context: u8 = 0;
        try open(
            .{
                .sample_format = .pcm_s16le,
                .sample_rate = 48_000,
                .channels = 2,
            },
            .{
                .context = &fake_context,
                .frame_bytes = 4,
                .readAvailable = &FakeSource.readAvailable,
            },
        );
    }
}
