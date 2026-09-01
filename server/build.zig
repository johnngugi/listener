const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    requireSupportedTarget(target);

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
    linkServerLibraries(exe.root_module, target);

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
    linkServerLibraries(server_tests.root_module, target);
    const run_server_tests = b.addRunArtifact(server_tests);

    // Keep the shared media contract independently compilable.
    const media_types_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("media/types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_media_types_tests = b.addRunArtifact(media_types_tests);

    // The FLAC metadata parser is also platform-neutral and must remain
    // independently testable without Apple framework linkage.
    const flac_metadata_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("flac_metadata_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_flac_metadata_tests = b.addRunArtifact(flac_metadata_tests);

    // Artwork has its own native backend test target.
    const artwork_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("artwork_tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    linkArtworkBackend(artwork_tests.root_module, target);
    const run_artwork_tests = b.addRunArtifact(artwork_tests);

    // Exercise the AudioToolbox backend directly.
    const native_decoder_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native_decoder_tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    linkNativeDecoderBackend(native_decoder_tests.root_module, target);
    const run_native_decoder_tests = b.addRunArtifact(native_decoder_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_server_tests.step);
    test_step.dependOn(&run_media_types_tests.step);
    test_step.dependOn(&run_flac_metadata_tests.step);
    test_step.dependOn(&run_artwork_tests.step);
    test_step.dependOn(&run_native_decoder_tests.step);
}

fn requireSupportedTarget(target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .macos => {},
        else => std.debug.panic(
            "unsupported server media target OS: {s}; only macOS is implemented",
            .{@tagName(target.result.os.tag)},
        ),
    }
}

fn linkServerLibraries(
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    linkArtworkBackend(module, target);
    linkNativeDecoderBackend(module, target);

    module.linkSystemLibrary("sqlite3", .{});

    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/lib" });
    module.linkSystemLibrary("grpc", .{});
}

fn linkNativeDecoderBackend(
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    switch (target.result.os.tag) {
        .macos => {
            module.linkFramework("AudioToolbox", .{});
            module.linkFramework("CoreFoundation", .{});
        },
        else => unreachable,
    }
}

fn linkArtworkBackend(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .macos => {
            module.linkFramework("CoreFoundation", .{});
            module.linkFramework("CoreGraphics", .{});
            module.linkFramework("ImageIO", .{});
        },
        else => unreachable,
    }
}
