# Client architecture

## Overview

The macOS client is split into a Flutter UI, a Dart API/FFI boundary, and a
native Zig playback engine. Flutter owns presentation and low-frequency state.
Zig owns network media transport, buffering, the playback lifecycle, and
CoreAudio output.

```text
                           gRPC control/library (:5779)
Flutter UI ─────────────────────────────────────────────> Listener server
    │                                                          ▲
    │ Dart API / FFI                                           │
    ▼                                                          │
Zig playback engine ───────── LSTN media TCP (:5778) ──────────┘
    │
    └── CoreAudio output
```

High-frequency PCM data stays outside Dart and Flutter.

## Flutter application

`client/listener_front` contains the application shell, models, repositories,
services, cubits, widgets, and generated protobuf types.

At startup, `ListenerBootstrap`:

1. opens the native engine;
2. loads the last successful server from shared preferences;
3. tries that server or starts Bonjour discovery for `_lstn._tcp`;
4. opens the engine's LSTN connection and a separate insecure gRPC channel; and
5. provides playback, output-device, library, and artwork dependencies to the UI.

The library loads 200 tracks per request and performs sorting on the server.
Artwork bytes are fetched lazily through `GetArtwork` and managed by
`ArtworkRepository`. The layout uses a fixed sidebar at widths of 1100 logical
pixels or more and a drawer below that breakpoint.

`PlaybackCubit` coordinates the two planes. It obtains a `playback_id` with the
gRPC `Start` method, then passes that ID to the engine's LSTN `START_STREAM`.
Pause, resume, and stop update both the local engine and gRPC session. Playback
position is polled from the engine. Seek is currently driven by the engine,
which replaces the active LSTN generation.

## Dart engine API and FFI

`client/engine/lib/listener_engine.dart` is the public Dart API. It validates the
native ABI version, owns the native engine handle, maps status codes, exposes
playback/discovery events, and guarantees native resources are released by
`close()`.

The API supports:

- discovery and connection;
- output-device enumeration, selection, and configuration;
- start, stop, pause, resume, current position, and seek;
- software gain; and
- asynchronous playback and discovery events.

Bindings in `lib/src/bindings.dart` use `@Native` with the Native Assets ID
`package:listener_engine/listener_engine.dart`. Consumers never locate or load a
dylib themselves.

## Native Assets build

`client/engine/hook/build.dart` maps the Flutter target to a Zig target, finds
the macOS SDK with `xcrun`, and invokes the engine's Zig build. The resulting
`liblistener_engine.dylib` is registered as a bundled dynamic code asset.

The production build selects CoreAudio only for macOS. Other target operating
systems fail at build time until another audio backend is implemented. Zig unit
and repository integration tests select the in-memory test backend instead.

## Zig playback engine

The Zig engine owns:

- one persistent LSTN connection;
- a single socket reader from `HELLO_ACK` through shutdown;
- serialized socket writes for heartbeats, credit, cancellation, and stream
  requests;
- playback generations and late-frame rejection;
- a shared PCM ring buffer;
- startup prebuffering and ongoing credit-based flow control;
- CoreAudio device and callback lifecycles; and
- event delivery across the FFI boundary.

The output device opens before network receiving begins. Playback starts after
half of the negotiated ring-buffer capacity is filled, or when `STREAM_END`
releases the wait for a short track. A failure before startup is returned by the
start operation; a later failure is emitted as an engine event.

The real-time callback reads only from the ring buffer and applies the gain
stage. It does not perform network I/O, allocation, logging, or Dart callbacks.

## Connection lifetime and recovery

The engine keeps its LSTN connection open between tracks. The lifetime reader
answers `PING` while active or idle. All writes share one outbound mutex so
sequence numbers remain ordered.

Shutdown marks the connection closed, shuts down the socket to wake its reader,
and joins the reader before releasing the descriptor. If the server disconnects
while the engine is idle, the configured endpoint is retained and the engine
reconnects before the next `START_STREAM`.

The gRPC channel is owned separately by `ListenerGrpc`. Changing servers creates
a new engine and channel before closing the previous pair.

## Buffering, credit, and playback clock

The client grants an absolute number of frames the server may have outstanding.
It sends `BUFFER_STATUS` with the buffered count, current credit, next render
position, last accepted server sequence, and underrun count. The server does not
send beyond that allowance.

The native audio device is the authoritative playback clock. UI timers and
network arrival times are not. The reported position is the generation's start
frame plus frames consumed by CoreAudio.

## Current platform and security boundaries

- macOS/CoreAudio is the only production client target.
- LSTN and gRPC are plaintext and unauthenticated.
- Bonjour advertises LSTN port 5778 and a `grpc-port=5779` TXT value, although
  the Flutter gRPC client currently uses port 5779 directly.
- The server owns filesystem paths; the client sees UUID track IDs and opaque
  playback IDs.
- Multi-zone synchronization is not implemented.

See [the LSTN protocol](protocol.md) and
[the gRPC adapter](grpc/server.md) for transport details.
