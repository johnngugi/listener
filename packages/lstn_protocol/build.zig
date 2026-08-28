const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protocol = b.addModule("lstn_protocol", .{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = protocol,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run LSTN protocol tests");
    test_step.dependOn(&run_tests.step);
}
