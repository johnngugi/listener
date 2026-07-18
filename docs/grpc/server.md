# gRPC Server Adapter

Listener exposes a separate gRPC control-plane contract in
`proto/listener/v1/listener.proto`:

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
}
```

Both services are hosted by the same gRPC server on the same port. gRPC routes
calls by their fully qualified service and method names.

The LSTN TCP protocol remains the media/data plane. It still carries audio
frames, buffer status, stream generations, heartbeats, and protocol errors on
its own connections. gRPC does not serialize or deserialize LSTN frames.

The gRPC control plane is the authoritative source for user-visible playback
state such as `starting`, `playing`, `paused`, `stopped`, `ended`, and
`error`. LSTN stream state is transport state for a specific media generation;
clients should not treat it as a substitute for `Status` or `Watch`.

The gRPC API stays behind `server/grpc/server.zig`; application logic uses the
transport-neutral types in `server/control.zig` and `server/library/service.zig`.
The rest of the app should not see `grpc_call`, `grpc_op`, completion-queue tags,
or serialized protobuf buffers.

## Current Scaffold

`server/grpc/server.zig` contains the gRPC server lifecycle and call-accept surface:

- `grpc_init` / `grpc_shutdown`
- completion queue creation and draining
- insecure HTTP/2 server port binding for local development
- `grpc_server_request_call` for accepting calls

`server/grpc/codec.zig` decodes Listener-specific protobuf request payloads into
transport-neutral control or library types. It intentionally does not implement
a general Zig protobuf or gRPC binding.

`server/control.zig` defines the transport-neutral command, response, status, and
event types. `server/playback.zig` owns playback IDs and state transitions behind
that boundary. The gRPC serving loop should call the playback controller with
decoded `control.Command` values and encode the returned `control.Response`
values back to protobuf.

`server/library/service.zig` is the transport-neutral boundary for library
browsing. `ListTracks` reads bounded pages from SQLite using the last returned
track ID as a cursor. A page size of zero selects the default of 100 tracks;
requests above the maximum of 500 are rejected with `INVALID_ARGUMENT`.
`next_page_token` is empty when no further page exists.

The Listener-specific serving loop:

1. accepts `listener.control.v1.ListenerControl` and
   `listener.control.v1.ListenerLibrary` methods;
2. receives request messages from the gRPC adapter and passes their payloads to the
   Listener-specific codec;
3. executes decoded calls through `server/playback.zig` or the library service;
   and
4. maps application failures to gRPC status codes.

The TCP media session should report transport-derived progress and terminal
events back through the playback boundary. For example, `BUFFER_STATUS` can
advance `current_frame`, a new stream generation can update `generation_id`,
and end-of-stream can become an `ended` playback state.

## Building The gRPC Adapter

The default build does not require the gRPC C library. To compile the optional
gRPC adapter, install the C library and run:

```sh
cd server
zig build test -Dgrpc=true
```

The optional build links `grpc`. Homebrew's `grpc` library brings in `gpr`
itself on macOS, so linking `gpr` directly can produce a duplicate-dylib abort.
If gRPC is installed outside the system library path, add include/library paths
in `server/build.zig` next to the existing FFmpeg paths.

## Protocol Mapping

The gRPC schema models player control, not the LSTN media protocol:

| Control concept | gRPC proto |
|---|---|
| Start playback | `Start(StartRequest)` |
| Stop playback | `Stop(StopRequest)` |
| Pause playback | `Pause(PauseRequest)` |
| Resume playback | `Resume(ResumeRequest)` |
| Seek playback | `Seek(SeekRequest)` |
| Query state | `Status(StatusRequest)` |
| Observe changes | `Watch(WatchRequest)` |
| Browse scanned tracks | `ListTracks(ListTracksRequest)` |
| Fetch stored album artwork | `GetArtwork(GetArtworkRequest)` |

`ListTracks` exposes an optional `artwork_id` on each track. Clients can pass
that identifier to `GetArtwork` to receive the original image bytes together
with their MIME type and pixel dimensions.

Transport-level and control-command failures should become gRPC statuses. LSTN
protocol errors remain on the TCP media/data connection.

An eventual client should call `Start`, use the returned `playback_id` in the
LSTN `START_STREAM` body, then open its playback-state subscription through
`Watch(playback_id)` or query `Status(playback_id)`. The LSTN server binds
that playback ID to the media header's `stream_id` and `generation_id`, and
buffer accounting for the active stream reports progress back to the playback
controller.
