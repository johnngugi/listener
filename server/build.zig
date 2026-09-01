const std = @import("std");

const MediaBackend = enum {
    ffmpeg,
    native,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    requireSupportedTarget(target);

    const media_backend = b.option(
        MediaBackend,
        "media-backend",
        "Select the temporary macOS decoder backend (ffmpeg or native)",
    ) orelse .native;
    const media_backend_options = b.addOptions();
    media_backend_options.addOption(MediaBackend, "media_backend", media_backend);
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
    exe.root_module.addOptions("media_backend_options", media_backend_options);

    linkServerLibraries(exe.root_module, target, media_backend);

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
    server_tests.root_module.addOptions("media_backend_options", media_backend_options);
    linkServerLibraries(server_tests.root_module, target, media_backend);
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

    // The FLAC metadata parser is also platform-neutral and must remain
    // independently testable without FFmpeg or Apple framework linkage.
    const flac_metadata_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("flac_metadata_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_flac_metadata_tests = b.addRunArtifact(flac_metadata_tests);

    // Artwork has its own native backend test target so validation and
    // normalization remain demonstrably independent of FFmpeg.
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

    // Exercise the AudioToolbox backend directly, independently of the selected
    // production backend.
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

    // Run both temporary implementations against the same fixtures. This target
    // deliberately imports each backend directly rather than using the facade.
    const decoder_parity_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("decoder_parity_tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    linkDecoderBackends(decoder_parity_tests.root_module, target);
    const run_decoder_parity_tests = b.addRunArtifact(decoder_parity_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_server_tests.step);
    test_step.dependOn(&run_media_types_tests.step);
    test_step.dependOn(&run_flac_metadata_tests.step);
    test_step.dependOn(&run_artwork_tests.step);
    test_step.dependOn(&run_native_decoder_tests.step);
    test_step.dependOn(&run_decoder_parity_tests.step);
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
    media_backend: MediaBackend,
) void {
    linkArtworkBackend(module, target);

    linkDecoderBackend(module, target, media_backend);

    module.linkSystemLibrary("sqlite3", .{});

    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/lib" });
    module.linkSystemLibrary("grpc", .{});
}

fn linkDecoderBackend(
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    media_backend: MediaBackend,
) void {
    switch (target.result.os.tag) {
        .macos => switch (media_backend) {
            .ffmpeg => linkFfmpegBackend(module),
            .native => linkNativeDecoderBackend(module, target),
        },
        else => unreachable,
    }
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

fn linkDecoderBackends(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    linkNativeDecoderBackend(module, target);
    linkFfmpegBackend(module);
}

fn linkFfmpegBackend(module: *std.Build.Module) void {
    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/lib" });
    module.linkSystemLibrary("avformat", .{});
    module.linkSystemLibrary("avcodec", .{});
    module.linkSystemLibrary("avutil", .{});
    module.linkSystemLibrary("swscale", .{});
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
