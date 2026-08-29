const std = @import("std");
const backend = @import("audio_backend");
const stdout = @import("stdout");

const c = @cImport({
    @cInclude("CoreAudioTypes/CoreAudioBaseTypes.h");
});

pub const Backend = backend.OutputBackendBootstrap{
    .name = "CoreAudio",
    .init = &create,
};

const AudioComponent = ?*anyopaque;
const AudioUnit = ?*anyopaque;
const AudioUnitPropertyID = c.UInt32;
const AudioUnitScope = c.UInt32;
const AudioUnitElement = c.UInt32;
const AudioUnitRenderActionFlags = c.UInt32;
const AudioObjectID = c.UInt32;
const AudioDeviceID = AudioObjectID;
const AudioObjectPropertySelector = c.UInt32;
const AudioObjectPropertyScope = c.UInt32;
const AudioObjectPropertyElement = c.UInt32;
const CFIndex = c_long;
const CFStringEncoding = c.UInt32;
const CFStringRef = ?*const anyopaque;

const AudioObjectPropertyAddress = extern struct {
    mSelector: AudioObjectPropertySelector,
    mScope: AudioObjectPropertyScope,
    mElement: AudioObjectPropertyElement,
};

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

extern fn AudioObjectGetPropertyDataSize(
    in_object_id: AudioObjectID,
    in_address: *const AudioObjectPropertyAddress,
    in_qualifier_data_size: c.UInt32,
    in_qualifier_data: ?*const anyopaque,
    out_data_size: *c.UInt32,
) callconv(.c) c.OSStatus;

extern fn AudioObjectGetPropertyData(
    in_object_id: AudioObjectID,
    in_address: *const AudioObjectPropertyAddress,
    in_qualifier_data_size: c.UInt32,
    in_qualifier_data: ?*const anyopaque,
    io_data_size: *c.UInt32,
    out_data: *anyopaque,
) callconv(.c) c.OSStatus;

extern fn AudioObjectIsPropertySettable(
    in_object_id: AudioObjectID,
    in_address: *const AudioObjectPropertyAddress,
    out_is_settable: *u8,
) callconv(.c) c.OSStatus;

extern fn AudioObjectSetPropertyData(
    in_object_id: AudioObjectID,
    in_address: *const AudioObjectPropertyAddress,
    in_qualifier_data_size: c.UInt32,
    in_qualifier_data: ?*const anyopaque,
    in_data_size: c.UInt32,
    in_data: *const anyopaque,
) callconv(.c) c.OSStatus;

extern fn CFRelease(cf: *const anyopaque) callconv(.c) void;
extern fn CFStringGetLength(string: *const anyopaque) callconv(.c) CFIndex;
extern fn CFStringGetMaximumSizeForEncoding(
    length: CFIndex,
    encoding: CFStringEncoding,
) callconv(.c) CFIndex;
extern fn CFStringGetCString(
    string: *const anyopaque,
    buffer: [*]u8,
    buffer_size: CFIndex,
    encoding: CFStringEncoding,
) callconv(.c) u8;
extern fn CFStringCreateWithBytes(
    allocator: ?*const anyopaque,
    bytes: [*]const u8,
    byte_count: CFIndex,
    encoding: CFStringEncoding,
    is_external_representation: u8,
) callconv(.c) CFStringRef;

const kAudioUnitType_Output = fourCC("auou");
const kAudioUnitSubType_HALOutput = fourCC("ahal");
const kAudioUnitManufacturer_Apple = fourCC("appl");
const kAudioUnitProperty_StreamFormat: AudioUnitPropertyID = 8;
const kAudioUnitProperty_SetRenderCallback: AudioUnitPropertyID = 23;
const kAudioUnitScope_Input: AudioUnitScope = 1;
const kAudioUnitScope_Global: AudioUnitScope = 0;
const kAudioOutputUnitProperty_CurrentDevice: AudioUnitPropertyID = 2000;
const kAudioObjectUnknown: AudioObjectID = 0;
const kAudioObjectSystemObject: AudioObjectID = 1;
const kAudioObjectPropertyScopeGlobal = fourCC("glob");
const kAudioObjectPropertyScopeOutput = fourCC("outp");
const kAudioObjectPropertyElementMain: AudioObjectPropertyElement = 0;
const kAudioObjectPropertyName = fourCC("lnam");
const kAudioHardwarePropertyDevices = fourCC("dev#");
const kAudioHardwarePropertyDefaultOutputDevice = fourCC("dOut");
const kAudioHardwarePropertyTranslateUIDToDevice = fourCC("uidd");
const kAudioDevicePropertyDeviceUID = fourCC("uid ");
const kAudioDevicePropertyStreamConfiguration = fourCC("slay");
const kAudioDevicePropertyHogMode = fourCC("oink");
const kCFStringEncodingUTF8: CFStringEncoding = 0x08000100;

extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;
extern fn getpid() callconv(.c) c_int;

const State = struct {
    allocator: std.mem.Allocator,
    output_unit: AudioUnit = null,
    output_started: bool = false,
    source: ?backend.OutputSource = null,
    selected_device_id: ?[]u8 = null,
    configuration: backend.OutputConfiguration = .{},
    exclusive_device_id: AudioDeviceID = kAudioObjectUnknown,
};

const vtable = backend.VTable{
    .enumerate_devices = &enumerateDevices,
    .select_device = &selectDevice,
    .configure = &configure,
    .open = &open,
    .start = &start,
    .stop = &stop,
    .pause_playback = &pausePlayback,
    .resume_playback = &resumePlayback,
    .close = &close,
    .deinit = &deinit,
};

fn create(allocator: std.mem.Allocator) !backend.OutputBackend {
    const state = try allocator.create(State);
    state.* = .{ .allocator = allocator };
    return .{
        .name = Backend.name,
        .context = state,
        .vtable = &vtable,
    };
}

fn enumerateDevices(_: *anyopaque, allocator: std.mem.Allocator) ![]backend.OutputDevice {
    const default_device = try defaultOutputDevice();
    const audio_devices = try allAudioDevices(allocator);
    defer allocator.free(audio_devices);

    var devices: std.ArrayList(backend.OutputDevice) = .empty;
    errdefer {
        for (devices.items) |device| device.deinit(allocator);
        devices.deinit(allocator);
    }

    for (audio_devices) |device_id| {
        if (!try hasOutputChannels(allocator, device_id)) continue;

        const id = try audioObjectString(
            allocator,
            device_id,
            kAudioDevicePropertyDeviceUID,
        );
        errdefer allocator.free(id);
        const name = try audioObjectString(
            allocator,
            device_id,
            kAudioObjectPropertyName,
        );
        errdefer allocator.free(name);

        try devices.append(allocator, .{
            .id = id,
            .name = name,
            .is_default = device_id == default_device,
            .capabilities = .{
                .exclusive_mode = supportsExclusiveMode(device_id),
            },
        });
    }

    return try devices.toOwnedSlice(allocator);
}

fn configure(
    context: *anyopaque,
    configuration: backend.OutputConfiguration,
) !void {
    const state = stateFromContext(context);
    if (state.output_unit != null) return error.AlreadyOpen;

    if (configuration.exclusive_mode) {
        const device_id = try selectedAudioDevice(state);
        if (!supportsExclusiveMode(device_id)) {
            return error.UnsupportedOutputConfiguration;
        }
    }
    state.configuration = configuration;
}

fn selectedAudioDevice(state: *const State) !AudioDeviceID {
    const device_id = if (state.selected_device_id) |selected_id|
        try audioDeviceForUid(selected_id)
    else
        try defaultOutputDevice();
    if (device_id == kAudioObjectUnknown) return error.OutputDeviceNotFound;
    return device_id;
}

fn supportsExclusiveMode(device_id: AudioDeviceID) bool {
    const address = exclusiveModeAddress();
    var is_settable: u8 = 0;
    const status = AudioObjectIsPropertySettable(
        device_id,
        &address,
        &is_settable,
    );
    return status == c.noErr and is_settable != 0;
}

fn exclusiveModeAddress() AudioObjectPropertyAddress {
    return .{
        .mSelector = kAudioDevicePropertyHogMode,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
}

fn acquireExclusiveAccess(device_id: AudioDeviceID) !void {
    const address = exclusiveModeAddress();
    const process_id = getpid();
    var owner: c_int = -1;
    var data_size: c.UInt32 = @sizeOf(c_int);
    try checkStatus(AudioObjectGetPropertyData(
        device_id,
        &address,
        0,
        null,
        &data_size,
        &owner,
    ));

    if (owner == process_id) return;
    if (owner != -1) return error.OutputDeviceInUse;

    // CoreAudio ignores the value and toggles ownership for the caller. It
    // writes the resulting owner back through the same pointer.
    owner = process_id;
    try checkStatus(AudioObjectSetPropertyData(
        device_id,
        &address,
        0,
        null,
        @sizeOf(c_int),
        &owner,
    ));
    owner = -1;
    data_size = @sizeOf(c_int);
    try checkStatus(AudioObjectGetPropertyData(
        device_id,
        &address,
        0,
        null,
        &data_size,
        &owner,
    ));
    if (owner != process_id) return error.OutputDeviceInUse;
}

fn releaseExclusiveAccess(device_id: AudioDeviceID) void {
    if (device_id == kAudioObjectUnknown) return;

    const address = exclusiveModeAddress();
    const process_id = getpid();
    var owner: c_int = -1;
    var data_size: c.UInt32 = @sizeOf(c_int);
    if (AudioObjectGetPropertyData(
        device_id,
        &address,
        0,
        null,
        &data_size,
        &owner,
    ) != c.noErr or owner != process_id) return;

    _ = AudioObjectSetPropertyData(
        device_id,
        &address,
        0,
        null,
        @sizeOf(c_int),
        &owner,
    );
}

fn selectDevice(context: *anyopaque, device_id: ?[]const u8) !void {
    const state = stateFromContext(context);
    if (state.output_unit != null) return error.AlreadyOpen;

    const selected = if (device_id) |id| selected: {
        if (id.len == 0) return error.InvalidOutputDeviceId;
        const audio_device = try audioDeviceForUid(id);
        if (audio_device == kAudioObjectUnknown) return error.OutputDeviceNotFound;
        if (!try hasOutputChannels(state.allocator, audio_device)) {
            return error.NotAnOutputDevice;
        }
        break :selected try state.allocator.dupe(u8, id);
    } else null;

    if (state.selected_device_id) |previous| state.allocator.free(previous);
    state.selected_device_id = selected;
}

fn audioDeviceForUid(device_uid: []const u8) !AudioDeviceID {
    const uid_string = CFStringCreateWithBytes(
        null,
        device_uid.ptr,
        @intCast(device_uid.len),
        kCFStringEncodingUTF8,
        0,
    ) orelse return error.InvalidOutputDeviceId;
    defer CFRelease(uid_string);

    const address = AudioObjectPropertyAddress{
        .mSelector = kAudioHardwarePropertyTranslateUIDToDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    const qualifier: CFStringRef = uid_string;
    var device_id: AudioDeviceID = kAudioObjectUnknown;
    var data_size: c.UInt32 = @sizeOf(AudioDeviceID);
    try checkStatus(AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        @sizeOf(CFStringRef),
        @ptrCast(&qualifier),
        &data_size,
        &device_id,
    ));
    return device_id;
}

fn defaultOutputDevice() !AudioDeviceID {
    const address = AudioObjectPropertyAddress{
        .mSelector = kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    var device_id: AudioDeviceID = kAudioObjectUnknown;
    var data_size: c.UInt32 = @sizeOf(AudioDeviceID);
    try checkStatus(AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        null,
        &data_size,
        &device_id,
    ));
    return device_id;
}

fn allAudioDevices(allocator: std.mem.Allocator) ![]AudioDeviceID {
    const address = AudioObjectPropertyAddress{
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    var data_size: c.UInt32 = 0;
    try checkStatus(AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &address,
        0,
        null,
        &data_size,
    ));

    if (data_size % @sizeOf(AudioDeviceID) != 0) {
        return error.InvalidAudioDeviceList;
    }
    const devices = try allocator.alloc(
        AudioDeviceID,
        data_size / @sizeOf(AudioDeviceID),
    );
    errdefer allocator.free(devices);
    try checkStatus(AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        null,
        &data_size,
        devices.ptr,
    ));
    return devices;
}

fn hasOutputChannels(
    allocator: std.mem.Allocator,
    device_id: AudioDeviceID,
) !bool {
    const address = AudioObjectPropertyAddress{
        .mSelector = kAudioDevicePropertyStreamConfiguration,
        .mScope = kAudioObjectPropertyScopeOutput,
        .mElement = kAudioObjectPropertyElementMain,
    };
    var data_size: c.UInt32 = 0;
    try checkStatus(AudioObjectGetPropertyDataSize(
        device_id,
        &address,
        0,
        null,
        &data_size,
    ));
    if (data_size < @sizeOf(c.AudioBufferList)) return false;

    const storage = try allocator.alignedAlloc(
        u8,
        .of(c.AudioBufferList),
        data_size,
    );
    defer allocator.free(storage);
    try checkStatus(AudioObjectGetPropertyData(
        device_id,
        &address,
        0,
        null,
        &data_size,
        storage.ptr,
    ));

    const buffer_list: *const c.AudioBufferList = @ptrCast(storage.ptr);
    const buffers = @as(
        [*]const c.AudioBuffer,
        @ptrCast(&buffer_list.mBuffers),
    )[0..buffer_list.mNumberBuffers];
    for (buffers) |buffer| {
        if (buffer.mNumberChannels > 0) return true;
    }
    return false;
}

fn audioObjectString(
    allocator: std.mem.Allocator,
    object_id: AudioObjectID,
    selector: AudioObjectPropertySelector,
) ![]u8 {
    const address = AudioObjectPropertyAddress{
        .mSelector = selector,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    var value: CFStringRef = null;
    var data_size: c.UInt32 = @sizeOf(CFStringRef);
    try checkStatus(AudioObjectGetPropertyData(
        object_id,
        &address,
        0,
        null,
        &data_size,
        @ptrCast(&value),
    ));
    const string = value orelse return error.MissingAudioDeviceString;
    defer CFRelease(string);

    const max_bytes = CFStringGetMaximumSizeForEncoding(
        CFStringGetLength(string),
        kCFStringEncodingUTF8,
    );
    if (max_bytes < 0) return error.InvalidAudioDeviceString;
    const buffer = try allocator.alloc(u8, @as(usize, @intCast(max_bytes)) + 1);
    defer allocator.free(buffer);
    if (CFStringGetCString(
        string,
        buffer.ptr,
        @intCast(buffer.len),
        kCFStringEncodingUTF8,
    ) == 0) {
        return error.InvalidAudioDeviceString;
    }

    const length = std.mem.indexOfScalar(u8, buffer, 0) orelse
        return error.InvalidAudioDeviceString;
    return try allocator.dupe(u8, buffer[0..length]);
}

fn open(
    context: *anyopaque,
    output_format: backend.OutputFormat,
    output_source: backend.OutputSource,
) !void {
    const state = stateFromContext(context);
    if (state.output_unit != null) return error.AlreadyOpen;
    const device_id = try selectedAudioDevice(state);
    if (!try hasOutputChannels(state.allocator, device_id)) {
        return error.NotAnOutputDevice;
    }

    var acquired_exclusive_access = false;
    if (state.configuration.exclusive_mode) {
        if (!supportsExclusiveMode(device_id)) {
            return error.UnsupportedOutputConfiguration;
        }
        try acquireExclusiveAccess(device_id);
        state.exclusive_device_id = device_id;
        acquired_exclusive_access = true;
    }
    errdefer if (acquired_exclusive_access) {
        releaseExclusiveAccess(state.exclusive_device_id);
        state.exclusive_device_id = kAudioObjectUnknown;
    };
    state.source = output_source;
    errdefer state.source = null;

    var stream_format = try makeStreamFormat(output_format);

    var description = AudioComponentDescription{
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput,
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
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &device_id,
        @sizeOf(AudioDeviceID),
    ));

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
        .inputProcRefCon = state,
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
    state.output_unit = unit;
    state.output_started = false;
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
    const state: *State = @ptrCast(@alignCast(in_ref_con orelse return c.noErr));
    const source = state.source orelse return c.noErr;

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

fn start(context: *anyopaque) !void {
    try startOutputUnit(stateFromContext(context));
}

fn stop(context: *anyopaque) !void {
    try stopOutputUnit(stateFromContext(context));
}

fn pausePlayback(context: *anyopaque) !void {
    try stopOutputUnit(stateFromContext(context));
}

fn resumePlayback(context: *anyopaque) !void {
    try startOutputUnit(stateFromContext(context));
}

fn close(context: *anyopaque) void {
    const state = stateFromContext(context);
    const opened_unit = state.output_unit orelse {
        state.source = null;
        return;
    };

    stopOutputUnit(state) catch {};
    _ = AudioUnitUninitialize(opened_unit);
    _ = AudioComponentInstanceDispose(opened_unit);
    state.output_unit = null;
    state.output_started = false;
    state.source = null;
    releaseExclusiveAccess(state.exclusive_device_id);
    state.exclusive_device_id = kAudioObjectUnknown;
}

fn deinit(context: *anyopaque) void {
    const state = stateFromContext(context);
    const allocator = state.allocator;
    close(context);
    if (state.selected_device_id) |selected| allocator.free(selected);
    allocator.destroy(state);
}

fn startOutputUnit(state: *State) !void {
    if (state.output_started) return;
    const opened_unit = state.output_unit orelse return error.NotOpen;
    try checkStatus(AudioOutputUnitStart(opened_unit));
    state.output_started = true;
}

fn stopOutputUnit(state: *State) !void {
    if (!state.output_started) return;
    const opened_unit = state.output_unit orelse return;
    try checkStatus(AudioOutputUnitStop(opened_unit));
    state.output_started = false;
}

fn stateFromContext(context: *anyopaque) *State {
    return @ptrCast(@alignCast(context));
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
    stdout.printGlobal("CoreAudio call failed with OSStatus {d}\n", .{status});
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
    var state = State{
        .allocator = std.testing.allocator,
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
    var state = State{ .allocator = std.testing.allocator };
    try std.testing.expectError(error.NotOpen, startOutputUnit(&state));
}

test "open compiles without opening the device by default" {
    if (getenv("LISTENER_TEST_COREAUDIO_OPEN") != null) {
        var output = try create(std.testing.allocator);
        defer output.deinit();

        const FakeSource = struct {
            fn readAvailable(_: *anyopaque, _: usize, output_buffer: []u8) []u8 {
                return output_buffer[0..0];
            }
        };
        var fake_context: u8 = 0;
        try output.open(
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
