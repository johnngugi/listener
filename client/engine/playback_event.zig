pub const PlaybackEventCallback = *const fn (
    context: ?*anyopaque,
    event: u32,
) callconv(.c) void;

pub const PlaybackEvent = enum(u32) {
    ended = 1,
    failed = 2,
    discovered_service = 3,
};

pub const DiscoveredService = extern struct {
    full_name: [*]const u8,
    full_name_len: usize,
    host_target: [*]const u8,
    host_target_len: usize,
    port: u16,
};
