const std = @import("std");
const protocol = @import("lstn_protocol");

pub const OutputBackend = struct {
    name: []const u8,
    impl: OutputImpl,
};

pub const OutputBackendBootstrap = struct {
    name: []const u8,
    init: *const fn (*OutputImpl) void,
};

pub const OutputImpl = struct {
    open: *const fn (OutputFormat, OutputSource) anyerror!void,
    start: *const fn () anyerror!void,
    stop: *const fn () anyerror!void,
    close: *const fn () void,
};

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
