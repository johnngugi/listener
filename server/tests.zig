test "server modules are included from the server source root" {
    _ = @import("control.zig");
    _ = @import("playback.zig");
    _ = @import("lstn_protocol");
    _ = @import("lstn/request.zig");
    _ = @import("lstn/connection.zig");
    _ = @import("grpc/codec.zig");
    _ = @import("grpc/server.zig");
    _ = @import("library/database.zig");
    _ = @import("library/sqlite.zig");
    _ = @import("library/scan.zig");
    _ = @import("library/service.zig");
    _ = @import("library/track_info.zig");
    _ = @import("media/decoder.zig");
    _ = @import("media/artwork.zig");
    _ = @import("media/flac/metadata.zig");
    _ = @import("media/types.zig");
}
