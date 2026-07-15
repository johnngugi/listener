const std = @import("std");
const database = @import("database.zig");

pub const service_full_name = "listener.control.v1.ListenerLibrary";

pub const Method = enum {
    list_tracks,

    pub fn fullName(self: Method) []const u8 {
        return switch (self) {
            .list_tracks => "/" ++ service_full_name ++ "/ListTracks",
        };
    }
};

pub const default_page_size: u32 = 100;
pub const max_page_size: u32 = 500;

pub const ListTracksRequest = struct {
    page_size: u32 = 0,
    page_token: []const u8 = "",
};

pub const Error = database.Error || error{
    InvalidPageSize,
    InvalidPageToken,
};

pub const Service = struct {
    db: database.Database,

    pub fn init(db: database.Database) Service {
        return .{ .db = db };
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
}

test "page tokens are positive database cursors" {
    try std.testing.expectEqual(@as(i64, 0), try decodePageToken(""));
    try std.testing.expectEqual(@as(i64, 42), try decodePageToken("42"));
    try std.testing.expectError(error.InvalidPageToken, decodePageToken("0"));
    try std.testing.expectError(error.InvalidPageToken, decodePageToken("abc"));
}
