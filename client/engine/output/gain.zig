const std = @import("std");
const backend = @import("audio_backend");

const SampleFormat = @FieldType(backend.OutputFormat, "sample_format");
const unity_gain_q32 = std.math.maxInt(u32);

pub const GainStage = struct {
    source: backend.OutputSource,
    sample_format: SampleFormat,
    gain_q32: std.atomic.Value(u32) = .init(unity_gain_q32),

    pub fn init(
        output_format: backend.OutputFormat,
        source: backend.OutputSource,
    ) GainStage {
        return .{
            .source = source,
            .sample_format = output_format.sample_format,
        };
    }

    pub fn outputSource(self: *GainStage) backend.OutputSource {
        return .{
            .context = self,
            .frame_bytes = self.source.frame_bytes,
            .readAvailable = &readAvailable,
        };
    }

    pub fn setGain(self: *GainStage, gain: f64) !void {
        if (!std.math.isFinite(gain) or gain < 0 or gain > 1) {
            return error.InvalidGain;
        }

        const scaled = @round(gain * @as(f64, @floatFromInt(unity_gain_q32)));
        self.gain_q32.store(@intFromFloat(scaled), .release);
    }

    fn readAvailable(
        context: *anyopaque,
        max_frames: usize,
        output_buffer: []u8,
    ) []u8 {
        const self: *GainStage = @ptrCast(@alignCast(context));
        const written = self.source.readAvailable(
            self.source.context,
            max_frames,
            output_buffer,
        );
        const gain = self.gain_q32.load(.acquire);

        if (gain == unity_gain_q32) return written;
        if (gain == 0) {
            @memset(written, 0);
            return written;
        }

        applyGain(self.sample_format, gain, written);
        return written;
    }
};

fn applyGain(
    sample_format: SampleFormat,
    gain: u32,
    bytes: []u8,
) void {
    switch (sample_format) {
        .pcm_s16le => scaleIntegerSamples(i16, bytes, gain),
        .pcm_s24le_packed => scaleIntegerSamples(i24, bytes, gain),
        .pcm_s24le_in_s32le => scale24In32Samples(bytes, gain),
        .pcm_s32le => scaleIntegerSamples(i32, bytes, gain),
        .pcm_f32le => scaleFloatSamples(bytes, gain),
    }
}

fn scaleIntegerSamples(comptime Sample: type, bytes: []u8, gain: u32) void {
    const sample_bytes = @bitSizeOf(Sample) / 8;
    std.debug.assert(bytes.len % sample_bytes == 0);

    var offset: usize = 0;
    while (offset < bytes.len) : (offset += sample_bytes) {
        const sample = std.mem.readInt(
            Sample,
            bytes[offset..][0..sample_bytes],
            .little,
        );
        std.mem.writeInt(
            Sample,
            bytes[offset..][0..sample_bytes],
            @intCast(scaleSigned(sample, gain)),
            .little,
        );
    }
}

fn scale24In32Samples(bytes: []u8, gain: u32) void {
    const sample_bytes = @sizeOf(i32);
    std.debug.assert(bytes.len % sample_bytes == 0);

    var offset: usize = 0;
    while (offset < bytes.len) : (offset += sample_bytes) {
        const container = std.mem.readInt(
            i32,
            bytes[offset..][0..sample_bytes],
            .little,
        );
        const valid_sample = container >> 8;
        const scaled = scaleSigned(valid_sample, gain) * 256;
        std.mem.writeInt(
            i32,
            bytes[offset..][0..sample_bytes],
            @intCast(scaled),
            .little,
        );
    }
}

fn scaleFloatSamples(bytes: []u8, gain: u32) void {
    const sample_bytes = @sizeOf(f32);
    std.debug.assert(bytes.len % sample_bytes == 0);

    const float_gain = @as(f32, @floatFromInt(gain)) /
        @as(f32, @floatFromInt(unity_gain_q32));
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += sample_bytes) {
        const bits = std.mem.readInt(
            u32,
            bytes[offset..][0..sample_bytes],
            .little,
        );
        const sample: f32 = @bitCast(bits);
        std.mem.writeInt(
            u32,
            bytes[offset..][0..sample_bytes],
            @bitCast(sample * float_gain),
            .little,
        );
    }
}

fn scaleSigned(sample: anytype, gain: u32) i64 {
    const product = @as(i64, sample) * @as(i64, gain);
    const half: i64 = @intCast(unity_gain_q32 / 2);
    const rounded = if (product >= 0) product + half else product - half;
    return @divTrunc(rounded, @as(i64, unity_gain_q32));
}

const TestSource = struct {
    bytes: []const u8,
    frame_bytes: usize,

    fn outputSource(self: *TestSource, frame_bytes: usize) backend.OutputSource {
        self.frame_bytes = frame_bytes;
        return .{
            .context = self,
            .frame_bytes = frame_bytes,
            .readAvailable = &readAvailable,
        };
    }

    fn readAvailable(
        context: *anyopaque,
        max_frames: usize,
        output_buffer: []u8,
    ) []u8 {
        const self: *TestSource = @ptrCast(@alignCast(context));
        const length = @min(
            self.bytes.len,
            @min(output_buffer.len, max_frames * self.frame_bytes),
        );
        const written = output_buffer[0..length];
        @memcpy(written, self.bytes[0..length]);
        return written;
    }
};

fn renderForTest(
    sample_format: SampleFormat,
    source_bytes: []const u8,
    gain: f64,
    output: []u8,
) ![]u8 {
    const sample_bytes = try backend.sample_format_bytes(sample_format);
    var source = TestSource{ .bytes = source_bytes, .frame_bytes = 0 };
    var stage = GainStage.init(
        .{
            .sample_format = sample_format,
            .sample_rate = 48_000,
            .channels = 1,
        },
        source.outputSource(sample_bytes),
    );
    try stage.setGain(gain);
    const output_source = stage.outputSource();
    return output_source.readAvailable(
        output_source.context,
        source_bytes.len / sample_bytes,
        output,
    );
}

test "unity gain preserves every PCM format byte for byte" {
    const cases = [_]struct {
        format: SampleFormat,
        bytes: []const u8,
    }{
        .{ .format = .pcm_s16le, .bytes = &.{ 0x00, 0x80, 0xff, 0x7f } },
        .{ .format = .pcm_s24le_packed, .bytes = &.{ 0x00, 0x00, 0x80, 0xff, 0xff, 0x7f } },
        .{ .format = .pcm_s24le_in_s32le, .bytes = &.{ 0x00, 0x00, 0x00, 0x80, 0x00, 0xff, 0xff, 0x7f } },
        .{ .format = .pcm_s32le, .bytes = &.{ 0x00, 0x00, 0x00, 0x80, 0xff, 0xff, 0xff, 0x7f } },
        .{ .format = .pcm_f32le, .bytes = &.{ 0x01, 0x00, 0xc0, 0x7f, 0x00, 0x00, 0x80, 0x3f } },
    };

    for (cases) |case| {
        var output: [8]u8 = undefined;
        const rendered = try renderForTest(
            case.format,
            case.bytes,
            1,
            output[0..case.bytes.len],
        );
        try std.testing.expectEqualSlices(u8, case.bytes, rendered);
    }
}

test "half gain scales signed integer PCM formats" {
    const cases = [_]struct {
        format: SampleFormat,
        source: []const u8,
        expected: []const u8,
    }{
        .{
            .format = .pcm_s16le,
            .source = &.{ 0xff, 0x7f, 0x00, 0x80 },
            .expected = &.{ 0x00, 0x40, 0x00, 0xc0 },
        },
        .{
            .format = .pcm_s24le_packed,
            .source = &.{ 0xff, 0xff, 0x7f, 0x00, 0x00, 0x80 },
            .expected = &.{ 0x00, 0x00, 0x40, 0x00, 0x00, 0xc0 },
        },
        .{
            .format = .pcm_s24le_in_s32le,
            .source = &.{ 0x00, 0xff, 0xff, 0x7f, 0x00, 0x00, 0x00, 0x80 },
            .expected = &.{ 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0xc0 },
        },
        .{
            .format = .pcm_s32le,
            .source = &.{ 0xff, 0xff, 0xff, 0x7f, 0x00, 0x00, 0x00, 0x80 },
            .expected = &.{ 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0xc0 },
        },
    };

    for (cases) |case| {
        var output: [8]u8 = undefined;
        const rendered = try renderForTest(
            case.format,
            case.source,
            0.5,
            output[0..case.source.len],
        );
        try std.testing.expectEqualSlices(u8, case.expected, rendered);
    }
}

test "half gain scales float PCM" {
    const source_values = [_]f32{ 1, -0.5 };
    const expected_values = [_]f32{ 0.5, -0.25 };
    var source: [source_values.len * @sizeOf(f32)]u8 = undefined;
    for (source_values, 0..) |value, index| {
        std.mem.writeInt(
            u32,
            source[index * @sizeOf(f32) ..][0..@sizeOf(f32)],
            @bitCast(value),
            .little,
        );
    }

    var output: [source.len]u8 = undefined;
    const rendered = try renderForTest(.pcm_f32le, &source, 0.5, &output);
    for (expected_values, 0..) |expected, index| {
        const bits = std.mem.readInt(
            u32,
            rendered[index * @sizeOf(f32) ..][0..@sizeOf(f32)],
            .little,
        );
        try std.testing.expectEqual(expected, @as(f32, @bitCast(bits)));
    }
}

test "zero gain mutes rendered bytes" {
    const source = [_]u8{ 0xff, 0x7f, 0x00, 0x80 };
    var output: [source.len]u8 = undefined;
    const rendered = try renderForTest(.pcm_s16le, &source, 0, &output);
    try std.testing.expectEqualSlices(u8, &@as([source.len]u8, @splat(0)), rendered);
}

test "gain rejects values outside attenuation range" {
    var source = TestSource{ .bytes = &.{}, .frame_bytes = 0 };
    var stage = GainStage.init(
        .{
            .sample_format = .pcm_s16le,
            .sample_rate = 48_000,
            .channels = 2,
        },
        source.outputSource(4),
    );

    try std.testing.expectError(error.InvalidGain, stage.setGain(-0.1));
    try std.testing.expectError(error.InvalidGain, stage.setGain(1.1));
    try std.testing.expectError(error.InvalidGain, stage.setGain(std.math.nan(f64)));
}
