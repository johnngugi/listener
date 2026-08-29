# Listener Flutter client

`listener_front` is the macOS desktop UI for Listener. It discovers or connects
to a Listener server, loads its FLAC library, fetches artwork, and coordinates
gRPC control calls with the native `listener_engine` media connection.

## Current features

- Restores the last successful server and falls back to Bonjour discovery.
- Supports manual server selection and reconnection.
- Displays a paginated library with server-side sorting.
- Loads and caches album artwork through gRPC.
- Supports play, pause, resume, stop, seek, previous, and next.
- Shows playback position, software/fixed volume modes, and mute.
- Lists CoreAudio output devices and supports exclusive-mode configuration.
- Switches between a persistent sidebar and a drawer below 1100 logical pixels.

## Run

Start the server from the repository's `server` directory, then:

```sh
flutter pub get
flutter run -d macos
```

The local engine package is referenced through `../engine`. Its Native Assets
hook requires Zig 0.16.0+, Xcode command-line tools, and the macOS SDK.

The app uses the discovered or manually entered host with LSTN port 5778 by
default. Its gRPC client currently uses insecure port 5779. Use Listener only on
a trusted network until authentication and transport security are implemented.

## Generated protobuf code

Generated Dart files live under `lib/src/generated/listener/v1`. The source
schema is `../../proto/listener/v1/listener.proto`. Keep the generated files in
sync whenever that schema changes.

## Checks

```sh
flutter analyze
flutter test
```
