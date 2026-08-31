const std = @import("std");
const metadata_parser = @import("media/flac/metadata.zig");

test "parses scanner fields and STREAMINFO without platform libraries" {
    var metadata = try metadata_parser.parse(
        std.testing.allocator,
        @embedFile("testdata/fixtures/baseline-metadata.flac"),
    );
    defer metadata.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("Baseline Title", metadata.title.?);
    try std.testing.expectEqualStrings("Track Artist", metadata.track_artist.?);
    try std.testing.expectEqualStrings(
        "Preferred Album Artist;Fallback Album Artist",
        metadata.album_artist.?,
    );
    try std.testing.expectEqualStrings("Baseline Album", metadata.album.?);
    try std.testing.expectEqual(@as(?u16, 3), metadata.track_number);
    try std.testing.expectEqual(@as(?u16, 2), metadata.disc_number);
    try std.testing.expectEqualStrings("2026-08-31", metadata.release_date.?);
    try std.testing.expectEqualStrings("flac", metadata.codec);
    try std.testing.expectEqual(@as(u32, 22_050), metadata.sample_rate);
    try std.testing.expectEqual(@as(u8, 1), metadata.stream_info.channels);
    try std.testing.expectEqual(@as(u8, 16), metadata.bits_per_sample);
    try std.testing.expectEqual(@as(u64, 17), metadata.stream_info.total_samples);
    try std.testing.expectEqual(@as(?u64, 1), metadata.duration_ms);
}

test "selects embedded front covers and owns their encoded bytes" {
    const cases = .{
        .{ @embedFile("testdata/fixtures/baseline-embedded-jpg.flac"), "image/jpeg" },
        .{ @embedFile("testdata/fixtures/baseline-embedded-png.flac"), "image/png" },
        .{ @embedFile("testdata/fixtures/baseline-embedded-webp.flac"), "image/webp" },
    };

    inline for (cases) |case| {
        var metadata = try metadata_parser.parse(std.testing.allocator, case[0]);
        defer metadata.deinit(std.testing.allocator);
        const picture = metadata.artwork orelse return error.MissingArtwork;
        try std.testing.expectEqual(@as(u32, 3), picture.picture_type);
        try std.testing.expectEqualStrings(case[1], picture.mime_type);
        try std.testing.expectEqual(@as(u32, 4), picture.width);
        try std.testing.expectEqual(@as(u32, 2), picture.height);
        try std.testing.expect(picture.bytes.len > 0);
    }
}

test "rejects truncated and adversarial metadata lengths safely" {
    const valid = @embedFile("testdata/fixtures/baseline-metadata.flac");
    try std.testing.expectError(
        error.InvalidStreamMarker,
        metadata_parser.parse(std.testing.allocator, ""),
    );
    try std.testing.expectError(
        error.InvalidStreamMarker,
        metadata_parser.parse(std.testing.allocator, "fLa"),
    );
    try std.testing.expectError(
        error.TruncatedMetadata,
        metadata_parser.parse(std.testing.allocator, "fLaC\x84\xff\xff\xfftruncated"),
    );

    // Every prefix through the complete metadata chain is incomplete.
    const metadata_end = findMetadataEnd(valid);
    var length: usize = 4;
    while (length < metadata_end) : (length += 1) {
        try std.testing.expectError(
            error.TruncatedMetadata,
            metadata_parser.parse(std.testing.allocator, valid[0..length]),
        );
    }

    var oversized_count = [_]u8{
        'f',  'L',  'a',  'C',
        0x00, 0x00, 0x00, 0x22,
    } ++ [_]u8{0} ** 34 ++ [_]u8{
        0x84, 0x00, 0x00, 0x08,
        0x00, 0x00, 0x00, 0x00,
        0x01, 0x10, 0x00, 0x00,
    };
    // Supply valid STREAMINFO packed fields before exercising the count cap.
    oversized_count[18] = 0x05;
    oversized_count[19] = 0x62;
    oversized_count[20] = 0x20;
    oversized_count[21] = 0xf0;
    try std.testing.expectError(
        error.MetadataTooLarge,
        metadata_parser.parse(std.testing.allocator, &oversized_count),
    );
}

test "prefers the first front cover and retains a bounded deterministic fallback" {
    const allocator = std.testing.allocator;
    const fixture = @embedFile("testdata/fixtures/baseline-metadata.flac");

    var encoded: std.ArrayList(u8) = .empty;
    defer encoded.deinit(allocator);
    try encoded.appendSlice(allocator, "fLaC");
    try appendBlock(allocator, &encoded, 0, false, fixture[8..42]);
    try appendPictureBlock(allocator, &encoded, 0, false, 4, 2, "fallback");
    try appendPictureBlock(allocator, &encoded, 3, false, 4, 2, "front");
    try appendPictureBlock(allocator, &encoded, 3, true, 4, 2, "later-front");

    var preferred = try metadata_parser.parse(allocator, encoded.items);
    defer preferred.deinit(allocator);
    try std.testing.expectEqualStrings("front", preferred.artwork.?.bytes);

    var bounded: std.ArrayList(u8) = .empty;
    defer bounded.deinit(allocator);
    try bounded.appendSlice(allocator, "fLaC");
    try appendBlock(allocator, &bounded, 0, false, fixture[8..42]);
    try appendPictureBlock(allocator, &bounded, 0, false, 4, 2, "fallback");
    try appendPictureBlock(allocator, &bounded, 3, true, 6_001, 2, "oversized");

    var fallback = try metadata_parser.parse(allocator, bounded.items);
    defer fallback.deinit(allocator);
    try std.testing.expectEqualStrings("fallback", fallback.artwork.?.bytes);
}

test "malformed PICTURE fields fail without out-of-bounds reads" {
    const allocator = std.testing.allocator;
    const fixture = @embedFile("testdata/fixtures/baseline-metadata.flac");
    var encoded: std.ArrayList(u8) = .empty;
    defer encoded.deinit(allocator);
    try encoded.appendSlice(allocator, "fLaC");
    try appendBlock(allocator, &encoded, 0, false, fixture[8..42]);
    try appendBlock(allocator, &encoded, 6, true, "\x00\x00\x00\x03");
    try std.testing.expectError(
        error.InvalidPicture,
        metadata_parser.parse(allocator, encoded.items),
    );
}

test "unknown blocks are skipped and a missing first STREAMINFO is rejected" {
    try std.testing.expectError(
        error.MissingStreamInfo,
        metadata_parser.parse(std.testing.allocator, "fLaC\xff\x00\x00\x00"),
    );

    var encoded = [_]u8{
        'f',  'L',  'a',  'C',
        0x00, 0x00, 0x00, 0x22,
    } ++ [_]u8{0} ** 34 ++ [_]u8{
        0xff, 0x00, 0x00, 0x03, 0xaa, 0xbb, 0xcc,
    };
    encoded[18] = 0x0a;
    encoded[19] = 0xc4;
    encoded[20] = 0x42;
    encoded[21] = 0xf0;

    var metadata = try metadata_parser.parse(std.testing.allocator, &encoded);
    defer metadata.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 44_100), metadata.sample_rate);
    try std.testing.expect(metadata.title == null);
}

fn findMetadataEnd(encoded: []const u8) usize {
    var offset: usize = 4;
    while (true) {
        const is_last = (encoded[offset] & 0x80) != 0;
        const length = (@as(usize, encoded[offset + 1]) << 16) |
            (@as(usize, encoded[offset + 2]) << 8) |
            encoded[offset + 3];
        offset += 4 + length;
        if (is_last) return offset;
    }
}

fn appendBlock(
    allocator: std.mem.Allocator,
    encoded: *std.ArrayList(u8),
    block_type: u7,
    is_last: bool,
    payload: []const u8,
) !void {
    std.debug.assert(payload.len <= 0x00ff_ffff);
    const last_bit: u8 = if (is_last) 0x80 else 0;
    const header = [4]u8{
        last_bit | @as(u8, block_type),
        @intCast((payload.len >> 16) & 0xff),
        @intCast((payload.len >> 8) & 0xff),
        @intCast(payload.len & 0xff),
    };
    try encoded.appendSlice(allocator, &header);
    try encoded.appendSlice(allocator, payload);
}

fn appendPictureBlock(
    allocator: std.mem.Allocator,
    encoded: *std.ArrayList(u8),
    picture_type: u32,
    is_last: bool,
    width: u32,
    height: u32,
    bytes: []const u8,
) !void {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(allocator);
    try appendU32Be(allocator, &payload, picture_type);
    try appendU32Be(allocator, &payload, "image/test".len);
    try payload.appendSlice(allocator, "image/test");
    try appendU32Be(allocator, &payload, 0);
    try appendU32Be(allocator, &payload, width);
    try appendU32Be(allocator, &payload, height);
    try appendU32Be(allocator, &payload, 24);
    try appendU32Be(allocator, &payload, 0);
    try appendU32Be(allocator, &payload, @intCast(bytes.len));
    try payload.appendSlice(allocator, bytes);
    try appendBlock(allocator, encoded, 6, is_last, payload.items);
}

fn appendU32Be(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(u8),
    value: u32,
) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .big);
    try list.appendSlice(allocator, &bytes);
}
