const std = @import("std");

const MediaBackend = enum {
    ffmpeg,
    native,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
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
        .root_source_file = b.path("client/engine/stdout.zig"),
        .target = target,
        .optimize = optimize,
    });

    const audio_backend = b.createModule(.{
        .root_source_file = b.path("client/engine/output/backend.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_backend.addImport("lstn_protocol", lstn_protocol);

    const audio_ring_buffer = b.createModule(.{
        .root_source_file = b.path("client/engine/output/ring-buffer.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_ring_buffer.addImport("audio_backend", audio_backend);

    const audio_gain = b.createModule(.{
        .root_source_file = b.path("client/engine/output/gain.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_gain.addImport("audio_backend", audio_backend);

    const selected_output = b.createModule(.{
        .root_source_file = b.path("client/engine/output/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    selected_output.addImport("audio_backend", audio_backend);

    const client_engine = b.createModule(.{
        .root_source_file = b.path("client/engine/ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_engine.addImport("lstn_protocol", lstn_protocol);
    client_engine.addImport("audio_backend", audio_backend);
    client_engine.addImport("audio_ring_buffer", audio_ring_buffer);
    client_engine.addImport("audio_gain", audio_gain);
    client_engine.addImport("selected_output", selected_output);
    client_engine.addImport("stdout", stdout);

    const server = b.createModule(.{
        .root_source_file = b.path("server/module.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    server.addImport("lstn_protocol", lstn_protocol);
    server.addOptions("media_backend_options", media_backend_options);

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    integration_tests.root_module.addImport("client_engine", client_engine);
    integration_tests.root_module.addImport("selected_output", selected_output);
    integration_tests.root_module.addImport("server", server);
    linkServerLibraries(integration_tests.root_module, media_backend);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run repo-level integration tests");
    test_step.dependOn(&run_integration_tests.step);
}

fn linkServerLibraries(module: *std.Build.Module, media_backend: MediaBackend) void {
    switch (media_backend) {
        .ffmpeg => {
            module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/include" });
            module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/lib" });
            module.linkSystemLibrary("avformat", .{});
            module.linkSystemLibrary("avcodec", .{});
            module.linkSystemLibrary("avutil", .{});
            module.linkSystemLibrary("swscale", .{});
        },
        .native => module.linkFramework("AudioToolbox", .{}),
    }

    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("CoreGraphics", .{});
    module.linkFramework("ImageIO", .{});

    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/lib" });
    module.linkSystemLibrary("grpc", .{});
}
