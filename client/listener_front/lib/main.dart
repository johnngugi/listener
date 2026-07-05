import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

const _listenerEngineDylibEnv = "LISTENER_ENGINE_DYLIB";
const _devListenerEngineDylibPath =
    "/Users/johnngugi/Coding/listener/client/engine/zig-out/lib/liblistener_engine.dylib";

final class Engine extends ffi.Opaque {}

typedef _AbiVersionNative = ffi.Uint32 Function();
typedef _AbiVersionDart = int Function();

typedef _CreateNative = ffi.Pointer<Engine> Function();
typedef _CreateDart = ffi.Pointer<Engine> Function();

typedef _DestroyNative = ffi.Void Function(ffi.Pointer<Engine>);
typedef _DestroyDart = void Function(ffi.Pointer<Engine>);

typedef _ConnectNative =
    ffi.Uint32 Function(
      ffi.Pointer<Engine>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Uint16,
    );
typedef _ConnectDart =
    int Function(ffi.Pointer<Engine>, ffi.Pointer<ffi.Uint8>, int, int);

typedef _StartStreamNative =
    ffi.Uint32 Function(
      ffi.Pointer<Engine>,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
    );
typedef _StartStreamDart =
    int Function(
      ffi.Pointer<Engine>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
    );

typedef _StopNative = ffi.Uint32 Function(ffi.Pointer<Engine>);
typedef _StopDart = int Function(ffi.Pointer<Engine>);

enum ListenerStatus {
  ok(0),
  nullEngine(1),
  invalidArgument(2),
  alreadyConnected(3),
  invalidHost(4),
  connectFailed(5),
  handshakeFailed(6),
  protocolError(7),
  outOfMemory(8),
  unexpected(255);

  const ListenerStatus(this.code);

  final int code;

  static ListenerStatus fromCode(int code) {
    return ListenerStatus.values.firstWhere(
      (status) => status.code == code,
      orElse: () => ListenerStatus.unexpected,
    );
  }
}

final class ListenerEngine {
  ListenerEngine._(this._library) {
    _abiVersion = _library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
      "listener_engine_abi_version",
    );

    _create = _library.lookupFunction<_CreateNative, _CreateDart>(
      "listener_engine_create",
    );

    _destroy = _library.lookupFunction<_DestroyNative, _DestroyDart>(
      'listener_engine_destroy',
    );

    _connect = _library.lookupFunction<_ConnectNative, _ConnectDart>(
      'listener_engine_connect',
    );

    _startStream = _library.lookupFunction<
      _StartStreamNative,
      _StartStreamDart
    >('listener_engine_start_stream');

    _stop = _library.lookupFunction<_StopNative, _StopDart>(
      'listener_engine_stop',
    );

    _engine = _create();
    if (_engine == ffi.nullptr) {
      throw StateError("listener_engine_create returned null");
    }
  }

  factory ListenerEngine.open() {
    return ListenerEngine._(
      ffi.DynamicLibrary.open(_listenerEngineLibraryPath()),
    );
  }

  final ffi.DynamicLibrary _library;

  late final _AbiVersionDart _abiVersion;
  late final _CreateDart _create;
  late final _DestroyDart _destroy;
  late final _ConnectDart _connect;
  late final _StartStreamDart _startStream;
  late final _StopDart _stop;
  late final ffi.Pointer<Engine> _engine;

  bool _closed = false;

  int get abiVersion => _abiVersion();

  ListenerStatus connect({String host = '127.0.0.1', int port = 5778}) {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    if (host.isEmpty) {
      throw ArgumentError.value(host, 'host', 'Host cannot be empty');
    }

    if (port < 0 || port > 0xffff) {
      throw RangeError.range(port, 0, 0xffff, 'port');
    }

    final hostBytes = utf8.encode(host);
    final hostPtr = malloc<ffi.Uint8>(hostBytes.length);

    try {
      hostPtr.asTypedList(hostBytes.length).setAll(0, hostBytes);

      final code = _connect(_engine, hostPtr, hostBytes.length, port);

      return ListenerStatus.fromCode(code);
    } finally {
      malloc.free(hostPtr);
    }
  }

  ListenerStatus startStream({
    required String playbackId,
    required String mediaPath,
    int requestedStartFrame = 0,
  }) {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    if (requestedStartFrame < 0) {
      throw RangeError.range(
        requestedStartFrame,
        0,
        null,
        'requestedStartFrame',
      );
    }

    final playbackIdBytes = utf8.encode(playbackId);
    final mediaPathBytes = utf8.encode(mediaPath);
    final playbackIdPtr = malloc<ffi.Uint8>(playbackIdBytes.length);
    final mediaPathPtr = malloc<ffi.Uint8>(mediaPathBytes.length);

    try {
      playbackIdPtr.asTypedList(playbackIdBytes.length).setAll(
        0,
        playbackIdBytes,
      );
      mediaPathPtr.asTypedList(mediaPathBytes.length).setAll(0, mediaPathBytes);

      final code = _startStream(
        _engine,
        requestedStartFrame,
        playbackIdPtr,
        playbackIdBytes.length,
        mediaPathPtr,
        mediaPathBytes.length,
      );

      return ListenerStatus.fromCode(code);
    } finally {
      malloc.free(playbackIdPtr);
      malloc.free(mediaPathPtr);
    }
  }

  ListenerStatus stop() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(_stop(_engine));
  }

  void close() {
    if (_closed) return;
    _destroy(_engine);
    _closed = true;
  }
}

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ListenerEngine? _engine;
  String _status = "Loading engine...";

  @override
  void initState() {
    super.initState();

    try {
      final engine = ListenerEngine.open();
      _engine = engine;
      _status = "Engine loaded. ABI ${engine.abiVersion}.";
    } catch (err) {
      _status = "Failed to load engine: $err";
    }
  }

  @override
  void dispose() {
    _engine?.close();
    super.dispose();
  }

  void _connect() {
    final engine = _engine;
    if (engine == null) return;

    setState(() {
      _status = "Connecting...";
    });

    try {
      final status = engine.connect();

      setState(() {
        _status = "Connect result: ${status.name} (${status.code})";
      });
    } catch (err) {
      setState(() {
        _status = "Connect failed: $err";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_status, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _engine == null ? null : _connect,
                child: const Text("Connect"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _listenerEngineLibraryPath() {
  const dartDefinePath = String.fromEnvironment(_listenerEngineDylibEnv);
  if (dartDefinePath.isNotEmpty) {
    return dartDefinePath;
  }

  final environmentPath = Platform.environment[_listenerEngineDylibEnv];
  if (environmentPath != null && environmentPath.isNotEmpty) {
    return environmentPath;
  }

  if (Platform.isMacOS) {
    return _devListenerEngineDylibPath;
  }

  throw UnsupportedError(
    "Set $_listenerEngineDylibEnv to the listener engine dynamic library path "
    "for ${Platform.operatingSystem}.",
  );
}
