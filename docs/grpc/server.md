# gRPC server adapter

Listener exposes its control and library API from
`proto/listener/v1/listener.proto`. Both services run on the same insecure HTTP/2
server at `0.0.0.0:5779`.

The current API is:

```proto
service ListenerControl {
  rpc Start(StartRequest) returns (StartResponse);
  rpc Stop(StopRequest) returns (CommandResponse);
  rpc Pause(PauseRequest) returns (CommandResponse);
  rpc Resume(ResumeRequest) returns (CommandResponse);
  rpc Seek(SeekRequest) returns (CommandResponse);
  rpc Status(StatusRequest) returns (StatusResponse);
  rpc Watch(WatchRequest) returns (stream PlaybackEvent);
}

service ListenerLibrary {
  rpc ListTracks(ListTracksRequest) returns (ListTracksResponse);
  rpc GetArtwork(GetArtworkRequest) returns (GetArtworkResponse);
}
```

`Start`, `Stop`, `Pause`, `Resume`, `Seek`, `Status`, `ListTracks`, and
`GetArtwork` are implemented as unary calls. `Watch` is declared and decoded but
currently returns gRPC `UNIMPLEMENTED`.

## Separation from LSTN

gRPC is the control and library plane. The LSTN TCP protocol on port 5778 is the
media plane and carries `STREAM_INFO`, PCM audio, flow-control state,
generations, heartbeats, cancellation, and media-specific protocol errors.
gRPC does not wrap or serialize LSTN frames.

The normal start flow is:

1. the client calls gRPC `Start(track_id, start_frame)`;
2. the server resolves the UUID to its private media path and creates a
   `playback_id`;
3. the client sends that `playback_id` in LSTN `START_STREAM`;
4. the server binds the LSTN stream and generation to the playback session; and
5. LSTN `BUFFER_STATUS` messages update the control session's current frame.

Track, playback, and status responses never expose server filesystem paths.

## Implementation

`server/grpc/server.zig` owns gRPC C-core initialization, the completion queue,
generic call acceptance, unary request/response operations, and gRPC status
mapping. The server currently uses `grpc_server_request_call`, so Listener's own
codec dispatches fully qualified method paths.

`server/grpc/codec.zig` is a deliberately narrow protobuf codec for Listener
requests and responses; it is not a general Zig protobuf implementation.
Application code receives transport-neutral types from `server/control.zig` and
`server/library/service.zig`.

`server/playback.zig` owns playback IDs, states, positions, generation numbers,
and the mapping from playback IDs to private media paths. Its supported states
are `idle`, `starting`, `playing`, `paused`, `stopped`, `ended`, and `error`.

## Library calls

`ListTracks` reads from the SQLite catalog populated at server startup.

- A page size of zero selects 100 tracks.
- The maximum page size is 500.
- Page tokens are opaque, sort-aware cursors.
- Sorting supports track number, title, duration, album artist, album, release
  date, and date added in either direction.
- `total_size` reports the catalog size and `next_page_token` is empty at the end.

Each track may contain an `artwork_id`. `GetArtwork` returns the stored original
image bytes, MIME type, width, and height for that ID. Missing or invalid artwork
maps to `NOT_FOUND` or another appropriate gRPC failure.

## Error mapping

Malformed protobuf and invalid arguments map to `INVALID_ARGUMENT`. Missing
tracks, artwork, or playback sessions map to `NOT_FOUND`. Invalid playback state
maps to `FAILED_PRECONDITION`, and unsupported operations map to `UNIMPLEMENTED`.
Unexpected application failures map to `INTERNAL`.

LSTN framing and media errors remain on the LSTN connection and are not returned
as gRPC statuses.

## Build and run

The gRPC adapter is part of the default server build and requires the gRPC C
library; there is no longer a `-Dgrpc=true` build option.

```sh
brew install grpc
cd server
zig build
zig build test
zig build run
```

`server/build.zig` currently searches `/opt/homebrew/opt/grpc`. Change that
include and library path when using a different package-manager prefix.

The transport is currently insecure and binds all interfaces. Do not expose port
5779 to an untrusted network.
