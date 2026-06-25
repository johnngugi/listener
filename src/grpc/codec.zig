const std = @import("std");

const control = @import("../control.zig");

pub const DecodeError = error{
    EmptyRequiredString,
    InvalidFieldNumber,
    InvalidMethod,
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
};

pub fn decodeRequest(method: []const u8, message: []const u8) DecodeError!Request {
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
