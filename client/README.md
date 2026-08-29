# Listener client

The client workspace contains the macOS Flutter application and the native
playback engine it consumes.

```text
listener_front/  Flutter UI, state management, generated gRPC types, and tests
engine/          Dart API, FFI bindings, Zig playback engine, and CoreAudio output
```

The Flutter layer uses gRPC for playback control, library browsing, and artwork.
Audio travels over the separate LSTN TCP connection owned by the Zig engine;
high-frequency audio never passes through Dart or Flutter.

## Run the app

Start the Listener server, then run:

```sh
cd client/listener_front
flutter pub get
flutter run -d macos
```

Zig 0.16.0+, Flutter/Dart 3.12.2+, Xcode command-line tools, and the macOS SDK
are required. Flutter invokes the engine's Native Assets hook, which builds and
bundles `liblistener_engine.dylib` automatically.

See the component READMEs for [the Flutter application](listener_front/README.md)
and [the native engine](engine/README.md), or read the
[client architecture](../docs/client-architecture.md).
