const std = @import("std");
const backend = @import("audio_backend");

pub const Backend = backend.OutputBackendBootstrap{
    .name = "TestOutput",
    .init = &create,
};

const State = struct {
    mutex: std.atomic.Mutex = .unlocked,
    allocator: std.mem.Allocator,
    source: ?backend.OutputSource = null,
    output_format: ?backend.OutputFormat = null,
    captured: std.ArrayList(u8) = .empty,
    render_thread: ?std.Thread = null,
    started: bool = false,
    stop_requested: bool = false,
    fail_next_open: bool = false,
    selected_device_id: ?[]u8 = null,
    configuration: backend.OutputConfiguration = .{},
};

const vtable = backend.VTable{
    .enumerate_devices = &enumerateDevices,
    .select_device = &selectDevice,
    .configure = &configure,
    .open = &open,
    .start = &start,
    .stop = &stop,
    .pause_playback = &pausePlayback,
    .resume_playback = &resumePlayback,
    .close = &close,
    .deinit = &deinit,
};

pub fn failNextOpen(output: *backend.OutputBackend) void {
    const state = stateFromOutput(output);
    lock(state);
    defer unlock(state);
    state.fail_next_open = true;
}

pub fn capturedBytes(output: *backend.OutputBackend, allocator: std.mem.Allocator) ![]u8 {
    const state = stateFromOutput(output);
    lock(state);
    defer unlock(state);

    return try allocator.dupe(u8, state.captured.items);
}

pub fn isStarted(output: *backend.OutputBackend) bool {
    const state = stateFromOutput(output);
    lock(state);
    defer unlock(state);

    return state.started;
}

pub fn waitForCapturedBytes(
    output: *backend.OutputBackend,
    expected_len: usize,
    max_yields: usize,
) !void {
    const state = stateFromOutput(output);
    var remaining = max_yields;
    while (remaining > 0) : (remaining -= 1) {
        lock(state);
        const enough = state.captured.items.len >= expected_len;
        unlock(state);

        if (enough) return;
        std.Thread.yield() catch {};
    }

    return error.Timeout;
}

fn create(allocator: std.mem.Allocator) !backend.OutputBackend {
    const state = try allocator.create(State);
    state.* = .{ .allocator = allocator };
    return .{
        .name = Backend.name,
        .context = state,
        .vtable = &vtable,
    };
}

fn enumerateDevices(_: *anyopaque, allocator: std.mem.Allocator) ![]backend.OutputDevice {
    const devices = try allocator.alloc(backend.OutputDevice, 1);
    errdefer allocator.free(devices);

    const id = try allocator.dupe(u8, "test-output");
    errdefer allocator.free(id);
    const name = try allocator.dupe(u8, "Test Output");
    errdefer allocator.free(name);

    devices[0] = .{
        .id = id,
        .name = name,
        .is_default = true,
        .capabilities = .{ .exclusive_mode = true },
    };
    return devices;
}

fn configure(
    context: *anyopaque,
    configuration: backend.OutputConfiguration,
) !void {
    const state = stateFromContext(context);
    lock(state);
    defer unlock(state);
    if (state.source != null) return error.AlreadyOpen;
    state.configuration = configuration;
}

fn selectDevice(context: *anyopaque, device_id: ?[]const u8) !void {
    const state = stateFromContext(context);
    if (device_id) |id| {
        if (!std.mem.eql(u8, id, "test-output")) return error.OutputDeviceNotFound;
    }

    const selected = if (device_id) |id|
        try state.allocator.dupe(u8, id)
    else
        null;

    lock(state);
    defer unlock(state);
    if (state.selected_device_id) |previous| state.allocator.free(previous);
    state.selected_device_id = selected;
}

fn open(
    context: *anyopaque,
    output_format: backend.OutputFormat,
    source: backend.OutputSource,
) !void {
    const state = stateFromContext(context);
    lock(state);
    defer unlock(state);

    if (state.fail_next_open) {
        state.fail_next_open = false;
        return error.TestOutputOpenFailed;
    }
    state.output_format = output_format;
    state.source = source;
    state.stop_requested = false;
}

fn start(context: *anyopaque) !void {
    const state = stateFromContext(context);
    lock(state);
    defer unlock(state);

    if (state.source == null) return error.NotOpen;
    if (state.started) return;

    state.stop_requested = false;
    state.started = true;
    state.render_thread = try std.Thread.spawn(.{}, renderLoop, .{state});
}

fn stop(context: *anyopaque) !void {
    const state = stateFromContext(context);
    var thread: ?std.Thread = null;

    lock(state);
    state.stop_requested = true;
    thread = state.render_thread;
    state.render_thread = null;
    state.started = false;
    unlock(state);

    if (thread) |joined_thread| {
        joined_thread.join();
    }
}

fn pausePlayback(context: *anyopaque) !void {
    try stop(context);
}

fn resumePlayback(context: *anyopaque) !void {
    try start(context);
}

fn close(context: *anyopaque) void {
    const state = stateFromContext(context);
    stop(context) catch {};

    lock(state);
    defer unlock(state);

    state.source = null;
    state.output_format = null;
    state.stop_requested = false;
}

fn deinit(context: *anyopaque) void {
    const state = stateFromContext(context);
    const allocator = state.allocator;
    close(context);
    if (state.selected_device_id) |selected| allocator.free(selected);
    state.captured.deinit(allocator);
    allocator.destroy(state);
}

fn renderLoop(state: *State) void {
    var scratch: [1024]u8 = undefined;

    while (true) {
        lock(state);
        const should_stop = state.stop_requested;
        const maybe_source = state.source;
        unlock(state);

        if (should_stop) return;
        const source = maybe_source orelse return;

        const max_frames = scratch.len / source.frame_bytes;
        const bytes = source.readAvailable(
            source.context,
            max_frames,
            scratch[0 .. max_frames * source.frame_bytes],
        );

        if (bytes.len > 0) {
            lock(state);
            state.captured.appendSlice(state.allocator, bytes) catch {
                state.stop_requested = true;
            };
            unlock(state);
        } else {
            std.Thread.yield() catch {};
        }
    }
}

fn stateFromOutput(output: *backend.OutputBackend) *State {
    return stateFromContext(output.context);
}

fn stateFromContext(context: *anyopaque) *State {
    return @ptrCast(@alignCast(context));
}

fn lock(state: *State) void {
    while (!state.mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

fn unlock(state: *State) void {
    state.mutex.unlock();
}

test "backend instances own independent state" {
    const allocator = std.testing.allocator;
    var first = try create(allocator);
    defer first.deinit();
    var second = try create(allocator);
    defer second.deinit();

    const FakeSource = struct {
        fn readAvailable(_: *anyopaque, _: usize, output_buffer: []u8) []u8 {
            return output_buffer[0..0];
        }
    };
    var source_context: u8 = 0;
    const source = backend.OutputSource{
        .context = &source_context,
        .frame_bytes = 4,
        .readAvailable = &FakeSource.readAvailable,
    };
    const output_format = backend.OutputFormat{
        .sample_format = .pcm_s16le,
        .sample_rate = 48_000,
        .channels = 2,
    };

    failNextOpen(&first);
    try std.testing.expectError(
        error.TestOutputOpenFailed,
        first.open(output_format, source),
    );
    try second.open(output_format, source);
}

test "enumerateDevices returns caller-owned portable devices" {
    const allocator = std.testing.allocator;
    var output = try create(allocator);
    defer output.deinit();

    const devices = try output.enumerateDevices(allocator);
    defer backend.deinitOutputDevices(allocator, devices);

    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("test-output", devices[0].id);
    try std.testing.expectEqualStrings("Test Output", devices[0].name);
    try std.testing.expect(devices[0].is_default);
    try std.testing.expect(devices[0].capabilities.exclusive_mode);
}

test "selectDevice validates and retains an opaque device ID" {
    const allocator = std.testing.allocator;
    var output = try create(allocator);
    defer output.deinit();

    try std.testing.expectError(
        error.OutputDeviceNotFound,
        output.selectDevice("missing-output"),
    );
    try output.selectDevice("test-output");
    try output.selectDevice(null);
}

test "configure stores portable output configuration while closed" {
    const allocator = std.testing.allocator;
    var output = try create(allocator);
    defer output.deinit();

    try output.configure(.{ .exclusive_mode = true });
    try std.testing.expect(stateFromOutput(&output).configuration.exclusive_mode);
}
