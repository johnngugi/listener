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
}

var output_unit: AudioUnit = null;

fn open(output_format: backend.OutputFormat) !void {
    if (output_unit != null) return error.AlreadyOpen;

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
        .inputProc = &renderSilence,
        .inputProcRefCon = null,
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

fn makeStreamFormat(
    output_format: backend.OutputFormat,
) !c.AudioStreamBasicDescription {
    const sample_bytes: c.UInt32 = switch (output_format.sample_format) {
        .pcm_s16le => 2,
        else => return error.UnsupportedSampleFormat,
    };
    if (output_format.sample_rate == 0) return error.InvalidSampleRate;

    const channels: c.UInt32 = output_format.channels;
    if (channels == 0) return error.InvalidChannelCount;

    const bytes_per_frame = sample_bytes * channels;
    return .{
        .mSampleRate = @floatFromInt(output_format.sample_rate),
        .mFormatID = c.kAudioFormatLinearPCM,
        .mFormatFlags = c.kAudioFormatFlagIsSignedInteger |
            c.kAudioFormatFlagIsPacked |
            c.kAudioFormatFlagsNativeEndian,
        .mBytesPerPacket = bytes_per_frame,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = bytes_per_frame,
        .mChannelsPerFrame = channels,
        .mBitsPerChannel = sample_bytes * 8,
        .mReserved = 0,
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

test "open compiles without opening the device by default" {
    if (getenv("LISTENER_TEST_COREAUDIO_OPEN") != null) {
        try open(.{
            .sample_format = .pcm_s16le,
            .sample_rate = 48_000,
            .channels = 2,
        });
    }
}
