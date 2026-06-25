const std = @import("std");

const control = @import("control.zig");

pub const SessionUpdate = struct {
    playback_id: []const u8,
    state: ?control.PlaybackState = null,
    current_frame: ?u64 = null,
    generation_id: ?u64 = null,
};

pub const Controller = struct {
    allocator: std.mem.Allocator,
    next_playback_number: u64 = 1,
    sessions: std.ArrayList(Session) = .empty,

    const Session = struct {
        playback_id: []u8,
        media_path: []u8,
        state: control.PlaybackState,
        current_frame: u64,
        generation_id: u64,

        fn deinit(self: *Session, allocator: std.mem.Allocator) void {
            allocator.free(self.playback_id);
            allocator.free(self.media_path);
        }

        fn startResult(self: *const Session) control.StartResult {
            return .{
                .playback_id = self.playback_id,
                .state = self.state,
            };
        }

        fn commandResult(self: *const Session) control.CommandResult {
            return .{
                .playback_id = self.playback_id,
                .state = self.state,
            };
        }

        fn status(self: *const Session) control.Status {
            return .{
                .playback_id = self.playback_id,
                .state = self.state,
                .media_path = self.media_path,
                .current_frame = self.current_frame,
                .generation_id = self.generation_id,
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator) Controller {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Controller) void {
        for (self.sessions.items) |*session| {
            session.deinit(self.allocator);
        }
        self.sessions.deinit(self.allocator);
    }

    pub fn execute(
        self: *Controller,
        command: control.Command,
    ) (std.mem.Allocator.Error || control.ControlError)!control.Response {
        return switch (command) {
            .start => |start_request| .{
                .start = try self.start(start_request),
            },
            .stop => |target| .{ .command = try self.stop(target) },
            .pause => |target| .{ .command = try self.pause(target) },
            .resume_playback => |target| .{
                .command = try self.resumePlayback(target),
            },
            .seek => |seek_request| .{
                .command = try self.seek(seek_request),
            },
            .status => |target| .{ .status = try self.status(target) },
        };
    }

    pub fn start(
        self: *Controller,
        request: control.Start,
    ) std.mem.Allocator.Error!control.StartResult {
        const playback_id = try std.fmt.allocPrint(
            self.allocator,
            "playback-{d}",
            .{self.next_playback_number},
        );
        errdefer self.allocator.free(playback_id);

        const media_path = try self.allocator.dupe(u8, request.media_path);
        errdefer self.allocator.free(media_path);

        try self.sessions.append(self.allocator, .{
            .playback_id = playback_id,
            .media_path = media_path,
            .state = .starting,
            .current_frame = request.start_frame,
            .generation_id = 1,
        });
        self.next_playback_number += 1;

        return self.sessions.items[self.sessions.items.len - 1].startResult();
    }

    pub fn stop(
        self: *Controller,
        target: control.Target,
    ) control.ControlError!control.CommandResult {
        const session = try self.findSession(target.playback_id);
        session.state = .stopped;
        return session.commandResult();
    }

    pub fn pause(
        self: *Controller,
        target: control.Target,
    ) control.ControlError!control.CommandResult {
        const session = try self.findSession(target.playback_id);
        switch (session.state) {
            .starting, .playing, .paused => session.state = .paused,
            .idle, .stopped, .ended, .error_state => return error.InvalidState,
        }
        return session.commandResult();
    }

    pub fn resumePlayback(
        self: *Controller,
        target: control.Target,
    ) control.ControlError!control.CommandResult {
        const session = try self.findSession(target.playback_id);
        switch (session.state) {
            .starting, .playing, .paused => session.state = .playing,
            .idle, .stopped, .ended, .error_state => return error.InvalidState,
        }
        return session.commandResult();
    }

    pub fn seek(
        self: *Controller,
        request: control.Seek,
    ) control.ControlError!control.CommandResult {
        const session = try self.findSession(request.playback_id);
        switch (session.state) {
            .starting, .playing, .paused => {},
            .idle, .stopped, .ended, .error_state => return error.InvalidState,
        }

        session.current_frame = request.frame;
        session.generation_id += 1;
        return session.commandResult();
    }

    pub fn status(
        self: *Controller,
        target: control.Target,
    ) control.ControlError!control.Status {
        return (try self.findSession(target.playback_id)).status();
    }

    pub fn updateSession(
        self: *Controller,
        update: SessionUpdate,
    ) control.ControlError!control.Status {
        const session = try self.findSession(update.playback_id);
        if (update.state) |state| session.state = state;
        if (update.current_frame) |frame| session.current_frame = frame;
        if (update.generation_id) |generation| session.generation_id = generation;

        return session.status();
    }

    fn findSession(
        self: *Controller,
        playback_id: []const u8,
    ) control.ControlError!*Session {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.playback_id, playback_id)) {
                return session;
            }
        }

        return error.PlaybackNotFound;
    }
};

test "controller starts playback and owns status state" {
    var controller = Controller.init(std.testing.allocator);
    defer controller.deinit();

    const started = try controller.start(.{
        .media_path = "/tmp/song.flac",
        .start_frame = 128,
    });

    try std.testing.expectEqualStrings("playback-1", started.playback_id);
    try std.testing.expectEqual(control.PlaybackState.starting, started.state);

    const status = try controller.status(.{ .playback_id = started.playback_id });
    try std.testing.expectEqualStrings("/tmp/song.flac", status.media_path);
    try std.testing.expectEqual(@as(u64, 128), status.current_frame);
    try std.testing.expectEqual(@as(u64, 1), status.generation_id);
}

test "controller executes transport-neutral commands" {
    var controller = Controller.init(std.testing.allocator);
    defer controller.deinit();

    const start_response = try controller.execute(.{
        .start = .{ .media_path = "/tmp/song.flac" },
    });
    try std.testing.expect(start_response == .start);

    const playback_id = start_response.start.playback_id;

    const resume_response = try controller.execute(.{
        .resume_playback = .{ .playback_id = playback_id },
    });
    try std.testing.expect(resume_response == .command);
    try std.testing.expectEqual(
        control.PlaybackState.playing,
        resume_response.command.state,
    );

    const seek_response = try controller.execute(.{
        .seek = .{ .playback_id = playback_id, .frame = 4096 },
    });
    try std.testing.expect(seek_response == .command);
    try std.testing.expectEqual(
        control.PlaybackState.playing,
        seek_response.command.state,
    );

    const status_response = try controller.execute(.{
        .status = .{ .playback_id = playback_id },
    });
    try std.testing.expect(status_response == .status);
    try std.testing.expectEqual(@as(u64, 4096), status_response.status.current_frame);
    try std.testing.expectEqual(@as(u64, 2), status_response.status.generation_id);
}

test "controller rejects unknown playback ids" {
    var controller = Controller.init(std.testing.allocator);
    defer controller.deinit();

    try std.testing.expectError(
        error.PlaybackNotFound,
        controller.status(.{ .playback_id = "missing" }),
    );
}

test "media session can report progress through the boundary" {
    var controller = Controller.init(std.testing.allocator);
    defer controller.deinit();

    const started = try controller.start(.{ .media_path = "/tmp/song.flac" });
    const status = try controller.updateSession(.{
        .playback_id = started.playback_id,
        .state = .playing,
        .current_frame = 2048,
    });

    try std.testing.expectEqual(control.PlaybackState.playing, status.state);
    try std.testing.expectEqual(@as(u64, 2048), status.current_frame);
}
