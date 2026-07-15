const std = @import("std");

const control = @import("../control.zig");
const database = @import("../library/database.zig");
const library = @import("../library/service.zig");

pub const DecodeError = error{
    EmptyRequiredString,
    InvalidFieldNumber,
    InvalidMethod,
    InvalidInteger,
    InvalidString,
    InvalidWireType,
    MalformedVarint,
    TruncatedMessage,
    UnsupportedWireType,
};

const max_control_string_len = 4096;

pub const Request = union(enum) {
    command: control.Command,
    watch: control.Target,
    list_tracks: library.ListTracksRequest,
};

pub fn encodeResponse(
    allocator: std.mem.Allocator,
    response: control.Response,
) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    switch (response) {
        .start => |start| {
            try appendString(&out, allocator, 1, start.playback_id);
            try appendEnum(&out, allocator, 2, start.state);
        },
        .command => |command| {
            try appendString(&out, allocator, 1, command.playback_id);
            try appendEnum(&out, allocator, 2, command.state);
        },
        .status => |status| {
            try appendString(&out, allocator, 1, status.playback_id);
            try appendEnum(&out, allocator, 2, status.state);
            try appendString(&out, allocator, 3, status.media_path);
            try appendUint64(&out, allocator, 4, status.current_frame);
            try appendUint64(&out, allocator, 5, status.generation_id);
        },
    }

    return out.toOwnedSlice(allocator);
}

pub fn encodeListTracksResponse(
    allocator: std.mem.Allocator,
    page: database.TrackPage,
) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (page.tracks) |track| {
        var encoded_track: std.ArrayList(u8) = .empty;
        defer encoded_track.deinit(allocator);

        try appendInt64(&encoded_track, allocator, 1, track.id);
        try appendString(&encoded_track, allocator, 2, track.path);
        try appendUint64(&encoded_track, allocator, 3, track.size);
        try appendInt64(&encoded_track, allocator, 4, track.modified_ns);
        try appendMessage(&out, allocator, 1, encoded_track.items);
    }

    if (page.has_more and page.tracks.len != 0) {
        const token = try std.fmt.allocPrint(
            allocator,
            "{d}",
            .{page.tracks[page.tracks.len - 1].id},
        );
        defer allocator.free(token);
        try appendString(&out, allocator, 2, token);
    }
    try appendUint64(&out, allocator, 3, page.total_size);

    return out.toOwnedSlice(allocator);
}

pub fn decodeRequest(method: []const u8, message: []const u8) DecodeError!Request {
    if (std.mem.eql(u8, method, library.Method.list_tracks.fullName())) {
        return .{ .list_tracks = try decodeListTracks(message) };
    }
    if (std.mem.eql(u8, method, control.Method.start.fullName())) {
        return .{ .command = .{ .start = try decodeStart(message) } };
    }
    if (std.mem.eql(u8, method, control.Method.stop.fullName())) {
        return .{ .command = .{ .stop = try decodeTarget(message) } };
    }
    if (std.mem.eql(u8, method, control.Method.pause.fullName())) {
        return .{ .command = .{ .pause = try decodeTarget(message) } };
    }
    if (std.mem.eql(u8, method, control.Method.resume_playback.fullName())) {
        return .{ .command = .{ .resume_playback = try decodeTarget(message) } };
    }
    if (std.mem.eql(u8, method, control.Method.seek.fullName())) {
        return .{ .command = .{ .seek = try decodeSeek(message) } };
    }
    if (std.mem.eql(u8, method, control.Method.status.fullName())) {
        return .{ .command = .{ .status = try decodeTarget(message) } };
    }
    if (std.mem.eql(u8, method, control.Method.watch.fullName())) {
        return .{ .watch = try decodeTarget(message) };
    }

    return error.InvalidMethod;
}

fn appendMessage(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_number: u32,
    value: []const u8,
) std.mem.Allocator.Error!void {
    try appendString(out, allocator, field_number, value);
}

fn appendString(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_number: u32,
    value: []const u8,
) std.mem.Allocator.Error!void {
    try appendKey(out, allocator, field_number, .length_delimited);
    try appendVarint(out, allocator, value.len);
    try out.appendSlice(allocator, value);
}

fn appendEnum(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_number: u32,
    state: control.PlaybackState,
) std.mem.Allocator.Error!void {
    try appendUint64(out, allocator, field_number, playbackStateValue(state));
}

fn appendUint64(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_number: u32,
    value: u64,
) std.mem.Allocator.Error!void {
    try appendKey(out, allocator, field_number, .varint);
    try appendVarint(out, allocator, value);
}

fn appendInt64(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_number: u32,
    value: i64,
) std.mem.Allocator.Error!void {
    try appendUint64(out, allocator, field_number, @bitCast(value));
}

fn appendKey(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_number: u32,
    wire_type: WireType,
) std.mem.Allocator.Error!void {
    try appendVarint(
        out,
        allocator,
        (@as(u64, field_number) << 3) | @intFromEnum(wire_type),
    );
}

fn appendVarint(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u64,
) std.mem.Allocator.Error!void {
    var remaining = value;
    while (remaining >= 0x80) {
        try out.append(allocator, @as(u8, @intCast(remaining & 0x7f)) | 0x80);
        remaining >>= 7;
    }
    try out.append(allocator, @intCast(remaining));
}

fn playbackStateValue(state: control.PlaybackState) u64 {
    return switch (state) {
        .idle => 1,
        .starting => 2,
        .playing => 3,
        .paused => 4,
        .stopped => 5,
        .ended => 6,
        .error_state => 7,
    };
}

fn decodeStart(message: []const u8) DecodeError!control.Start {
    var out = control.Start{
        .media_path = "",
        .start_frame = 0,
    };

    var reader = ProtoReader.init(message);
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => out.media_path = try field.string(),
            2 => out.start_frame = try field.uint64(),
            else => try field.skip(),
        }
    }

    try validateRequiredString(out.media_path);
    return out;
}

fn decodeTarget(message: []const u8) DecodeError!control.Target {
    var out = control.Target{ .playback_id = "" };

    var reader = ProtoReader.init(message);
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => out.playback_id = try field.string(),
            else => try field.skip(),
        }
    }

    try validateRequiredString(out.playback_id);
    return out;
}

fn decodeSeek(message: []const u8) DecodeError!control.Seek {
    var out = control.Seek{
        .playback_id = "",
        .frame = 0,
    };

    var reader = ProtoReader.init(message);
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => out.playback_id = try field.string(),
            2 => out.frame = try field.uint64(),
            else => try field.skip(),
        }
    }

    try validateRequiredString(out.playback_id);
    return out;
}

fn decodeListTracks(message: []const u8) DecodeError!library.ListTracksRequest {
    var out = library.ListTracksRequest{};

    var reader = ProtoReader.init(message);
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => out.page_size = std.math.cast(u32, try field.uint64()) orelse
                return error.InvalidInteger,
            2 => out.page_token = try field.string(),
            else => try field.skip(),
        }
    }

    return out;
}

fn validateRequiredString(value: []const u8) DecodeError!void {
    if (value.len == 0) return error.EmptyRequiredString;
}

const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    fixed32 = 5,
};

const Field = struct {
    number: u32,
    wire_type: WireType,
    reader: *ProtoReader,

    fn uint64(self: Field) DecodeError!u64 {
        if (self.wire_type != .varint) return error.InvalidWireType;
        return self.reader.readVarint();
    }

    fn string(self: Field) DecodeError![]const u8 {
        if (self.wire_type != .length_delimited) return error.InvalidWireType;

        const bytes = try self.reader.readBytes();
        if (bytes.len > max_control_string_len) return error.InvalidString;
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidString;
        if (std.mem.indexOfScalar(u8, bytes, 0) != null) {
            return error.InvalidString;
        }

        return bytes;
    }

    fn skip(self: Field) DecodeError!void {
        switch (self.wire_type) {
            .varint => _ = try self.reader.readVarint(),
            .fixed64 => try self.reader.skipBytes(8),
            .length_delimited => _ = try self.reader.readBytes(),
            .fixed32 => try self.reader.skipBytes(4),
        }
    }
};

const ProtoReader = struct {
    bytes: []const u8,
    offset: usize = 0,

    fn init(bytes: []const u8) ProtoReader {
        return .{ .bytes = bytes };
    }

    fn next(self: *ProtoReader) DecodeError!?Field {
        if (self.offset == self.bytes.len) return null;

        const key = try self.readVarint();
        const field_number = key >> 3;
        if (field_number == 0 or field_number > std.math.maxInt(u32)) {
            return error.InvalidFieldNumber;
        }

        return .{
            .number = @intCast(field_number),
            .wire_type = try decodeWireType(@intCast(key & 0x07)),
            .reader = self,
        };
    }

    fn readVarint(self: *ProtoReader) DecodeError!u64 {
        var result: u64 = 0;

        for (0..10) |shift_index| {
            if (self.offset >= self.bytes.len) return error.TruncatedMessage;

            const byte = self.bytes[self.offset];
            self.offset += 1;

            if (shift_index == 9 and byte > 1) return error.MalformedVarint;

            result |= @as(u64, byte & 0x7f) << @intCast(shift_index * 7);
            if ((byte & 0x80) == 0) return result;
        }

        return error.MalformedVarint;
    }

    fn readBytes(self: *ProtoReader) DecodeError![]const u8 {
        const len = try self.readVarint();
        if (len > std.math.maxInt(usize)) return error.TruncatedMessage;

        const start = self.offset;
        const end = start + @as(usize, @intCast(len));
        if (end < start or end > self.bytes.len) return error.TruncatedMessage;

        self.offset = end;
        return self.bytes[start..end];
    }

    fn skipBytes(self: *ProtoReader, len: usize) DecodeError!void {
        const end = self.offset + len;
        if (end < self.offset or end > self.bytes.len) {
            return error.TruncatedMessage;
        }
        self.offset = end;
    }
};

fn decodeWireType(value: u3) DecodeError!WireType {
    return switch (value) {
        0 => .varint,
        1 => .fixed64,
        2 => .length_delimited,
        5 => .fixed32,
        else => error.UnsupportedWireType,
    };
}

test "decodes start request" {
    const message =
        "\x0a\x11/tmp/example.flac" ++
        "\x10\x96\x01";

    const request = try decodeRequest(control.Method.start.fullName(), message);

    try std.testing.expect(request == .command);
    try std.testing.expect(request.command == .start);
    try std.testing.expectEqualStrings(
        "/tmp/example.flac",
        request.command.start.media_path,
    );
    try std.testing.expectEqual(@as(u64, 150), request.command.start.start_frame);
}

test "decodes list tracks request" {
    const request = try decodeRequest(
        library.Method.list_tracks.fullName(),
        "\x08\xfa\x01\x12\x02\x34\x32",
    );

    try std.testing.expect(request == .list_tracks);
    try std.testing.expectEqual(@as(u32, 250), request.list_tracks.page_size);
    try std.testing.expectEqualStrings("42", request.list_tracks.page_token);
}

test "encodes list tracks response" {
    var tracks = [_]database.Track{.{
        .id = 7,
        .path = @constCast("/music/a.flac"),
        .size = 123,
        .modified_ns = 456,
    }};
    const encoded = try encodeListTracksResponse(std.testing.allocator, .{
        .tracks = &tracks,
        .total_size = 9,
        .has_more = true,
    });
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualStrings(
        "\x0a\x16" ++
            "\x08\x07" ++
            "\x12\x0d/music/a.flac" ++
            "\x18\x7b" ++
            "\x20\xc8\x03" ++
            "\x12\x01\x37" ++
            "\x18\x09",
        encoded,
    );
}

test "encodes start response" {
    const encoded = try encodeResponse(std.testing.allocator, .{
        .start = .{
            .playback_id = "playback-1",
            .state = .starting,
        },
    });
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualStrings(
        "\x0a\x0aplayback-1" ++
            "\x10\x02",
        encoded,
    );
}

test "encodes command response" {
    const encoded = try encodeResponse(std.testing.allocator, .{
        .command = .{
            .playback_id = "playback-1",
            .state = .paused,
        },
    });
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualStrings(
        "\x0a\x0aplayback-1" ++
            "\x10\x04",
        encoded,
    );
}

test "encodes status response" {
    const encoded = try encodeResponse(std.testing.allocator, .{
        .status = .{
            .playback_id = "playback-1",
            .state = .playing,
            .media_path = "/tmp/song.flac",
            .current_frame = 4096,
            .generation_id = 2,
        },
    });
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualStrings(
        "\x0a\x0aplayback-1" ++
            "\x10\x03" ++
            "\x1a\x0e/tmp/song.flac" ++
            "\x20\x80\x20" ++
            "\x28\x02",
        encoded,
    );
}

test "decodes target control requests" {
    const message = "\x0a\x0bplayback-42";

    inline for (.{
        control.Method.stop,
        control.Method.pause,
        control.Method.resume_playback,
        control.Method.status,
    }) |method| {
        const request = try decodeRequest(method.fullName(), message);

        try std.testing.expect(request == .command);
        try std.testing.expectEqualStrings("playback-42", switch (method) {
            .stop => request.command.stop.playback_id,
            .pause => request.command.pause.playback_id,
            .resume_playback => request.command.resume_playback.playback_id,
            .status => request.command.status.playback_id,
            else => unreachable,
        });
    }
}

test "decodes seek request" {
    const message =
        "\x0a\x0bplayback-42" ++
        "\x10\x80\x80\x01";

    const request = try decodeRequest(control.Method.seek.fullName(), message);

    try std.testing.expect(request == .command);
    try std.testing.expect(request.command == .seek);
    try std.testing.expectEqualStrings("playback-42", request.command.seek.playback_id);
    try std.testing.expectEqual(@as(u64, 16384), request.command.seek.frame);
}

test "decodes watch request separately from unary commands" {
    const message = "\x0a\x0bplayback-42";

    const request = try decodeRequest(control.Method.watch.fullName(), message);

    try std.testing.expect(request == .watch);
    try std.testing.expectEqualStrings("playback-42", request.watch.playback_id);
}

test "skips unknown proto3 fields" {
    const message =
        "\x0a\x0bplayback-42" ++
        "\x18\x7b" ++
        "\x22\x03abc";

    const request = try decodeRequest(control.Method.stop.fullName(), message);

    try std.testing.expect(request == .command);
    try std.testing.expectEqualStrings("playback-42", request.command.stop.playback_id);
}

test "rejects malformed request payloads" {
    try std.testing.expectError(
        error.InvalidMethod,
        decodeRequest("/listener.control.v1.ListenerControl/Missing", ""),
    );
    try std.testing.expectError(
        error.EmptyRequiredString,
        decodeRequest(control.Method.stop.fullName(), ""),
    );
    try std.testing.expectError(
        error.InvalidWireType,
        decodeRequest(control.Method.stop.fullName(), "\x08\x01"),
    );
    try std.testing.expectError(
        error.TruncatedMessage,
        decodeRequest(control.Method.stop.fullName(), "\x0a\x05abc"),
    );
    try std.testing.expectError(
        error.MalformedVarint,
        decodeRequest(control.Method.seek.fullName(), "\x0a\x01p\x10\x80\x80\x80\x80\x80\x80\x80\x80\x80\x02"),
    );
    try std.testing.expectError(
        error.InvalidString,
        decodeRequest(control.Method.stop.fullName(), "\x0a\x02\xc3\x28"),
    );
}
