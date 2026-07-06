const std = @import("std");
const backend = @import("audio_backend");

pub const Backend = backend.OutputBackendBootstrap{
    .name = "TestOutput",
    .init = &init,
};

const State = struct {
    mutex: std.atomic.Mutex = .unlocked,
    allocator: ?std.mem.Allocator = null,
    source: ?backend.OutputSource = null,
    output_format: ?backend.OutputFormat = null,
    captured: std.ArrayList(u8) = .empty,
    render_thread: ?std.Thread = null,
    started: bool = false,
    stop_requested: bool = false,
};

var state: State = .{};

pub fn reset(allocator: std.mem.Allocator) void {
    close();
    lock();
    defer unlock();

    state.captured.deinit(allocator);
    state.allocator = allocator;
    state.source = null;
    state.output_format = null;
    state.captured = .empty;
    state.render_thread = null;
    state.started = false;
    state.stop_requested = false;
}

pub fn capturedBytes(allocator: std.mem.Allocator) ![]u8 {
    lock();
    defer unlock();

    return try allocator.dupe(u8, state.captured.items);
}

pub fn waitForCapturedBytes(expected_len: usize, max_yields: usize) !void {
    var remaining = max_yields;
    while (remaining > 0) : (remaining -= 1) {
        lock();
        const enough = state.captured.items.len >= expected_len;
        unlock();

        if (enough) return;
        std.Thread.yield() catch {};
    }

    return error.Timeout;
}

fn init(impl: *backend.OutputImpl) void {
    impl.* = .{
        .open = &open,
        .start = &start,
        .stop = &stop,
        .close = &close,
    };
}

fn open(output_format: backend.OutputFormat, source: backend.OutputSource) !void {
    lock();
    defer unlock();

    if (state.allocator == null) return error.TestBackendNotInitialized;
    state.output_format = output_format;
    state.source = source;
    state.stop_requested = false;
}

fn start() !void {
    lock();
    defer unlock();

    if (state.source == null) return error.NotOpen;
    if (state.started) return;

    state.started = true;
    state.render_thread = try std.Thread.spawn(.{}, renderLoop, .{});
}

fn stop() !void {
    var thread: ?std.Thread = null;

    lock();
    state.stop_requested = true;
    thread = state.render_thread;
    state.render_thread = null;
    state.started = false;
    unlock();

    if (thread) |joined_thread| {
        joined_thread.join();
    }
}

fn close() void {
    stop() catch {};

    lock();
    defer unlock();

    state.source = null;
    state.output_format = null;
    state.stop_requested = false;
}

fn renderLoop() void {
    var scratch: [1024]u8 = undefined;

    while (true) {
        lock();
        const should_stop = state.stop_requested;
        const maybe_source = state.source;
        unlock();

        if (should_stop) return;
        const source = maybe_source orelse return;

        const max_frames = scratch.len / source.frame_bytes;
        const bytes = source.readAvailable(
            source.context,
            max_frames,
            scratch[0 .. max_frames * source.frame_bytes],
        );

        if (bytes.len > 0) {
            lock();
            const allocator = state.allocator orelse {
                unlock();
                return;
            };
            state.captured.appendSlice(allocator, bytes) catch {
                state.stop_requested = true;
            };
            unlock();
        } else {
            std.Thread.yield() catch {};
        }
    }
}

fn lock() void {
    while (!state.mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

fn unlock() void {
    state.mutex.unlock();
}
