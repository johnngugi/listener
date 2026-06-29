test "server modules are included from the server source root" {
    _ = @import("control.zig");
    _ = @import("playback.zig");
    _ = @import("lstn/protocol.zig");
    _ = @import("lstn/request.zig");
    _ = @import("lstn/connection.zig");
    _ = @import("grpc/codec.zig");
    _ = @import("grpc/server.zig");
}
