const std = @import("std");

pub const max_metadata_bytes: usize = 64 * 1024 * 1024;
pub const max_comment_bytes: usize = 1024 * 1024;
pub const max_comment_count: u32 = 4096;
pub const max_artwork_source_bytes: usize = 32 * 1024 * 1024;
pub const max_artwork_width: u32 = 6_000;
pub const max_artwork_height: u32 = 6_000;
pub const max_artwork_pixels: u64 = 25_000_000;

pub const Error = error{
    InvalidStreamMarker,
    TruncatedMetadata,
    MetadataTooLarge,
    MissingStreamInfo,
    InvalidStreamInfo,
    DuplicateStreamInfo,
    InvalidVorbisComment,
    InvalidPicture,
};

pub const StreamInfo = struct {
    minimum_block_size: u16,
    maximum_block_size: u16,
    minimum_frame_size: u24,
    maximum_frame_size: u24,
    sample_rate: u32,
    channels: u8,
    bits_per_sample: u8,
    total_samples: u64,
    md5: [16]u8,
};

/// An owned FLAC PICTURE block selected for later validation by the platform
/// image backend. The dimensions are untrusted format claims, not decoded
/// image dimensions.
pub const Picture = struct {
    picture_type: u32,
    mime_type: []u8,
    description: []u8,
    width: u32,
    height: u32,
    color_depth: u32,
    indexed_colors: u32,
    bytes: []u8,

    pub fn deinit(self: *Picture, allocator: std.mem.Allocator) void {
        allocator.free(self.mime_type);
        allocator.free(self.description);
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

/// Scanner-ready FLAC metadata. Every slice is owned and remains valid after
/// the encoded input is released. Call `deinit` exactly once.
pub const Metadata = struct {
    stream_info: StreamInfo,
    title: ?[]u8 = null,
    track_artist: ?[]u8 = null,
    album_artist: ?[]u8 = null,
    album: ?[]u8 = null,
    track_number: ?u16 = null,
    disc_number: ?u16 = null,
    release_date: ?[]u8 = null,
    duration_ms: ?u64,
    codec: []u8,
    sample_rate: u32,
    bits_per_sample: u8,
    artwork: ?Picture = null,

    pub fn deinit(self: *Metadata, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.title);
        freeOptional(allocator, self.track_artist);
        freeOptional(allocator, self.album_artist);
        freeOptional(allocator, self.album);
        freeOptional(allocator, self.release_date);
        if (self.artwork) |*picture| picture.deinit(allocator);
        allocator.free(self.codec);
        self.* = undefined;
    }
};

const OwnedTag = struct {
    value: ?[]u8 = null,
    priority: u8 = std.math.maxInt(u8),

    fn deinit(self: *OwnedTag, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.value);
        self.* = .{};
    }

    fn add(
        self: *OwnedTag,
        allocator: std.mem.Allocator,
        value: []const u8,
        priority: u8,
    ) !void {
        if (priority > self.priority) return;

        if (priority < self.priority or self.value == null) {
            const replacement = try allocator.dupe(u8, value);
            freeOptional(allocator, self.value);
            self.value = replacement;
            self.priority = priority;
            return;
        }

        const previous = self.value.?;
        const joined = try std.mem.concat(allocator, u8, &.{ previous, ";", value });
        allocator.free(previous);
        self.value = joined;
    }
};

const Builder = struct {
    stream_info: ?StreamInfo = null,
    title: OwnedTag = .{},
    track_artist: OwnedTag = .{},
    album_artist: OwnedTag = .{},
    album: OwnedTag = .{},
    track_number: OwnedTag = .{},
    disc_number: OwnedTag = .{},
    release_date: OwnedTag = .{},
    artwork: ?Picture = null,

    fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
        self.title.deinit(allocator);
        self.track_artist.deinit(allocator);
        self.album_artist.deinit(allocator);
        self.album.deinit(allocator);
        self.track_number.deinit(allocator);
        self.disc_number.deinit(allocator);
        self.release_date.deinit(allocator);
        if (self.artwork) |*picture| picture.deinit(allocator);
        self.* = .{};
    }
};

const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn remaining(self: Cursor) usize {
        return self.bytes.len - self.index;
    }

    fn take(self: *Cursor, length: usize) Error![]const u8 {
        if (length > self.remaining()) return error.TruncatedMetadata;
        const result = self.bytes[self.index..][0..length];
        self.index += length;
        return result;
    }

    fn takeU32Le(self: *Cursor) Error!u32 {
        return std.mem.readInt(u32, (try self.take(4))[0..4], .little);
    }

    fn takeU32Be(self: *Cursor) Error!u32 {
        return std.mem.readInt(u32, (try self.take(4))[0..4], .big);
    }
};

/// Parses the metadata chain at the start of a complete FLAC file or a slice
/// ending immediately after its last metadata block. Audio frames following
/// the last block are intentionally ignored.
pub fn parse(allocator: std.mem.Allocator, encoded: []const u8) !Metadata {
    var cursor = Cursor{ .bytes = encoded };
    const marker = cursor.take(4) catch return error.InvalidStreamMarker;
    if (!std.mem.eql(u8, marker, "fLaC")) return error.InvalidStreamMarker;

    var builder: Builder = .{};
    defer builder.deinit(allocator);

    var metadata_bytes: usize = 4;
    var is_last = false;
    var block_index: usize = 0;
    while (!is_last) : (block_index += 1) {
        const header = cursor.take(4) catch return error.TruncatedMetadata;
        is_last = (header[0] & 0x80) != 0;
        const block_type = header[0] & 0x7f;
        const block_length = (@as(usize, header[1]) << 16) |
            (@as(usize, header[2]) << 8) |
            @as(usize, header[3]);

        metadata_bytes = std.math.add(usize, metadata_bytes, 4 + block_length) catch
            return error.MetadataTooLarge;
        if (metadata_bytes > max_metadata_bytes) return error.MetadataTooLarge;

        const block = cursor.take(block_length) catch return error.TruncatedMetadata;
        if (block_index == 0 and block_type != 0) return error.MissingStreamInfo;

        switch (block_type) {
            0 => {
                if (builder.stream_info != null) return error.DuplicateStreamInfo;
                builder.stream_info = try parseStreamInfo(block);
            },
            4 => try parseVorbisComment(allocator, block, &builder),
            6 => if (try parsePicture(allocator, block)) |picture| {
                selectPicture(allocator, &builder.artwork, picture);
            },
            else => {},
        }
    }

    const stream_info = builder.stream_info orelse return error.MissingStreamInfo;
    const codec = try allocator.dupe(u8, "flac");
    errdefer allocator.free(codec);

    const result: Metadata = .{
        .stream_info = stream_info,
        .title = builder.title.value,
        .track_artist = builder.track_artist.value,
        .album_artist = builder.album_artist.value,
        .album = builder.album.value,
        .track_number = parseNumber(builder.track_number.value),
        .disc_number = parseNumber(builder.disc_number.value),
        .release_date = builder.release_date.value,
        .duration_ms = durationMs(stream_info.total_samples, stream_info.sample_rate),
        .codec = codec,
        .sample_rate = stream_info.sample_rate,
        .bits_per_sample = stream_info.bits_per_sample,
        .artwork = builder.artwork,
    };

    builder.title.value = null;
    builder.track_artist.value = null;
    builder.album_artist.value = null;
    builder.album.value = null;
    builder.release_date.value = null;
    builder.artwork = null;
    return result;
}

fn parseStreamInfo(block: []const u8) Error!StreamInfo {
    if (block.len != 34) return error.InvalidStreamInfo;

    const packed_value = std.mem.readInt(u64, block[10..18], .big);
    const sample_rate: u32 = @intCast(packed_value >> 44);
    if (sample_rate == 0) return error.InvalidStreamInfo;

    return .{
        .minimum_block_size = std.mem.readInt(u16, block[0..2], .big),
        .maximum_block_size = std.mem.readInt(u16, block[2..4], .big),
        .minimum_frame_size = std.mem.readInt(u24, block[4..7], .big),
        .maximum_frame_size = std.mem.readInt(u24, block[7..10], .big),
        .sample_rate = sample_rate,
        .channels = @intCast(((packed_value >> 41) & 0x7) + 1),
        .bits_per_sample = @intCast(((packed_value >> 36) & 0x1f) + 1),
        .total_samples = packed_value & 0x0000000fffffffff,
        .md5 = block[18..34].*,
    };
}

fn parseVorbisComment(
    allocator: std.mem.Allocator,
    block: []const u8,
    builder: *Builder,
) !void {
    var cursor = Cursor{ .bytes = block };
    const vendor_length = cursor.takeU32Le() catch return error.InvalidVorbisComment;
    _ = cursor.take(vendor_length) catch return error.InvalidVorbisComment;
    const count = cursor.takeU32Le() catch return error.InvalidVorbisComment;
    if (count > max_comment_count) return error.MetadataTooLarge;

    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const length = cursor.takeU32Le() catch return error.InvalidVorbisComment;
        if (length > max_comment_bytes) return error.MetadataTooLarge;
        const comment = cursor.take(length) catch return error.InvalidVorbisComment;
        const separator = std.mem.indexOfScalar(u8, comment, '=') orelse continue;
        if (separator == 0) continue;
        try addComment(allocator, builder, comment[0..separator], comment[separator + 1 ..]);
    }

    if (cursor.remaining() != 0) return error.InvalidVorbisComment;
}

fn addComment(
    allocator: std.mem.Allocator,
    builder: *Builder,
    key: []const u8,
    value: []const u8,
) !void {
    if (std.ascii.eqlIgnoreCase(key, "title"))
        try builder.title.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "artist"))
        try builder.track_artist.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "album_artist"))
        try builder.album_artist.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "albumartist"))
        try builder.album_artist.add(allocator, value, 1)
    else if (std.ascii.eqlIgnoreCase(key, "album"))
        try builder.album.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "track"))
        try builder.track_number.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "tracknumber"))
        try builder.track_number.add(allocator, value, 1)
    else if (std.ascii.eqlIgnoreCase(key, "disc"))
        try builder.disc_number.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "discnumber"))
        try builder.disc_number.add(allocator, value, 1)
    else if (std.ascii.eqlIgnoreCase(key, "date"))
        try builder.release_date.add(allocator, value, 0)
    else if (std.ascii.eqlIgnoreCase(key, "year"))
        try builder.release_date.add(allocator, value, 1);
}

fn parsePicture(allocator: std.mem.Allocator, block: []const u8) !?Picture {
    var cursor = Cursor{ .bytes = block };
    const picture_type = cursor.takeU32Be() catch return error.InvalidPicture;
    const mime_length = cursor.takeU32Be() catch return error.InvalidPicture;
    const mime_type = cursor.take(mime_length) catch return error.InvalidPicture;
    const description_length = cursor.takeU32Be() catch return error.InvalidPicture;
    const description = cursor.take(description_length) catch return error.InvalidPicture;
    const width = cursor.takeU32Be() catch return error.InvalidPicture;
    const height = cursor.takeU32Be() catch return error.InvalidPicture;
    const color_depth = cursor.takeU32Be() catch return error.InvalidPicture;
    const indexed_colors = cursor.takeU32Be() catch return error.InvalidPicture;
    const data_length = cursor.takeU32Be() catch return error.InvalidPicture;
    const bytes = cursor.take(data_length) catch return error.InvalidPicture;
    if (cursor.remaining() != 0) return error.InvalidPicture;

    if (mime_type.len > max_comment_bytes or description.len > max_comment_bytes) return null;
    if (bytes.len == 0 or bytes.len > max_artwork_source_bytes) return null;
    if (!claimedDimensionsAllowed(width, height)) return null;

    const owned_mime = try allocator.dupe(u8, mime_type);
    errdefer allocator.free(owned_mime);
    const owned_description = try allocator.dupe(u8, description);
    errdefer allocator.free(owned_description);
    const owned_bytes = try allocator.dupe(u8, bytes);
    errdefer allocator.free(owned_bytes);

    return .{
        .picture_type = picture_type,
        .mime_type = owned_mime,
        .description = owned_description,
        .width = width,
        .height = height,
        .color_depth = color_depth,
        .indexed_colors = indexed_colors,
        .bytes = owned_bytes,
    };
}

fn claimedDimensionsAllowed(width: u32, height: u32) bool {
    // Zero means "unknown" in real-world files. The image backend remains the
    // authority and must validate the decoded dimensions in all cases.
    if (width > max_artwork_width or height > max_artwork_height) return false;
    if (width == 0 or height == 0) return true;
    return @as(u64, width) * @as(u64, height) <= max_artwork_pixels;
}

fn selectPicture(
    allocator: std.mem.Allocator,
    selected: *?Picture,
    candidate: Picture,
) void {
    if (selected.* == null) {
        selected.* = candidate;
        return;
    }

    if (selected.*.?.picture_type != 3 and candidate.picture_type == 3) {
        selected.*.?.deinit(allocator);
        selected.* = candidate;
        return;
    }

    var rejected = candidate;
    rejected.deinit(allocator);
}

fn durationMs(total_samples: u64, sample_rate: u32) ?u64 {
    if (total_samples == 0) return null;
    const milliseconds = std.math.mul(u64, total_samples, 1000) catch return null;
    // Round positive stream durations to the nearest millisecond.
    return (milliseconds + sample_rate / 2) / sample_rate;
}

fn parseNumber(raw: ?[]const u8) ?u16 {
    const value = raw orelse return null;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    const separator = std.mem.indexOfScalar(u8, trimmed, '/') orelse trimmed.len;
    const number = std.mem.trim(u8, trimmed[0..separator], " \t");
    if (number.len == 0) return null;
    return std.fmt.parseInt(u16, number, 10) catch null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}
