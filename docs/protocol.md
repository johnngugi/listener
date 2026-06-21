# Listener Media Protocol

## Status

This document describes version 1 of the Listener media protocol as currently
implemented in `src/protocol.zig`.

The protocol is still under development. The common header and the
`START_STREAM`, `STREAM_INFO`, `AUDIO_FRAME`, and `BUFFER_STATUS` bodies are
defined. `HELLO`, `HELLO_ACK`, `CANCEL_GENERATION`, `PING`, and `PONG`
currently have empty bodies. `STREAM_END` is an empty server message.
`AUDIO_FRAME` messages carry decoded PCM payload bytes. `PROTOCOL_ERROR` has a
structured diagnostic body.

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
| 1 | `HELLO` | Client → server | Empty body |
| 2 | `HELLO_ACK` | Server → client | Empty body |
| 3 | `START_STREAM` | Client → server | Defined |
| 4 | `STREAM_INFO` | Server → client | Defined |
| 5 | `AUDIO_FRAME` | Server → client | Defined |
| 6 | `BUFFER_STATUS` | Client → server | Defined |
| 7 | `CANCEL_GENERATION` | Client → server | Empty body |
| 8 | `STREAM_END` | Server → client | Empty body |
| 9 | `PROTOCOL_ERROR` | Server → client | Defined |
| 10 | `PING` | Either direction | Empty body |
| 11 | `PONG` | Either direction | Empty body |

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

## `START_STREAM`

`START_STREAM` asks the server to open a media file and begin a playback
generation. Its body consists of a 10-byte fixed portion followed by a
variable-length UTF-8 file path.

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 8 | `u64` | `requested_start_frame` | Source PCM frame at which playback should begin; use `0` to start at the beginning |
| 8 | 2 | `u16` | `path_len` | Number of bytes in `media_path` |
| 10 | `path_len` | bytes | `media_path` | UTF-8 path of the media file accessible to the server |

The body length is:

```text
body_len = 10 + path_len
```

`media_path` is not NUL-terminated. The encoded path bytes immediately follow
the `path_len` field. It must be valid UTF-8, contain no NUL bytes, and contain
between 1 and 4,096 bytes.

The current server supports only `requested_start_frame = 0`. Other values are
rejected because seeking is not yet implemented.

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

The body contains 12 bytes of fixed metadata followed by decoded PCM data:

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 8 | `u64` | `frame_offset` | Source PCM-frame position of the first payload frame |
| 8 | 4 | `u32` | `frame_count` | Number of decoded PCM frames represented |
| 12 | Variable | bytes | `audio_data` | Interleaved PCM payload |

```text
+----------------------+---------------------+
| 12-byte frame info   | PCM audio data      |
+----------------------+---------------------+
```

```text
body_len = 12 + audio_data.len
```

For uncompressed PCM:

```text
audio_data.len =
    frame_count * channels * bytes_per_sample
```

The current implementation limits `audio_data` to 1,024 bytes per message.
Payloads contain only complete PCM frames; a frame is never split across
messages.

The audio format is inherited from the preceding `STREAM_INFO` for the same
stream and generation. Mid-generation format changes are not currently
supported.

`frame_offset` is measured in source PCM frames, not bytes or individual
channel samples. Successive messages advance it by the preceding message's
`frame_count`.

The server sends audio in response to `BUFFER_STATUS`, up to the credit
reported by the client. It stops producing frames when credit is exhausted or
the decoder reaches end of input.

## `STREAM_END`

`STREAM_END` tells the client that the server has produced all audio for the
identified stream and generation. Its body is empty, so `body_len` must be
`0`.

The server sends it immediately after the final `AUDIO_FRAME` when the decoder
reports end of input with that frame. If the final audio frame exactly fills a
message, the decoder performs a one-frame lookahead so the server can still
send `STREAM_END` immediately. It is sent at most once for a generation.

Receiving `STREAM_END` does not mean playback has completed. The client should
continue rendering audio already buffered for that generation and consider
playback complete only after the buffer has drained.

## `PROTOCOL_ERROR`

`PROTOCOL_ERROR` reports a recoverable problem with a client message. Its body
contains 14 bytes of fixed metadata followed by an optional UTF-8 diagnostic:

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 2 | `u16` | `error_code` | Stable value from the protocol-error code table |
| 2 | 2 | `u16` | `offending_message_type` | Message type of the rejected client message |
| 4 | 8 | `u64` | `offending_sequence` | Sequence number of the rejected client message |
| 12 | 2 | `u16` | `detail_len` | Number of bytes in `detail` |
| 14 | Variable | bytes | `detail` | Optional human-readable UTF-8 diagnostic |

```text
body_len = 14 + detail_len
```

The detail is limited to 4,096 bytes, must be valid UTF-8, and must not contain
NUL bytes. It is intended for diagnostics only. Clients must branch on
`error_code`, not on the detail text.

| Value | Name | Meaning |
|---:|---|---|
| 1 | `MALFORMED_MESSAGE` | The message framing or representation is malformed |
| 2 | `INVALID_BODY` | The body is structurally or semantically invalid |
| 3 | `UNEXPECTED_MESSAGE` | The message direction or type is not accepted |
| 4 | `INVALID_STATE` | The message is not valid in the current connection state |
| 5 | `UNSUPPORTED_OPERATION` | The requested operation is valid but unsupported |
| 6 | `STREAM_UNAVAILABLE` | The requested media stream could not be opened |
| 7 | `INTERNAL_ERROR` | The server could not complete an otherwise valid request |

The response header copies the offending message's `stream_id` and
`generation_id`. The response receives its own server sequence number;
`offending_sequence` identifies the rejected client message.

The current server sends `PROTOCOL_ERROR` only after it has decoded and fully
consumed a trustworthy message frame. Invalid magic, versions, flags, header
lengths, message-type values, oversized bodies, truncated frames, and
transport failures close the connection without a response. This avoids
responding when framing is untrustworthy or the next message boundary is
unknown.

## `BUFFER_STATUS`

`BUFFER_STATUS` is sent by the client to report playback progress and control
server flow. Its body is exactly 28 bytes.

| Offset | Size | Type | Field | Description |
|---:|---:|---|---|---|
| 0 | 4 | `u32` | `buffered_frames` | Frames accepted but not yet rendered |
| 4 | 4 | `u32` | `credit_frames` | Absolute allowance for unacknowledged frames |
| 8 | 8 | `u64` | `next_render_frame` | Source offset of the next frame the device will render |
| 16 | 8 | `u64` | `last_received_sequence` | Most recent accepted message sequence |
| 24 | 4 | `u32` | `underrun_count` | Number of distinct playback starvation periods |

### Credit semantics

`credit_frames` is an absolute allowance, not an increment. Every
`BUFFER_STATUS` replaces the previously reported credit value.

The server must limit its outstanding audio accordingly. This prevents large
amounts of obsolete audio from accumulating in TCP buffers and delaying a seek
or track change.

`last_received_sequence` acknowledges every audio message through that server
sequence number. The server removes the acknowledged frames from its
outstanding-frame accounting before applying the new credit.

### Playback position

`next_render_frame` is an exclusive position. If frames `10,000` through
`10,999` have played, its value is `11,000`.

It must be derived from frames consumed by the audio device, not from frames
received over the network or merely submitted to an application buffer.

### Underruns

`underrun_count` increases once for each continuous starvation period. It
should not increase once per audio callback while the same underrun continues.

## `CANCEL_GENERATION`

`CANCEL_GENERATION` asks the server to stop producing audio for one playback
generation. Its body is empty, so `body_len` must be `0`. The target is
identified by the common header's `stream_id` and `generation_id`.

The server cancels the active decoder only when both identifiers match the
active stream. A cancellation for an obsolete generation, an unrelated
stream, or a connection with no active stream is ignored. This makes
cancellation idempotent and prevents a delayed cancellation from terminating
a newer generation.

Cancellation does not retract bytes already written to the TCP connection.
The client must discard buffered audio for the cancelled generation and ignore
any late messages carrying its identifiers. The server does not currently send
an acknowledgement or `STREAM_END` in response.

## `PING` and `PONG`

Both messages have empty bodies. A receiver must answer `PING` with `PONG`.

After `HELLO`, the server waits 30 seconds between heartbeat checks and allows
10 seconds for the matching `PONG`. Only one server heartbeat is outstanding
at a time. If the deadline expires, the server closes the connection and
releases its active decoder. A connection that does not send `HELLO` within 30
seconds is also closed. Client-initiated `PING` messages receive an immediate
`PONG`.

## Playback generations

The generation ID protects playback state from late or obsolete data:

1. The client sends `CANCEL_GENERATION` for the active stream and generation.
2. The client discards buffered data for that generation.
3. The client increments `generation_id`.
4. The client sends `START_STREAM` for the new generation.
5. Messages carrying an older generation ID are ignored.

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
- Validate that `AUDIO_FRAME` payload length matches its frame count and the
  active stream format.
- Define `channel_layout` values.
- Define `STREAM_END` reasons.
- Define stable protocol error codes.
- Decide authentication and encryption for remote connections.
- Define compressed FLAC and Opus profiles if remote playback is added.
