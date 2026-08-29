# Listener

**Your lossless music library, everywhere on your local network.**

Listener is a network music player allowing you to stream your own collection
of music files from a native desktop client. You can store your library on one
machine and play it from any device on the same network. Listener provides an
intuitive interface, bit-perfect playback, and straightforward setup.

Listener pairs a Zig media server with a Flutter desktop app and a native Zig
playback engine. The server handles indexing and decoding; the client sends the
resulting PCM directly to CoreAudio, with control over the output device,
exclusive mode, and volume behavior.

## Why Listener?

Most music players are built around files stored on the listening device or a
catalog controlled by a streaming service. Listener separates **where your
music lives** from **where you listen to it** while keeping the whole experience
inside your network.

- **One library, no syncing.** Add music to the server and every Listener client
  sees the same indexed collection, metadata, and artwork.
- **Your collection stays yours.** Listener needs no hosted service or account,
  and server filesystem paths are never exposed to clients.
- **A deliberate lossless signal path.** Audio is decoded on the server,
  transported as PCM, and rendered by a native engine. Choose a CoreAudio
  device, request exclusive access, or use fixed volume for unity gain.
- **Made for the local network.** Bonjour discovery makes nearby servers feel
  automatic, while manual connection remains available when you need it.
- **Built as a system, not a remote file browser.** Separate control and media
  protocols keep library operations responsive while the audio path manages
  buffering, flow control, cancellation, and recovery.

## Project status

Listener is usable today and under active development. The current client is
for macOS, the library supports FLAC, and connections are unencrypted and
unauthenticated. Run it only on a trusted network for now.

## What works

- Recursive FLAC indexing from the server user's `~/Music` directory.
- Metadata and embedded or sidecar album-art extraction.
- Paginated, sortable library browsing in the Flutter client.
- Bonjour discovery with manual server selection as a fallback.
- Play, pause, resume, stop, seek, previous/next, and playback-position updates.
- CoreAudio output-device selection, exclusive-mode configuration, and software
  volume.
- A persistent LSTN media connection with buffering, flow control, heartbeats,
  cancellation, and reconnect-on-next-stream behavior.

## Architecture

```text
Flutter UI ── gRPC :5779 ──> Zig control/library server
    │
    └── Dart FFI ──> Zig playback engine ── LSTN TCP :5778 ──> Zig media server
                          │
                          └── CoreAudio
```

The gRPC API carries control, library metadata, and artwork. The custom LSTN
protocol carries decoded PCM audio and flow-control messages. Media paths stay
on the server.

## Repository layout

```text
client/                  Flutter application and native playback engine
packages/lstn_protocol/  Shared Zig implementation of the LSTN wire protocol
server/                  Zig server, library database, decoder, and transports
proto/                   Protobuf control and library API
docs/                    Architecture, protocol, API, and licensing notes
tests/                   Repository-level integration tests
```

## Requirements

The current implementation targets macOS and requires:

- Zig 0.16.0 or later.
- Flutter with Dart 3.12.2 or later.
- Xcode command-line tools and the macOS SDK.
- FFmpeg shared libraries (`libavformat`, `libavcodec`, `libavutil`, and
  `libswscale`).
- The gRPC C library and SQLite 3.

The Zig build files use Homebrew paths under `/opt/homebrew`, so they work as
written on Apple Silicon Homebrew installations. Install the native dependencies
with:

```sh
brew install ffmpeg grpc
```

Homebrew's `ffmpeg` formula is GPL-3.0-or-later. Listener currently publishes
source rather than a compiled server distribution; users install FFmpeg and
compile Listener locally. The licensing of the exact FFmpeg build must be
reviewed before adding compiled server releases.

## Run Listener

Start the server first. At startup it scans `~/Music` for `.flac` files, creates
or migrates its SQLite database, registers `_lstn._tcp` through Bonjour, and
listens on TCP ports 5778 and 5779.

```sh
cd server
zig build run
```

By default, server state is stored in
`~/Library/Application Support/Listener`. Set `LISTENER_DATA_DIR` to an absolute
path to use a different data directory.

In another terminal, run the Flutter client:

```sh
cd client/listener_front
flutter pub get
flutter run -d macos
```

The client first tries the last successful server, then starts Bonjour
discovery. The server settings screen also accepts a host and LSTN port
manually; the current gRPC port remains fixed at 5779.

## Tests and analysis

```sh
# Server unit tests
cd server && zig build test

# Repository-level server/client integration tests
zig build test

# Native engine Dart and Zig tests
cd client/engine && dart test && zig build test

# Flutter tests and static analysis
cd client/listener_front && flutter test && flutter analyze
```

The root integration build and the server build both require the FFmpeg and
gRPC native libraries.

## Documentation

- [Client architecture](docs/client-architecture.md)
- [LSTN media protocol](docs/protocol.md)
- [gRPC server adapter](docs/grpc/server.md)

## License

Listener is available under the [MIT License](LICENSE). Third-party components,
including FFmpeg, retain their own licenses.
