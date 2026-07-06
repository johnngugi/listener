const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lstn_protocol = b.createModule(.{
        .root_source_file = b.path("shared/lstn/protocol.zig"),
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
    client_engine.addImport("selected_output", selected_output);

    const server = b.createModule(.{
        .root_source_file = b.path("server/module.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    server.addImport("lstn_protocol", lstn_protocol);

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
    linkServerLibraries(integration_tests.root_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run repo-level integration tests");
    test_step.dependOn(&run_integration_tests.step);
}

fn linkServerLibraries(module: *std.Build.Module) void {
    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/ffmpeg/lib" });
    module.linkSystemLibrary("avformat", .{});
    module.linkSystemLibrary("avcodec", .{});
    module.linkSystemLibrary("avutil", .{});
    module.linkSystemLibrary("swresample", .{});

    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/include" });
    module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/grpc/lib" });
    module.linkSystemLibrary("grpc", .{});
}
