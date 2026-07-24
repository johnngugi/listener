import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

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
    );
typedef _StartStreamDart =
    int Function(ffi.Pointer<Engine>, int, ffi.Pointer<ffi.Uint8>, int);

typedef _StopNative = ffi.Uint32 Function(ffi.Pointer<Engine>);
typedef _StopDart = int Function(ffi.Pointer<Engine>);

typedef _PauseNative = ffi.Uint32 Function(ffi.Pointer<Engine>);
typedef _PauseDart = int Function(ffi.Pointer<Engine>);

typedef _ResumeNative = ffi.Uint32 Function(ffi.Pointer<Engine>);
typedef _ResumeDart = int Function(ffi.Pointer<Engine>);

typedef _PlaybackEventCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Uint32);
typedef _SetEventCallbackNative =
    ffi.Uint32 Function(
      ffi.Pointer<Engine>,
      ffi.Pointer<ffi.NativeFunction<_PlaybackEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef _SetEventCallbackDart =
    int Function(
      ffi.Pointer<Engine>,
      ffi.Pointer<ffi.NativeFunction<_PlaybackEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

enum PlaybackEngineEvent { ended, failed }

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

    _startStream = _library
        .lookupFunction<_StartStreamNative, _StartStreamDart>(
          'listener_engine_start_stream',
        );

    _stop = _library.lookupFunction<_StopNative, _StopDart>(
      'listener_engine_stop',
    );

    _pause = _library.lookupFunction<_PauseNative, _PauseDart>(
      'listener_engine_pause',
    );

    _resume = _library.lookupFunction<_ResumeNative, _ResumeDart>(
      'listener_engine_resume',
    );

    _setEventCallback = _library
        .lookupFunction<_SetEventCallbackNative, _SetEventCallbackDart>(
          'listener_engine_set_event_callback',
        );

    _engine = _create();
    if (_engine == ffi.nullptr) {
      throw StateError("listener_engine_create returned null");
    }

    _eventCallback = ffi.NativeCallable<_PlaybackEventCallbackNative>.listener(
      _handlePlaybackEvent,
    );
    final callbackStatus = ListenerStatus.fromCode(
      _setEventCallback(_engine, _eventCallback.nativeFunction, ffi.nullptr),
    );
    if (callbackStatus != ListenerStatus.ok) {
      _eventCallback.close();
      _destroy(_engine);
      throw StateError(
        'Failed to register playback event callback: ${callbackStatus.name}',
      );
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
  late final _PauseDart _pause;
  late final _ResumeDart _resume;
  late final _SetEventCallbackDart _setEventCallback;
  late final ffi.Pointer<Engine> _engine;
  late final ffi.NativeCallable<_PlaybackEventCallbackNative> _eventCallback;

  final StreamController<PlaybackEngineEvent> _events =
      StreamController<PlaybackEngineEvent>.broadcast();

  bool _closed = false;

  int get abiVersion => _abiVersion();
  Stream<PlaybackEngineEvent> get events => _events.stream;

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
    final playbackIdPtr = malloc<ffi.Uint8>(playbackIdBytes.length);

    try {
      playbackIdPtr
          .asTypedList(playbackIdBytes.length)
          .setAll(0, playbackIdBytes);
      final code = _startStream(
        _engine,
        requestedStartFrame,
        playbackIdPtr,
        playbackIdBytes.length,
      );

      return ListenerStatus.fromCode(code);
    } finally {
      malloc.free(playbackIdPtr);
    }
  }

  ListenerStatus stop() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(_stop(_engine));
  }

  ListenerStatus pause() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(_pause(_engine));
  }

  ListenerStatus resume() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(_resume(_engine));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _destroy(_engine);
    _eventCallback.close();
    unawaited(_events.close());
  }

  void _handlePlaybackEvent(ffi.Pointer<ffi.Void> _, int event) {
    if (_closed) return;

    switch (event) {
      case 1:
        _events.add(PlaybackEngineEvent.ended);
      case 2:
        _events.add(PlaybackEngineEvent.failed);
    }
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
