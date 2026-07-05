const std = @import("std");
const Mutex = std.Io.Mutex;
const Condition = std.Io.Condition;
const audio_backend = @import("audio_backend");

pub const PcmRingBuffer = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    frame_bytes: usize,
    capacity_frames: usize,
    read_frame: usize,
    write_frame: usize,
    filled_frames: usize,
    total_frames_written: u64,
    total_frames_read: u64,
    end_of_stream: bool,

    pub fn new(
        allocator: std.mem.Allocator,
        output_format: audio_backend.OutputFormat,
        capacity_frames: usize,
    ) RingBufferError!PcmRingBuffer {
        if (capacity_frames == 0) {
            return RingBufferError.ZeroCapacity;
        }

        const sample_format_bytes = try audio_backend.sample_format_bytes(output_format.sample_format);
        const frame_bytes = output_format.channels * sample_format_bytes;
        const total_bytes = capacity_frames * frame_bytes;

        var bytes = try std.ArrayList(u8).initCapacity(allocator, total_bytes);
        try bytes.resize(allocator, total_bytes);

        return .{
            .allocator = allocator,
            .bytes = bytes,
            .frame_bytes = frame_bytes,
            .capacity_frames = capacity_frames,
            .read_frame = 0,
            .write_frame = 0,
            .filled_frames = 0,
            .total_frames_written = 0,
            .total_frames_read = 0,
            .end_of_stream = false,
        };
    }

    pub fn deinit(self: *PcmRingBuffer) void {
        self.bytes.deinit(self.allocator);
    }

    pub fn write_frames(self: *PcmRingBuffer, bytes: []const u8) RingBufferError!usize {
        try self.require_aligned(bytes.len, null);

        const requested_frames = bytes.len / self.frame_bytes;
        const frames_to_write = @min(requested_frames, self.writeable_frames());
        const bytes_to_write = frames_to_write * self.frame_bytes;

        self.copy_into_ring(bytes[0..bytes_to_write]);
        self.filled_frames += frames_to_write;
        self.total_frames_written += @intCast(frames_to_write);

        return frames_to_write;
    }

    pub fn read_frames(self: *PcmRingBuffer, max_frames: usize, output_buffer: []u8) []u8 {
        const output_frames = output_buffer.len / self.frame_bytes;
        const frames_to_read = @min(max_frames, @min(output_frames, self.readable_frames()));
        const bytes_to_read = frames_to_read * self.frame_bytes;

        const out_slice = output_buffer[0..bytes_to_read];
        self.copy_out_of_ring(out_slice);

        self.filled_frames -= frames_to_read;
        self.total_frames_read += @intCast(frames_to_read);

        return out_slice;
    }

    pub fn copy_into_ring(self: *PcmRingBuffer, src: []const u8) void {
        var copied: usize = 0;

        while (copied < src.len) {
            const write_offset = self.write_frame * self.frame_bytes;
            const contiguous_frames = self.capacity_frames - self.write_frame;
            const contiguous_bytes = contiguous_frames * self.frame_bytes;
            const copy_len = @min(src.len - copied, contiguous_bytes);

            @memcpy(
                self.bytes.items[write_offset .. write_offset + copy_len],
                src[copied .. copied + copy_len],
            );

            copied += copy_len;
            self.write_frame =
                (self.write_frame + (copy_len / self.frame_bytes)) % self.capacity_frames;
        }
    }

    pub fn copy_out_of_ring(self: *PcmRingBuffer, dst: []u8) void {
        var copied: usize = 0;

        while (copied < dst.len) {
            const read_offset = self.read_frame * self.frame_bytes;
            const contiguous_frames = self.capacity_frames - self.read_frame;
            const contiguous_bytes = contiguous_frames * self.frame_bytes;
            const copy_len = @min(dst.len - copied, contiguous_bytes);

            @memcpy(
                dst[copied .. copied + copy_len],
                self.bytes.items[read_offset .. read_offset + copy_len],
            );

            copied += copy_len;
            self.read_frame =
                (self.read_frame + (copy_len / self.frame_bytes)) % self.capacity_frames;
        }
    }

    pub fn require_aligned(self: *PcmRingBuffer, byte_len: usize, error_detail: ?*MisalignedByteLengthDetails) RingBufferError!void {
        if (byte_len % self.frame_bytes != 0) {
            if (error_detail) |details| {
                details.* = .{
                    .frame_bytes = self.frame_bytes,
                    .actual = byte_len,
                };
            }

            return RingBufferError.MisalignedByteLength;
        }
    }

    pub fn capacity(self: *PcmRingBuffer) usize {
        return self.capacity_frames;
    }

    pub fn readable_frames(self: *PcmRingBuffer) usize {
        return self.filled_frames;
    }

    pub fn writeable_frames(self: *PcmRingBuffer) usize {
        return self.capacity_frames - self.filled_frames;
    }

    pub fn total_frames(self: *PcmRingBuffer) u64 {
        return self.total_frames_written;
    }

    pub fn frames_read(self: *PcmRingBuffer) u64 {
        return self.total_frames_read;
    }

    pub fn mark_end_of_stream(self: *PcmRingBuffer) void {
        self.end_of_stream = true;
    }

    pub fn is_drained(self: *PcmRingBuffer) bool {
        return self.end_of_stream and self.filled_frames == 0;
    }
};

pub const RingBufferError = error{
    OutOfMemory,
    ZeroCapacity,
    MisalignedByteLength,
    UnsupportedSampleFormat,
};

pub const MisalignedByteLengthDetails = struct {
    frame_bytes: usize,
    actual: usize,
};

const SharedRingState = struct {
    ring: PcmRingBuffer,
    stopped: bool,
    paused: bool,
};

pub const SharedPcmRingBuffer = struct {
    inner: Mutex = .init,
    changed: Condition = .init,
    state: SharedRingState,
    io: std.Io,

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        output_format: audio_backend.OutputFormat,
        capacity_frames: usize,
    ) RingBufferError!SharedPcmRingBuffer {
        return .{
            .state = .{
                .ring = try PcmRingBuffer.new(allocator, output_format, capacity_frames),
                .stopped = false,
                .paused = false,
            },
            .io = io,
        };
    }

    pub fn deinit(self: *SharedPcmRingBuffer) void {
        self.state.ring.deinit();
    }

    pub fn outputSource(self: *SharedPcmRingBuffer) audio_backend.OutputSource {
        return .{
            .context = self,
            .frame_bytes = self.state.ring.frame_bytes,
            .readAvailable = &readAvailableForOutput,
        };
    }

    pub fn writeBlocking(self: *SharedPcmRingBuffer, bytes: []const u8) !usize {
        return self.writeBlockingUntil(bytes, alwaysFalse);
    }

    pub fn writeBlockingUntil(self: *SharedPcmRingBuffer, bytes: []const u8, should_stop: *const fn () bool) !usize {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        const frame_bytes = self.state.ring.frame_bytes;

        if (bytes.len % frame_bytes != 0) {
            return error.MisalignedByteLength;
        }

        while (self.state.ring.writeable_frames() == 0 and
            !self.state.stopped and
            !self.state.paused and
            !should_stop())
        {
            self.changed.wait(self.io, &self.inner) catch |err| switch (err) {
                error.TimeOut => {},
                else => return err,
            };
        }

        if (self.state.stopped or should_stop()) {
            return 0;
        }

        if (self.state.paused) {
            return 0;
        }

        const written = try self.state.ring.write_frames(bytes);
        self.changed.broadcast(self.io);

        return written;
    }

    pub fn readBlocking(self: *SharedPcmRingBuffer, max_frames: usize, output_buffer: []u8) ![]u8 {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        while (self.state.ring.readable_frames() == 0 and
            !self.state.ring.is_drained() and
            !self.state.stopped)
        {
            try self.changed.wait(self.io, &self.inner);
        }

        const bytes = self.state.ring.read_frames(max_frames, output_buffer);
        self.changed.broadcast(self.io);

        return bytes;
    }

    pub fn readBlockingFullOrTerminal(self: *SharedPcmRingBuffer, max_frames: usize, output_buffer: []u8) ![]u8 {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        while (self.state.ring.readable_frames() < max_frames and
            !self.state.ring.end_of_stream and
            !self.state.stopped)
        {
            try self.changed.wait(self.io, &self.inner);
        }

        const bytes = self.state.ring.read_frames(max_frames, output_buffer);
        self.changed.broadcast(self.io);

        return bytes;
    }

    pub fn readAvailable(self: *SharedPcmRingBuffer, max_frames: usize, output_buffer: []u8) []u8 {
        if (!self.inner.tryLock()) {
            return output_buffer[0..0];
        }
        defer self.inner.unlock(self.io);

        const bytes = self.state.ring.read_frames(max_frames, output_buffer);
        self.changed.broadcast(self.io);

        return bytes;
    }

    pub fn markEndOfStream(self: *SharedPcmRingBuffer) !void {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        self.state.ring.markEndOfStream();
        self.changed.broadcast(self.io);
    }

    pub fn stop(self: *SharedPcmRingBuffer) !void {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        self.state.stopped = true;
        self.changed.broadcast(self.io);
    }

    pub fn setPaused(self: *SharedPcmRingBuffer, paused: bool) !void {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        self.state.paused = paused;
        self.changed.broadcast(self.io);
    }

    pub fn isPaused(self: *SharedPcmRingBuffer) !bool {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.paused;
    }

    pub fn readableFrames(self: *SharedPcmRingBuffer) !usize {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.ring.readable_frames();
    }

    pub fn writableFrames(self: *SharedPcmRingBuffer) !usize {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.ring.writeable_frames();
    }

    pub fn capacityFrames(self: *SharedPcmRingBuffer) !usize {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.ring.capacity();
    }

    pub fn framesRead(self: *SharedPcmRingBuffer) !u64 {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.ring.frames_read();
    }

    pub fn isDrained(self: *SharedPcmRingBuffer) !bool {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.ring.is_drained();
    }

    pub fn isStopped(self: *SharedPcmRingBuffer) !bool {
        try self.inner.lock(self.io);
        defer self.inner.unlock(self.io);

        return self.state.stopped;
    }

    fn alwaysFalse() bool {
        return false;
    }

    fn readAvailableForOutput(
        context: *anyopaque,
        max_frames: usize,
        output_buffer: []u8,
    ) []u8 {
        const self: *SharedPcmRingBuffer = @ptrCast(@alignCast(context));
        return self.readAvailable(max_frames, output_buffer);
    }
};
