const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lstn_protocol = b.createModule(.{
        .root_source_file = b.path("../../shared/lstn/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "listener_engine",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("ffi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addImport("lstn_protocol", lstn_protocol);

    b.installArtifact(lib);
}
