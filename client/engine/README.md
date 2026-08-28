# Listener engine

`listener_engine` is the native playback package used by the Flutter client. It
contains the public Dart API, the Dart FFI bindings, the Zig implementation, and
a Dart Native Assets build hook that compiles and bundles the engine.

## Requirements

- Dart 3.12 or later
- Zig
- Xcode command-line tools and the macOS SDK

## Checks

```sh
dart analyze
dart test
zig build test
```

Applications consume the package through its Dart API:

```dart
import 'package:listener_engine/listener_engine.dart';

final engine = ListenerEngine.open();
```

No dylib path is required. The build hook compiles the appropriate native
library and Flutter bundles it into the application.
