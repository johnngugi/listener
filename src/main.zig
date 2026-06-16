const std = @import("std");
const decoder = @import("decoder.zig");

const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
});

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const path = "/Users/johnngugi/Music/Library/Dominik Hauser - Chevaliers de Sangreal (From _The Da Vinci Code_) [feat. Hans Zimmer].flac";
    var audio_decoder = try decoder.AudioDecoder.open(
        allocator,
        path,
        .{
            .sample_format = .s32,
            .layout = .interleaved,
        },
    );
    defer audio_decoder.deinit();

    var buf: [16 * 1024]u8 = undefined;

    while (true) {
        const result = try audio_decoder.read(&buf);

        if (result.bytes > 0) {
            const pcm = buf[0..result.bytes];

            // Later
            // - write pcm to audio endpoint
            _ = pcm;
        }

        if (result.end_of_stream) {
            break;
        }
    }
}
