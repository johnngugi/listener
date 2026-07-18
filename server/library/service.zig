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

        const after_id = try decodePageToken(request.page_token);
        return self.db.listTracks(allocator, after_id, limit);
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
};

fn decodePageToken(token: []const u8) error{InvalidPageToken}!i64 {
    if (token.len == 0) return 0;
    const value = std.fmt.parseInt(i64, token, 10) catch
        return error.InvalidPageToken;
    if (value <= 0) return error.InvalidPageToken;
    return value;
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

test "page tokens are positive database cursors" {
    try std.testing.expectEqual(@as(i64, 0), try decodePageToken(""));
    try std.testing.expectEqual(@as(i64, 42), try decodePageToken("42"));
    try std.testing.expectError(error.InvalidPageToken, decodePageToken("0"));
    try std.testing.expectError(error.InvalidPageToken, decodePageToken("abc"));
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
