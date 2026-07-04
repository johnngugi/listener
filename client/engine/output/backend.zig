const protocol = @import("lstn_protocol");

pub const OutputBackend = struct {
    name: []const u8,
    impl: OutputImpl,
};

pub const OutputBackendBootstrap = struct {
    name: []const u8,
    init: *const fn (*OutputImpl) void,
};

pub const OutputImpl = struct {
    open: *const fn (OutputFormat) anyerror!void,
};

pub const OutputFormat = struct {
    sample_format: protocol.SampleFormat,
    sample_rate: u32,
    channels: u16,
};
