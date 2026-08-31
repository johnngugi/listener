const std = @import("std");
const builtin = @import("builtin");

pub const max_source_bytes: usize = 32 * 1024 * 1024;
pub const max_encoded_bytes: usize = 10 * 1024 * 1024;
pub const max_width: u32 = 6_000;
pub const max_height: u32 = 6_000;
pub const max_pixels: u64 = 25_000_000;
pub const max_stored_dimension: u32 = 1_024;

pub const Format = enum {
    jpeg,
    png,
    webp,

    pub fn mimeType(self: Format) []const u8 {
        return switch (self) {
            .jpeg => "image/jpeg",
            .png => "image/png",
            .webp => "image/webp",
        };
    }

    pub fn extension(self: Format) []const u8 {
        return switch (self) {
            .jpeg => "jpg",
            .png => "png",
            .webp => "webp",
        };
    }
};

/// Validated, encoded artwork owned by the caller.
pub const Artwork = struct {
    format: Format,
    bytes: []u8,
    width: u32,
    height: u32,

    pub fn deinit(self: *Artwork, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

/// Detects the encoded format, validates the decoded image, and normalizes it
/// when its encoded size or longest dimension exceeds the storage policy.
/// Invalid and unsupported images are rejected with `null`; allocation
/// failures remain errors.
pub fn process(allocator: std.mem.Allocator, encoded: []const u8) !?Artwork {
    if (encoded.len == 0 or encoded.len > max_source_bytes) return null;

    return switch (builtin.os.tag) {
        .macos => @import("macos/artwork.zig").process(Artwork, Format, allocator, encoded),
        else => @compileError("no artwork backend is available for this platform"),
    };
}

pub fn dimensionsAllowed(width: u32, height: u32) bool {
    if (width == 0 or height == 0) return false;
    if (width > max_width or height > max_height) return false;
    return @as(u64, width) * @as(u64, height) <= max_pixels;
}

test "format metadata is stable" {
    try std.testing.expectEqualStrings("image/jpeg", Format.jpeg.mimeType());
    try std.testing.expectEqualStrings("png", Format.png.extension());
    try std.testing.expectEqualStrings("image/webp", Format.webp.mimeType());
}

test "dimension policy rejects empty and excessive images" {
    try std.testing.expect(dimensionsAllowed(5_000, 5_000));
    try std.testing.expect(!dimensionsAllowed(0, 1_000));
    try std.testing.expect(!dimensionsAllowed(6_001, 1_000));
    try std.testing.expect(!dimensionsAllowed(6_000, 6_000));
}

test "macOS backend detects and preserves supported fixtures" {
    const cases = .{
        .{ @embedFile("../testdata/fixtures/baseline-cover.jpg"), Format.jpeg },
        .{ @embedFile("../testdata/fixtures/baseline-cover.png"), Format.png },
        .{ @embedFile("../testdata/fixtures/baseline-cover.webp"), Format.webp },
    };

    inline for (cases) |case| {
        var result = (try process(std.testing.allocator, case[0])) orelse
            return error.ArtworkRejected;
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(case[1], result.format);
        try std.testing.expectEqual(@as(u32, 4), result.width);
        try std.testing.expectEqual(@as(u32, 2), result.height);
        try std.testing.expectEqualSlices(u8, case[0], result.bytes);
    }
}

test "macOS backend rejects invalid and truncated encoded data" {
    try std.testing.expect((try process(std.testing.allocator, "not an image")) == null);

    const png = @embedFile("../testdata/fixtures/baseline-cover.png");
    try std.testing.expect((try process(std.testing.allocator, png[0..20])) == null);
}

test "macOS backend resizes oversized artwork and encodes JPEG" {
    var result = (try process(
        std.testing.allocator,
        @embedFile("../testdata/fixtures/oversized-cover.jpg"),
    )) orelse return error.ArtworkRejected;
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(Format.jpeg, result.format);
    try std.testing.expectEqual(max_stored_dimension, @max(result.width, result.height));
    try std.testing.expect(result.width <= max_stored_dimension);
    try std.testing.expect(result.height <= max_stored_dimension);
    try std.testing.expect(result.bytes.len <= max_encoded_bytes);
}
