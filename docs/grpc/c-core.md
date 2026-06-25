# gRPC C-core Integration

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
```

The LSTN TCP protocol remains the media/data plane. It still carries audio
frames, buffer status, stream generations, heartbeats, and protocol errors on
its own connections. gRPC does not serialize or deserialize LSTN frames.

The gRPC control plane is the authoritative source for user-visible playback
state such as `starting`, `playing`, `paused`, `stopped`, `ended`, and
`error`. LSTN stream state is transport state for a specific media generation;
clients should not treat it as a substitute for `Status` or `Watch`.

The gRPC API should stay behind `src/grpc/c_core.zig` and control-plane logic
should use `src/control.zig` types. The rest of the app should not see
`grpc_call`, `grpc_op`, completion-queue tags, or serialized protobuf buffers.

## Current Scaffold

`src/grpc/c_core.zig` contains the C-core lifecycle and call-accept surface:

- `grpc_init` / `grpc_shutdown`
- completion queue creation and draining
- insecure HTTP/2 server port binding for local development
- `grpc_server_request_call` for accepting calls

`src/grpc/codec.zig` decodes Listener-specific protobuf request payloads into
`src/control.zig` types. It intentionally does not implement a general Zig
protobuf or gRPC binding.

`src/control.zig` defines the transport-neutral command, response, status, and
event types. `src/playback.zig` owns playback IDs and state transitions behind
that boundary. The gRPC serving loop should call the playback controller with
decoded `control.Command` values and encode the returned `control.Response`
values back to protobuf.

The next step is a Listener-specific control loop that:

1. accepts only `listener.control.v1.ListenerControl` methods;
2. receives request messages from C-core and passes their payloads to the
   control-only codec;
3. executes decoded commands through `src/playback.zig`; and
4. maps control failures to gRPC status codes.

The TCP media session should report transport-derived progress and terminal
events back through the playback boundary. For example, `BUFFER_STATUS` can
advance `current_frame`, a new stream generation can update `generation_id`,
and end-of-stream can become an `ended` playback state.

## Building With C-core

The default build does not require gRPC C-core. To compile the optional C-core
adapter, install the C library and run:

```sh
zig build test -Dgrpc=true
```

The optional build links `grpc`. Homebrew's `grpc` library brings in `gpr`
itself on macOS, so linking `gpr` directly can produce a duplicate-dylib abort.
If gRPC is installed outside the system library path, add include/library paths
in `build.zig` next to the existing FFmpeg paths.

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

Transport-level and control-command failures should become gRPC statuses. LSTN
protocol errors remain on the TCP media/data connection.

An eventual client should open its playback-state subscription through
`Watch(playback_id)` or query `Status(playback_id)` first, then use LSTN for
the corresponding media stream bytes and buffer accounting.
