# Listener Media Protocol

## Status

This document describes version 1 of the Listener media protocol as currently
implemented in `src/protocol.zig`.

The protocol is still under development. The common header and the
`STREAM_INFO`, `AUDIO_FRAME`, and `BUFFER_STATUS` fixed bodies are defined.
The remaining message bodies and attachment of encoded audio bytes to an
`AUDIO_FRAME` are not yet implemented.

## Overview

Listener uses a bidirectional TCP connection for media transport:

```text
Client                                      Server
  |---- HELLO -------------------------------->|
  |<--- HELLO_ACK -----------------------------|
  |---- START_STREAM -------------------------->|
  |<--- STREAM_INFO ----------------------------|
  |<--- AUDIO_FRAME ----------------------------|
  |---- BUFFER_STATUS ------------------------->|
  |<--- AUDIO_FRAME ... ------------------------|
  |---- CANCEL_GENERATION --------------------->|
  |<--- STREAM_END / ERROR ---------------------|
```

Every message consists of:

```text
+----------------------+----------------------+
| 40-byte header       | body_len body bytes  |
+----------------------+----------------------+
```

All protocol integers are unsigned and encoded in network byte order
(big-endian), unless a field explicitly says otherwise. PCM byte order is part
of its sample format and is currently little-endian.

## Protocol constants

| Name | Value | Description |
|---|---:|---|
| Magic | ASCII `LSTN` | Identifies Listener protocol data |
| Protocol version | `1` | Current wire-protocol version |
| Header length | `40` bytes | Version 1 header size |
| Maximum body length | `1,048,576` bytes | Largest accepted message body |

## Common header

Every message begins with this 40-byte header:

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 4 | `u8[4]` | `magic` | Fixed ASCII signature `LSTN` |
| 4 | 2 | `u16` | `version` | Protocol version; currently `1` |
| 6 | 2 | `u16` | `message_type` | Message type identifier |
| 8 | 2 | `u16` | `flags` | Reserved; must currently be `0` |
| 10 | 2 | `u16` | `header_len` | Header size; currently `40` |
| 12 | 4 | `u32` | `body_len` | Number of bytes following the header |
| 16 | 8 | `u64` | `stream_id` | Logical media-stream identifier |
| 24 | 8 | `u64` | `generation_id` | Playback generation identifier |
| 32 | 8 | `u64` | `sequence` | Message sequence number |

### Header field semantics

#### `stream_id`

Identifies one logical playback stream. It allows a connection to distinguish
messages belonging to different streams.

#### `generation_id`

Identifies the current incarnation of a stream. Seeking or changing tracks
starts a new generation. A receiver must ignore messages from an obsolete
generation.

#### `sequence`

A monotonically increasing message number used for accounting, diagnostics,
and detecting unexpected gaps. TCP itself provides reliable, ordered delivery,
so this field is not used for retransmission.

#### `flags`

No flags are defined in version 1. Senders must set the field to zero.
Receivers should reject nonzero values until flag semantics are specified.

The field is reserved so future versions can attach boolean properties to a
message without changing the fixed header layout.

#### `header_len`

This is a wire-level protocol constant rather than caller-controlled message
state. Version 1 always writes and accepts a value of `40`.

The field reserves a path for future header extensions. The current decoder
does not support extended headers and rejects any other value.

#### `body_len`

The exact number of bytes following the header. It must not exceed the maximum
body length of 1 MiB.

## Message types

| Value | Name | Direction | Status |
|---:|---|---|---|
| 1 | `HELLO` | Client → server | Body not yet defined |
| 2 | `HELLO_ACK` | Server → client | Body not yet defined |
| 3 | `START_STREAM` | Client → server | Body not yet defined |
| 4 | `STREAM_INFO` | Server → client | Defined |
| 5 | `AUDIO_FRAME` | Server → client | Fixed metadata defined |
| 6 | `BUFFER_STATUS` | Client → server | Defined |
| 7 | `CANCEL_GENERATION` | Client → server | Body not yet defined |
| 8 | `STREAM_END` | Server → client | Body not yet defined |
| 9 | `PROTOCOL_ERROR` | Either direction | Body not yet defined |
| 10 | `PING` | Either direction | Body not yet defined |
| 11 | `PONG` | Either direction | Body not yet defined |

Unknown message-type values are rejected.

## Sample formats

| Value | Name | Bytes/sample | Description |
|---:|---|---:|---|
| 1 | `pcm_s16le` | 2 | Signed 16-bit little-endian PCM |
| 2 | `pcm_s24le_packed` | 3 | Signed 24-bit little-endian PCM packed into three bytes |
| 3 | `pcm_s24le_in_s32le` | 4 | Signed 24-bit value sign-extended into a little-endian `i32` |
| 4 | `pcm_s32le` | 4 | Signed 32-bit little-endian PCM |
| 5 | `pcm_f32le` | 4 | IEEE-754 binary32 little-endian PCM |

Unknown sample-format values are rejected.

PCM is interleaved by channel unless a future protocol version states
otherwise. For stereo audio, samples are ordered:

```text
left, right, left, right, ...
```

A **PCM frame** contains one sample for every channel. At 48 kHz,
`48,000` frames represent one second regardless of the number of channels.

## `STREAM_INFO`

`STREAM_INFO` describes the audio format and the selected playback range.
Its body is exactly 32 bytes.

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 2 | `u16` | `format` | Value from the sample-format table |
| 2 | 4 | `u32` | `sample_rate` | PCM frames per second |
| 6 | 2 | `u16` | `channels` | Number of interleaved channels |
| 8 | 4 | `u32` | `channel_layout` | Channel-layout identifier or mask; exact mapping is not yet specified |
| 12 | 8 | `u64` | `total_frames` | Total decoded PCM frames in the source |
| 20 | 8 | `u64` | `actual_start_frame` | First source frame the server will send |
| 28 | 4 | `u32` | `recommended_buffer_frames` | Recommended client buffer target |

`actual_start_frame` may differ from a requested seek position if the server
must align decoding to a supported boundary.

## `AUDIO_FRAME`

The currently implemented fixed metadata body is 12 bytes:

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 8 | `u64` | `sample_offset` | Source-frame offset of the first represented frame |
| 8 | 4 | `u32` | `frame_count` | Number of decoded PCM frames represented |

The audio bytes are intended to follow this metadata:

```text
+----------------------+---------------------+
| 12-byte frame info   | encoded audio data  |
+----------------------+---------------------+
```

When audio payload support is implemented:

```text
body_len = 12 + encoded_audio_length
```

For uncompressed PCM:

```text
encoded_audio_length =
    frame_count * channels * bytes_per_sample
```

The audio format is inherited from the preceding `STREAM_INFO` for the same
stream and generation. Mid-generation format changes are not currently
supported.

The current Zig `AudioFrame.decode` function accepts only the 12-byte metadata
body. Reading and validating the following audio bytes remains to be
implemented.

## `BUFFER_STATUS`

`BUFFER_STATUS` is sent by the client to report playback progress and control
server flow. Its body is exactly 28 bytes.

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 4 | `u32` | `buffered_frames` | Frames accepted but not yet rendered |
| 4 | 4 | `u32` | `credit_frames` | Absolute allowance for additional in-flight frames |
| 8 | 8 | `u64` | `next_render_frame` | Source offset of the next frame the device will render |
| 16 | 8 | `u64` | `last_received_sequence` | Most recent accepted message sequence |
| 24 | 4 | `u32` | `underrun_count` | Number of distinct playback starvation periods |

### Credit semantics

`credit_frames` is an absolute allowance, not an increment. Every
`BUFFER_STATUS` replaces the previously reported credit value.

The server must limit its outstanding audio accordingly. This prevents large
amounts of obsolete audio from accumulating in TCP buffers and delaying a seek
or track change.

### Playback position

`next_render_frame` is an exclusive position. If frames `10,000` through
`10,999` have played, its value is `11,000`.

It must be derived from frames consumed by the audio device, not from frames
received over the network or merely submitted to an application buffer.

### Underruns

`underrun_count` increases once for each continuous starvation period. It
should not increase once per audio callback while the same underrun continues.

## Playback generations

The generation ID protects playback state from late or obsolete data:

1. The client discards buffered data when seeking or changing tracks.
2. The client increments `generation_id`.
3. The client requests the new frame offset or track.
4. Messages carrying an older generation ID are ignored.

Pause is local and does not require a new generation. Stop clears the local
buffer. A later restart may use a new generation depending on the chosen
control semantics.

## Playback clock

For one playback client, no server/client clock synchronization is required.
The DAC or native audio device is the authoritative playback clock.

Playback position is:

```text
generation start frame + frames consumed by the audio device
```

Packet-arrival time, server wall-clock time, UI timers, and frames merely
submitted to the audio API are not authoritative playback clocks.

Multi-zone synchronization is outside the currently implemented protocol. It
will require monotonic clock probes, scheduled start times, device-latency
estimation, and gradual correction for DAC clock drift.

## Validation rules

A receiver currently rejects a message when:

- `magic` is not `LSTN`;
- `version` is not `1`;
- fewer than 40 header bytes are available;
- `header_len` is not `40`;
- `body_len` exceeds 1 MiB;
- `message_type` is unknown;
- a fixed-size body has the wrong length; or
- a `STREAM_INFO` sample format is unknown.

TCP reads are not message-aligned. An implementation must:

1. Read exactly 40 bytes for the header.
2. Decode and validate the header.
3. Read exactly `body_len` bytes.
4. Decode the body according to `message_type`.

Neither Zig struct memory nor native integer layout is part of the wire
protocol. Every field must be encoded and decoded explicitly.

## Open items

- Define `HELLO` and version/capability negotiation.
- Define `HELLO_ACK`.
- Define `START_STREAM` and its media handle.
- Attach and validate audio bytes in `AUDIO_FRAME`.
- Define `channel_layout` values.
- Define `CANCEL_GENERATION`.
- Define `STREAM_END` reasons.
- Define stable protocol error codes.
- Define `PING` and `PONG` timestamps.
- Decide authentication and encryption for remote connections.
- Define compressed FLAC and Opus profiles if remote playback is added.
