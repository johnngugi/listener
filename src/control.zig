const std = @import("std");

pub const service_full_name = "listener.control.v1.ListenerControl";
pub const service_full_name_z: [:0]const u8 = service_full_name;

pub const Method = enum {
    start,
    stop,
    pause,
    resume_playback,
    seek,
    status,
    watch,

    pub fn fullName(self: Method) []const u8 {
        return switch (self) {
            .start => "/" ++ service_full_name ++ "/Start",
            .stop => "/" ++ service_full_name ++ "/Stop",
            .pause => "/" ++ service_full_name ++ "/Pause",
            .resume_playback => "/" ++ service_full_name ++ "/Resume",
            .seek => "/" ++ service_full_name ++ "/Seek",
            .status => "/" ++ service_full_name ++ "/Status",
            .watch => "/" ++ service_full_name ++ "/Watch",
        };
    }
};

pub const PlaybackState = enum {
    idle,
    starting,
    playing,
    paused,
    stopped,
    ended,
    error_state,
};

pub const Command = union(enum) {
    start: Start,
    stop: Target,
    pause: Target,
    resume_playback: Target,
    seek: Seek,
    status: Target,
};

pub const Start = struct {
    media_path: []const u8,
    start_frame: u64 = 0,
};

pub const Target = struct {
    playback_id: []const u8,
};

pub const Seek = struct {
    playback_id: []const u8,
    frame: u64,
};

test "control method names are independent of the media protocol" {
    try std.testing.expectEqualStrings(
        "/listener.control.v1.ListenerControl/Start",
        Method.start.fullName(),
    );
    try std.testing.expectEqualStrings(
        "/listener.control.v1.ListenerControl/Watch",
        Method.watch.fullName(),
    );
}
