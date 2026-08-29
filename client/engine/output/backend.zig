const std = @import("std");
const protocol = @import("lstn_protocol");

pub const OutputBackend = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub fn enumerateDevices(
        self: *OutputBackend,
        allocator: std.mem.Allocator,
    ) ![]OutputDevice {
        return self.vtable.enumerate_devices(self.context, allocator);
    }

    pub fn selectDevice(
        self: *OutputBackend,
        device_id: ?[]const u8,
    ) !void {
        try self.vtable.select_device(self.context, device_id);
    }

    pub fn configure(
        self: *OutputBackend,
        configuration: OutputConfiguration,
    ) !void {
        try self.vtable.configure(self.context, configuration);
    }

    pub fn open(
        self: *OutputBackend,
        output_format: OutputFormat,
        output_source: OutputSource,
    ) !void {
        try self.vtable.open(self.context, output_format, output_source);
    }

    pub fn start(self: *OutputBackend) !void {
        try self.vtable.start(self.context);
    }

    pub fn stop(self: *OutputBackend) !void {
        try self.vtable.stop(self.context);
    }

    pub fn pausePlayback(self: *OutputBackend) !void {
        try self.vtable.pause_playback(self.context);
    }

    pub fn resumePlayback(self: *OutputBackend) !void {
        try self.vtable.resume_playback(self.context);
    }

    pub fn close(self: *OutputBackend) void {
        self.vtable.close(self.context);
    }

    pub fn deinit(self: *OutputBackend) void {
        self.vtable.deinit(self.context);
        self.* = undefined;
    }
};

pub const OutputBackendBootstrap = struct {
    name: []const u8,
    init: *const fn (std.mem.Allocator) anyerror!OutputBackend,
};

pub const VTable = struct {
    enumerate_devices: *const fn (*anyopaque, std.mem.Allocator) anyerror![]OutputDevice,
    select_device: *const fn (*anyopaque, ?[]const u8) anyerror!void,
    configure: *const fn (*anyopaque, OutputConfiguration) anyerror!void,
    open: *const fn (*anyopaque, OutputFormat, OutputSource) anyerror!void,
    start: *const fn (*anyopaque) anyerror!void,
    stop: *const fn (*anyopaque) anyerror!void,
    pause_playback: *const fn (*anyopaque) anyerror!void,
    resume_playback: *const fn (*anyopaque) anyerror!void,
    close: *const fn (*anyopaque) void,
    deinit: *const fn (*anyopaque) void,
};

pub const OutputDevice = struct {
    id: []u8,
    name: []u8,
    is_default: bool,
    capabilities: OutputCapabilities,

    pub fn deinit(self: OutputDevice, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
    }
};

pub const OutputCapabilities = struct {
    exclusive_mode: bool = false,
};

pub const OutputConfiguration = struct {
    exclusive_mode: bool = false,
};

pub fn deinitOutputDevices(
    allocator: std.mem.Allocator,
    devices: []OutputDevice,
) void {
    for (devices) |device| device.deinit(allocator);
    allocator.free(devices);
}

pub const OutputFormat = struct {
    sample_format: protocol.SampleFormat,
    sample_rate: u32,
    channels: u16,
};

pub const OutputSource = struct {
    context: *anyopaque,
    frame_bytes: usize,
    readAvailable: *const fn (
        context: *anyopaque,
        max_frames: usize,
        output_buffer: []u8,
    ) []u8,
};

pub fn sample_format_bytes(sample_format: protocol.SampleFormat) !u32 {
    return switch (sample_format) {
        .pcm_s16le => 2,
        .pcm_s24le_packed => 3,
        .pcm_s24le_in_s32le,
        .pcm_s32le,
        .pcm_f32le,
        => 4,
    };
}

test "sample_format_bytes returns protocol sample widths" {
    try std.testing.expectEqual(@as(u32, 2), try sample_format_bytes(.pcm_s16le));
    try std.testing.expectEqual(@as(u32, 3), try sample_format_bytes(.pcm_s24le_packed));
    try std.testing.expectEqual(@as(u32, 4), try sample_format_bytes(.pcm_s24le_in_s32le));
    try std.testing.expectEqual(@as(u32, 4), try sample_format_bytes(.pcm_s32le));
    try std.testing.expectEqual(@as(u32, 4), try sample_format_bytes(.pcm_f32le));
}
