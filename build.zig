const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "listener",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/include" });
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/lib" });
    exe.root_module.linkSystemLibrary("avformat", .{});
    exe.root_module.linkSystemLibrary("avcodec", .{});
    exe.root_module.linkSystemLibrary("avutil", .{});
    exe.root_module.linkSystemLibrary("swresample", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const protocol_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/protocol.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_protocol_tests = b.addRunArtifact(protocol_tests);

    const request_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/request.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_request_tests = b.addRunArtifact(request_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_protocol_tests.step);
    test_step.dependOn(&run_request_tests.step);
}
