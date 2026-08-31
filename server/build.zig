const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lstn_protocol = b.dependency("lstn_protocol", .{
        .target = target,
        .optimize = optimize,
    }).module("lstn_protocol");
    const stdout = b.createModule(.{
        .root_source_file = b.path("stdout.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "listener",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addImport("lstn_protocol", lstn_protocol);
    exe.root_module.addImport("stdout", stdout);

    linkServerLibraries(exe.root_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const server_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    server_tests.root_module.addImport("lstn_protocol", lstn_protocol);
    server_tests.root_module.addImport("stdout", stdout);
    linkServerLibraries(server_tests.root_module);
    const run_server_tests = b.addRunArtifact(server_tests);

    // Keep the shared media contract independently compilable: this target
    // deliberately receives no FFmpeg include paths or linked libraries.
    const media_types_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("media/types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_media_types_tests = b.addRunArtifact(media_types_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_server_tests.step);
    test_step.dependOn(&run_media_types_tests.step);
}

fn linkServerLibraries(module: *std.Build.Module) void {
    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/lib" });
    module.linkSystemLibrary("avformat", .{});
    module.linkSystemLibrary("avcodec", .{});
    module.linkSystemLibrary("avutil", .{});
    module.linkSystemLibrary("swscale", .{});

    module.linkSystemLibrary("sqlite3", .{});

    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/lib" });
    module.linkSystemLibrary("grpc", .{});
}
