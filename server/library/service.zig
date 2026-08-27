const std = @import("std");
const database = @import("database.zig");

pub const service_full_name = "listener.control.v1.ListenerLibrary";

pub const Method = enum {
    list_tracks,
    get_artwork,

    pub fn fullName(self: Method) []const u8 {
        return switch (self) {
            .list_tracks => "/" ++ service_full_name ++ "/ListTracks",
            .get_artwork => "/" ++ service_full_name ++ "/GetArtwork",
        };
    }
};

pub const default_page_size: u32 = 100;
pub const max_page_size: u32 = 500;
pub const max_artwork_bytes: u64 = 10 * 1024 * 1024;

pub const ListTracksRequest = struct {
    page_size: u32 = 0,
    page_token: []const u8 = "",
    sort: database.TrackSort = .{},
};

pub const GetArtworkRequest = struct {
    artwork_id: i64 = 0,
};

pub const Artwork = struct {
    id: i64,
    mime_type: []u8,
    width: u32,
    height: u32,
    data: []u8,

    pub fn deinit(self: *Artwork, allocator: std.mem.Allocator) void {
        allocator.free(self.mime_type);
        allocator.free(self.data);
        self.* = undefined;
    }
};

pub const Error = database.Error || error{
    ArtworkFileInvalid,
    ArtworkNotFound,
    InvalidPageSize,
    InvalidPageToken,
    TrackNotFound,
};

pub const Service = struct {
    db: database.Database,
    io: std.Io,
    artwork_dir: []const u8,

    pub fn init(db: database.Database, io: std.Io, artwork_dir: []const u8) Service {
        return .{ .db = db, .io = io, .artwork_dir = artwork_dir };
    }

    pub fn listTracks(
        self: Service,
        allocator: std.mem.Allocator,
        request: ListTracksRequest,
    ) Error!database.TrackPage {
        const limit = if (request.page_size == 0)
            default_page_size
        else if (request.page_size <= max_page_size)
            request.page_size
        else
            return error.InvalidPageSize;

        var decoded_token = try decodePageToken(
            allocator,
            request.page_token,
            request.sort,
        );
        defer decoded_token.deinit(allocator);

        return self.db.listTracks(allocator, .{
            .sort = request.sort,
            .after = decoded_token.cursor,
            .limit = limit,
        });
    }

    pub fn getArtwork(
        self: Service,
        allocator: std.mem.Allocator,
        request: GetArtworkRequest,
    ) Error!Artwork {
        if (request.artwork_id <= 0) return error.ArtworkNotFound;

        var artworkResult = (try self.db.getArtwork(allocator, request.artwork_id)) orelse
            return error.ArtworkNotFound;
        defer artworkResult.deinit(allocator);

        if (artworkResult.byte_length > max_artwork_bytes) return error.ArtworkFileInvalid;
        if (std.fs.path.isAbsolute(artworkResult.storage_key) or
            std.mem.eql(u8, artworkResult.storage_key, "..") or
            std.mem.startsWith(u8, artworkResult.storage_key, "../") or
            std.mem.indexOf(u8, artworkResult.storage_key, "/../") != null)
        {
            return error.ArtworkFileInvalid;
        }

        const absolute_path = std.fs.path.join(
            allocator,
            &.{ self.artwork_dir, artworkResult.storage_key },
        ) catch return error.OutOfMemory;
        defer allocator.free(absolute_path);

        const data = std.Io.Dir.cwd().readFileAlloc(
            self.io,
            absolute_path,
            allocator,
            // The reader needs room for one additional byte to distinguish a
            // file of exactly `byte_length` bytes from an oversized file.
            .limited(artworkResult.byte_length + 1),
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.ArtworkFileInvalid,
        };
        errdefer allocator.free(data);

        if (data.len != artworkResult.byte_length) return error.ArtworkFileInvalid;

        return .{
            .id = artworkResult.id,
            .mime_type = allocator.dupe(u8, artworkResult.mime_type) catch return error.OutOfMemory,
            .width = artworkResult.width,
            .height = artworkResult.height,
            .data = data,
        };
    }

    pub fn resolveTrack(
        self: Service,
        allocator: std.mem.Allocator,
        track_id: []const u8,
    ) Error!database.TrackSource {
        if (!database.isTrackId(track_id)) return error.TrackNotFound;
        return (try self.db.getTrackSource(allocator, track_id)) orelse
            error.TrackNotFound;
    }
};

const DecodedPageToken = struct {
    cursor: ?database.TrackCursor = null,
    owned_text: ?[]u8 = null,

    fn deinit(self: *DecodedPageToken, allocator: std.mem.Allocator) void {
        if (self.owned_text) |text| allocator.free(text);
        self.* = undefined;
    }
};

fn decodePageToken(
    allocator: std.mem.Allocator,
    token: []const u8,
    expected_sort: database.TrackSort,
) Error!DecodedPageToken {
    if (token.len == 0) return .{};

    // Keep accepting the original ID-only cursor for the default ordering.
    if (!std.mem.startsWith(u8, token, "v1:")) {
        if (!expected_sort.eql(.{})) return error.InvalidPageToken;
        const id = std.fmt.parseInt(i64, token, 10) catch
            return error.InvalidPageToken;
        if (id <= 0) return error.InvalidPageToken;
        return .{ .cursor = .{ .value = .{ .integer = id }, .id = id } };
    }

    var parts = std.mem.splitScalar(u8, token, ':');
    if (!std.mem.eql(u8, parts.next() orelse return error.InvalidPageToken, "v1"))
        return error.InvalidPageToken;
    const field_value = std.fmt.parseInt(u8, parts.next() orelse return error.InvalidPageToken, 10) catch
        return error.InvalidPageToken;
    const direction_value = std.fmt.parseInt(u8, parts.next() orelse return error.InvalidPageToken, 10) catch
        return error.InvalidPageToken;
    const id = std.fmt.parseInt(i64, parts.next() orelse return error.InvalidPageToken, 10) catch
        return error.InvalidPageToken;
    const kind = parts.next() orelse return error.InvalidPageToken;
    const encoded_value = parts.next() orelse return error.InvalidPageToken;
    if (parts.next() != null or id <= 0) return error.InvalidPageToken;

    const sort: database.TrackSort = .{
        .field = std.enums.fromInt(database.TrackSortField, field_value) orelse
            return error.InvalidPageToken,
        .direction = std.enums.fromInt(database.SortDirection, direction_value) orelse
            return error.InvalidPageToken,
    };
    if (!sort.eql(expected_sort)) return error.InvalidPageToken;

    if (std.mem.eql(u8, kind, "i")) {
        const value = std.fmt.parseInt(i64, encoded_value, 10) catch
            return error.InvalidPageToken;
        return .{ .cursor = .{ .value = .{ .integer = value }, .id = id } };
    }
    if (!std.mem.eql(u8, kind, "t")) return error.InvalidPageToken;

    const text = try decodeHex(allocator, encoded_value);
    return .{
        .cursor = .{ .value = .{ .text = text }, .id = id },
        .owned_text = text,
    };
}

pub fn encodePageToken(
    allocator: std.mem.Allocator,
    track: database.Track,
    sort: database.TrackSort,
) std.mem.Allocator.Error![]u8 {
    const cursor = track.pageCursor(sort);

    // Continue emitting the original token for default-sorted clients.
    if (sort.eql(.{})) {
        return std.fmt.allocPrint(allocator, "{d}", .{cursor.id});
    }

    return switch (cursor.value) {
        .integer => |value| std.fmt.allocPrint(
            allocator,
            "v1:{d}:{d}:{d}:i:{d}",
            .{ @intFromEnum(sort.field), @intFromEnum(sort.direction), cursor.id, value },
        ),
        .text => |value| encodeTextPageToken(allocator, cursor.id, sort, value),
    };
}

fn encodeTextPageToken(
    allocator: std.mem.Allocator,
    id: i64,
    sort: database.TrackSort,
    value: []const u8,
) std.mem.Allocator.Error![]u8 {
    const prefix = try std.fmt.allocPrint(
        allocator,
        "v1:{d}:{d}:{d}:t:",
        .{ @intFromEnum(sort.field), @intFromEnum(sort.direction), id },
    );
    defer allocator.free(prefix);

    const token = try allocator.alloc(u8, prefix.len + value.len * 2);
    @memcpy(token[0..prefix.len], prefix);
    const hex = "0123456789abcdef";
    for (value, 0..) |byte, index| {
        token[prefix.len + index * 2] = hex[byte >> 4];
        token[prefix.len + index * 2 + 1] = hex[byte & 0x0f];
    }
    return token;
}

fn decodeHex(allocator: std.mem.Allocator, encoded: []const u8) Error![]u8 {
    if (encoded.len % 2 != 0) return error.InvalidPageToken;
    const text = allocator.alloc(u8, encoded.len / 2) catch return error.OutOfMemory;
    errdefer allocator.free(text);

    for (text, 0..) |*byte, index| {
        const high = hexNibble(encoded[index * 2]) orelse return error.InvalidPageToken;
        const low = hexNibble(encoded[index * 2 + 1]) orelse return error.InvalidPageToken;
        byte.* = high << 4 | low;
    }
    return text;
}

fn hexNibble(value: u8) ?u8 {
    return switch (value) {
        '0'...'9' => value - '0',
        'a'...'f' => value - 'a' + 10,
        'A'...'F' => value - 'A' + 10,
        else => null,
    };
}

test "library method has an independent gRPC service name" {
    try std.testing.expectEqualStrings(
        "/listener.control.v1.ListenerLibrary/ListTracks",
        Method.list_tracks.fullName(),
    );
    try std.testing.expectEqualStrings(
        "/listener.control.v1.ListenerLibrary/GetArtwork",
        Method.get_artwork.fullName(),
    );
}

test "page tokens round trip integer and text sort cursors" {
    const allocator = std.testing.allocator;
    const track = database.Track{
        .id = @constCast("d9428888-122b-4e3f-8f74-8f7e6b3f5c21"),
        .cursor = 42,
        .path = @constCast("/music/a.flac"),
        .size = 0,
        .modified_ns = 0,
        .title = @constCast("A:B"),
        .track_artist = null,
        .album_artist = null,
        .album = null,
        .track_number = null,
        .disc_number = null,
        .release_date = null,
        .duration_ms = 123,
        .codec = @constCast("flac"),
        .sample_rate = 0,
        .bits_per_sample = 0,
        .date_added = 0,
    };

    for ([_]database.TrackSort{
        .{ .field = .duration, .direction = .descending },
        .{ .field = .title },
    }) |sort| {
        const encoded = try encodePageToken(allocator, track, sort);
        defer allocator.free(encoded);
        var decoded = try decodePageToken(allocator, encoded, sort);
        defer decoded.deinit(allocator);
        try std.testing.expectEqual(@as(i64, 42), decoded.cursor.?.id);
        switch (decoded.cursor.?.value) {
            .integer => |value| try std.testing.expectEqual(@as(i64, 123), value),
            .text => |value| try std.testing.expectEqualStrings("A:B", value),
        }
    }

    const legacy = try decodePageToken(allocator, "42", .{});
    try std.testing.expectEqual(@as(i64, 42), legacy.cursor.?.id);
    try std.testing.expectError(
        error.InvalidPageToken,
        decodePageToken(allocator, "42", .{ .field = .title }),
    );
}

fn serviceTestFile(
    seed: u8,
    path: []const u8,
    title: []const u8,
) database.ScannedFile {
    const bytes: [16]u8 = @splat(seed);
    return .{
        .track_id = database.trackIdFromBytes(bytes),
        .path = path,
        .size = 0,
        .modified_ns = 0,
        .title = title,
        .track_artist = null,
        .album_artist = null,
        .album = null,
        .track_number = null,
        .disc_number = null,
        .release_date = null,
        .duration_ms = null,
        .codec = "flac",
        .sample_rate = 44_100,
        .bits_per_sample = 16,
    };
}

test "list tracks carries sorted page tokens across service requests" {
    const sqlite = @import("sqlite.zig");
    const allocator = std.testing.allocator;

    var db = try sqlite.open(allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const scan = try db.beginScan("/music");
    try db.upsertFiles(scan, &.{
        serviceTestFile(1, "/music/one.flac", "Zulu"),
        serviceTestFile(2, "/music/two.flac", "alpha"),
        serviceTestFile(3, "/music/three.flac", "Alpha"),
    });
    try db.finishScan(scan);

    const service = Service.init(db, std.testing.io, "");
    const sort: database.TrackSort = .{ .field = .title };
    var first = try service.listTracks(allocator, .{
        .page_size = 2,
        .sort = sort,
    });
    defer first.deinit(allocator);
    try std.testing.expect(first.has_more);
    try std.testing.expectEqualStrings("/music/two.flac", first.tracks[0].path);
    try std.testing.expectEqualStrings("/music/three.flac", first.tracks[1].path);

    const token = try encodePageToken(allocator, first.tracks[1], sort);
    defer allocator.free(token);
    var second = try service.listTracks(allocator, .{
        .page_size = 2,
        .page_token = token,
        .sort = sort,
    });
    defer second.deinit(allocator);
    try std.testing.expect(!second.has_more);
    try std.testing.expectEqual(@as(usize, 1), second.tracks.len);
    try std.testing.expectEqualStrings("/music/one.flac", second.tracks[0].path);

    try std.testing.expectError(
        error.InvalidPageToken,
        service.listTracks(allocator, .{
            .page_size = 2,
            .page_token = token,
            .sort = .{ .field = .album },
        }),
    );
}

test "get artwork returns the stored image and metadata" {
    const sqlite = @import("sqlite.zig");
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "cover.png", .data = "png-data" });

    var artwork_dir_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const artwork_dir_len = try tmp.dir.realPath(io, &artwork_dir_buffer);
    const artwork_dir = artwork_dir_buffer[0..artwork_dir_len];

    var db = try sqlite.open(allocator, ":memory:", .{});
    defer db.deinit();
    try db.migrate();

    const scan = try db.beginScan("/music");
    defer db.abortScan(scan);
    const artwork_id = try db.upsertArtwork(scan, .{
        .sha256 = @splat(0xab),
        .mime_type = "image/png",
        .width = 640,
        .height = 480,
        .byte_length = 8,
        .storage_key = "cover.png",
    });

    const service = Service.init(db, io, artwork_dir);
    var artwork = try service.getArtwork(allocator, .{ .artwork_id = artwork_id });
    defer artwork.deinit(allocator);

    try std.testing.expectEqual(artwork_id, artwork.id);
    try std.testing.expectEqualStrings("image/png", artwork.mime_type);
    try std.testing.expectEqual(@as(u32, 640), artwork.width);
    try std.testing.expectEqual(@as(u32, 480), artwork.height);
    try std.testing.expectEqualStrings("png-data", artwork.data);
    try std.testing.expectError(
        error.ArtworkNotFound,
        service.getArtwork(allocator, .{ .artwork_id = artwork_id + 1 }),
    );
}
