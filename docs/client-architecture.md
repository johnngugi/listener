# Client Architecture

## Overview

The client is split into a Flutter UI, a small Dart FFI wrapper, and a native
Zig audio engine. Flutter owns user interaction and low-frequency state
rendering. Zig owns playback, streaming, buffering, and platform audio output.

```text
Flutter UI
  -> Dart FFI wrapper
  -> Zig audio engine
  -> Listener server
  -> Platform audio backend
```

Flutter talks to the Zig engine through Dart FFI. The Zig engine should expose a
small C ABI surface that Dart can call. High-frequency audio data must stay out
of Flutter and Dart.

## Responsibilities

### Flutter UI

- Layout, navigation, widgets, and app presentation.
- Playback controls such as play, pause, resume, seek, and stop.
- Library, queue, device, and settings views.
- Low-frequency playback state rendering.

### Dart FFI Wrapper

- Load the native Zig library.
- Provide Dart-friendly methods for engine commands.
- Convert Flutter actions into native calls.
- Subscribe to playback events from the Zig engine.
- Keep the native boundary small and stable.

Example command surface:

```text
start(session_or_token, track_id)
pause()
resume()
seek(frame_or_time_position)
stop()
select_device(device_id)
subscribe_events(callback)
```

### Zig Audio Engine

- Playback state machine.
- Server stream client.
- Buffer and credit management.
- Decode and format conversion when needed.
- Platform audio backend selection.
- Device discovery and capability reporting.
- Real-time audio callback.

The Zig engine owns the actual playback lifecycle. Flutter asks the engine to
play; the engine connects to the server, manages the stream, fills buffers, and
writes frames to the selected audio device.

### Server

- Authentication and playback-session validation.
- Stream source selection.
- Frame or chunk delivery.
- Seek and range handling.
- Optional decoding or transcoding.

## Control And Data Flow

Flutter should not directly manage the media data path. It should send playback
intent to the local Zig engine, then render events reported by the engine.

```text
User action
  -> Flutter control
  -> Dart FFI call
  -> Zig playback command
  -> Server stream request
  -> Zig buffer
  -> Platform audio device
```

The client should prefer outbound connections from the Zig engine to the server.
Avoid requiring the server to open inbound connections to the client, because
that creates firewall, NAT, mobile-network, and sandboxing problems.

## Buffering And Flow Control

The Zig engine should use a ring buffer for decoded audio frames. The real-time
audio callback must not wait on network I/O, gRPC, allocation, locks, logging,
or Dart.

Use credit-based flow control between the Zig engine and the server:

```text
buffer capacity: N frames
low watermark: request more data
high watermark: stop granting new credit
```

The engine tells the server how many more frames it can accept. The server sends
only that much data for the current stream generation.

## Playback State

The engine should expose simple playback states to Flutter:

```text
Idle -> Preparing -> Buffering -> Playing
Playing -> Paused
Playing -> Buffering
Playing -> Draining -> Idle
Any -> Error
```

Flutter renders these states, but the Zig engine is authoritative for local
playback state because it owns device access, stream health, and buffer health.

## Platform Audio

The audio backend should be capability-based rather than assuming every platform
supports the same features.

Capabilities may include:

- Shared output support.
- Exclusive or low-level output support.
- Supported sample rates and formats.
- Current hardware sample rate.
- Whether resampling is required.
- Latency range.
- Volume control support.
- Device hotplug support.

Platform backends can then map these capabilities to APIs such as WASAPI,
CoreAudio, PulseAudio, PipeWire, ALSA, or Android audio APIs.

## Initial Implementation Slice

Start with a small vertical slice before adding full server streaming:

1. Flutter button calls Dart FFI.
2. Dart FFI calls the Zig engine.
3. Zig engine plays a generated tone or local PCM buffer.
4. Zig sends playback events back to Flutter.
5. Add one platform audio backend.
6. Add server streaming and flow control after the local engine boundary works.

This keeps the first client milestone focused on the Flutter-to-Zig boundary,
native playback lifecycle, and event reporting.
