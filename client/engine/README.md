# Listener engine

`listener_engine` is the native playback package used by the Flutter client. It
provides a Dart API backed by a Zig dynamic library built through Dart Native
Assets.

The engine owns:

- Bonjour discovery and the persistent LSTN TCP connection.
- Playback generations, heartbeats, flow-control credit, and buffering.
- Play, pause, resume, stop, seek, and playback events.
- CoreAudio device enumeration and output configuration.
- Real-time PCM rendering and software gain.

The current production output backend is macOS CoreAudio. Unit and integration
tests use an in-memory Zig backend.

## Requirements

- Dart 3.12.2 or later.
- Zig 0.16.0 or later.
- Xcode command-line tools and the macOS SDK.

## Use from Dart

```dart
import 'package:listener_engine/listener_engine.dart';

final engine = ListenerEngine.open();
try {
  final connection = engine.connect(host: '127.0.0.1', port: 5778);
  if (connection != ListenerStatus.ok) {
    throw StateError('Listener connection failed: ${connection.name}');
  }

  final result = engine.startStream(playbackId: 'playback-1');
  if (result != ListenerStatus.ok) {
    throw StateError('Playback failed: ${result.name}');
  }
} finally {
  engine.close();
}
```

The playback ID comes from the gRPC `Start` call. Applications do not provide a
dynamic-library path: the build hook compiles `liblistener_engine.dylib`, and
Flutter bundles it into the consuming macOS application.

## Checks

```sh
dart pub get
dart analyze
dart test
zig build test
```

Run the repository-level `zig build test` from the project root to exercise the
engine and server together.
