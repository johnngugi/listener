const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const macos_sdk_path = b.option(
        []const u8,
        "macos-sdk-path",
        "Path to the macOS SDK used for framework linking",
    );

    const lstn_protocol = b.dependency("lstn_protocol", .{
        .target = target,
        .optimize = optimize,
    }).module("lstn_protocol");

    const stdout = b.createModule(.{
        .root_source_file = b.path("stdout.zig"),
        .target = target,
        .optimize = optimize,
    });

    const audio_backend = b.createModule(.{
        .root_source_file = b.path("output/backend.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_backend.addImport("lstn_protocol", lstn_protocol);

    const audio_ring_buffer = b.createModule(.{
        .root_source_file = b.path("output/ring-buffer.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_ring_buffer.addImport("audio_backend", audio_backend);

    const selected_output = selectedOutputBackend(b, target, optimize, audio_backend, stdout);

    const root_module = b.createModule(.{
        .root_source_file = b.path("ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("lstn_protocol", lstn_protocol);
    root_module.addImport("audio_backend", audio_backend);
    root_module.addImport("audio_ring_buffer", audio_ring_buffer);
    root_module.addImport("selected_output", selected_output);
    root_module.addImport("stdout", stdout);

    const lib = b.addLibrary(.{
        .name = "listener_engine",
        .linkage = .dynamic,
        .root_module = root_module,
    });
    linkSelectedOutputBackend(lib, target, macos_sdk_path);

    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = clientEngineModule(
            b,
            target,
            optimize,
            lstn_protocol,
            audio_backend,
            audio_ring_buffer,
            testOutputBackend(b, target, optimize, audio_backend),
            stdout,
        ),
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

fn clientEngineModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lstn_protocol: *std.Build.Module,
    audio_backend: *std.Build.Module,
    audio_ring_buffer: *std.Build.Module,
    selected_output: *std.Build.Module,
    stdout: *std.Build.Module,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("lstn_protocol", lstn_protocol);
    module.addImport("audio_backend", audio_backend);
    module.addImport("audio_ring_buffer", audio_ring_buffer);
    module.addImport("selected_output", selected_output);
    module.addImport("stdout", stdout);
    return module;
}

fn selectedOutputBackend(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    audio_backend: *std.Build.Module,
    stdout: *std.Build.Module,
) *std.Build.Module {
    const root_source_file = switch (target.result.os.tag) {
        .macos => "output/coreaudio.zig",
        // Add Linux and Windows cases here as those backends land.
        else => std.debug.panic(
            "unsupported audio backend for target OS: {}",
            .{target.result.os.tag},
        ),
    };

    const module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("audio_backend", audio_backend);
    module.addImport("stdout", stdout);
    return module;
}

fn testOutputBackend(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    audio_backend: *std.Build.Module,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("output/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("audio_backend", audio_backend);
    return module;
}

fn linkSelectedOutputBackend(
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    macos_sdk_path: ?[]const u8,
) void {
    switch (target.result.os.tag) {
        .macos => {
            // Native Assets rewrites the dylib's install name while bundling.
            // Reserve enough Mach-O header space for the rewritten paths.
            lib.headerpad_max_install_names = true;
            if (macos_sdk_path) |sdk_path| {
                lib.root_module.addFrameworkPath(.{
                    .cwd_relative = std.fs.path.join(
                        lib.step.owner.allocator,
                        &.{ sdk_path, "System/Library/Frameworks" },
                    ) catch @panic("out of memory"),
                });
                lib.root_module.addLibraryPath(.{
                    .cwd_relative = std.fs.path.join(
                        lib.step.owner.allocator,
                        &.{ sdk_path, "usr/lib" },
                    ) catch @panic("out of memory"),
                });
            }
            lib.root_module.linkFramework("CoreAudio", .{});
            lib.root_module.linkFramework("CoreFoundation", .{});
            lib.root_module.linkFramework("AudioUnit", .{});
        },
        else => unreachable,
    }
}
