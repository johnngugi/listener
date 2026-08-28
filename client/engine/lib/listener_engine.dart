// Copyright (c) 2026 Listener contributors. All rights reserved.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:listener_engine/src/bindings.dart';
import 'package:listener_engine/src/playback_engine_event.dart';

export 'src/playback_engine_event.dart';

const _listenerEngineAbiVersion = 1;

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
  noActiveStream(9),
  invalidSeekFrame(10),
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

abstract interface class PlaybackEngine {
  Stream<PlaybackEngineEvent> get events;

  Future<DiscoveredServiceEvent> discoverService();

  ListenerStatus startStream({
    required String playbackId,
    int requestedStartFrame = 0,
  });

  ListenerStatus stop();

  ListenerStatus pause();

  ListenerStatus resume();

  ({ListenerStatus status, int frame}) currentFrame();

  ListenerStatus seek(int targetFrame);

  void close();
}

final class ListenerEngine implements PlaybackEngine {
  ListenerEngine._() {
    final abiVersion = listenerEngineAbiVersion();
    if (abiVersion != _listenerEngineAbiVersion) {
      throw StateError(
        'Unsupported listener engine ABI $abiVersion; '
        'expected $_listenerEngineAbiVersion',
      );
    }

    _engine = listenerEngineCreate();
    if (_engine == ffi.nullptr) {
      throw StateError("listener_engine_create returned null");
    }

    _eventCallback = ffi.NativeCallable<PlaybackEventCallbackNative>.listener(
      _handlePlaybackEvent,
    );
    final callbackStatus = ListenerStatus.fromCode(
      listenerEngineSetEventCallback(
        _engine,
        _eventCallback.nativeFunction,
        ffi.nullptr,
      ),
    );
    if (callbackStatus != ListenerStatus.ok) {
      _eventCallback.close();
      listenerEngineDestroy(_engine);
      throw StateError(
        'Failed to register playback event callback: ${callbackStatus.name}',
      );
    }

    _currentFrameOut = calloc<ffi.Uint64>();
  }

  factory ListenerEngine.open() => ListenerEngine._();

  late final ffi.Pointer<NativeEngine> _engine;
  late final ffi.NativeCallable<PlaybackEventCallbackNative> _eventCallback;
  late final ffi.Pointer<ffi.Uint64> _currentFrameOut;

  final StreamController<PlaybackEngineEvent> _events =
      StreamController<PlaybackEngineEvent>.broadcast();

  Completer<DiscoveredServiceEvent>? _discoveryCompleter;

  bool _closed = false;

  int get abiVersion => listenerEngineAbiVersion();

  @override
  Stream<PlaybackEngineEvent> get events => _events.stream;

  @override
  Future<DiscoveredServiceEvent> discoverService() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    if (_discoveryCompleter != null) {
      throw StateError('Service discovery is already running');
    }

    final completer = Completer<DiscoveredServiceEvent>();
    _discoveryCompleter = completer;

    final status = ListenerStatus.fromCode(
      listenerEngineStartDiscovery(_engine),
    );
    if (status != ListenerStatus.ok) {
      _discoveryCompleter = null;
      throw StateError('Failed to start service discovery: ${status.name}');
    }

    return completer.future;
  }

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

      final code = listenerEngineConnect(
        _engine,
        hostPtr,
        hostBytes.length,
        port,
      );

      return ListenerStatus.fromCode(code);
    } finally {
      malloc.free(hostPtr);
    }
  }

  @override
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
      final code = listenerEngineStartStream(
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

  @override
  ListenerStatus stop() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(listenerEngineStop(_engine));
  }

  @override
  ListenerStatus pause() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(listenerEnginePause(_engine));
  }

  @override
  ListenerStatus resume() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    return ListenerStatus.fromCode(listenerEngineResume(_engine));
  }

  @override
  ({ListenerStatus status, int frame}) currentFrame() {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    _currentFrameOut.value = 0;
    final result = listenerEngineCurrentFrame(_engine, _currentFrameOut);
    return (
      status: ListenerStatus.fromCode(result),
      frame: _currentFrameOut.value,
    );
  }

  @override
  ListenerStatus seek(int targetFrame) {
    if (_closed) {
      throw StateError('ListenerEngine is closed');
    }

    if (targetFrame < 0) {
      throw RangeError.value(targetFrame, 'targetFrame');
    }

    return ListenerStatus.fromCode(listenerEngineSeek(_engine, targetFrame));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    calloc.free(_currentFrameOut);
    listenerEngineDestroy(_engine);
    _eventCallback.close();
    unawaited(_events.close());
  }

  void _handlePlaybackEvent(ffi.Pointer<ffi.Void> context, int event) {
    switch (event) {
      case 1:
        if (!_closed) {
          _events.add(Ended());
        }
      case 2:
        if (!_closed) {
          _events.add(Failed());
        }
      case 3:
        _handleDiscoveredService(context);
    }
  }

  void _handleDiscoveredService(ffi.Pointer<ffi.Void> context) {
    final completer = _discoveryCompleter;
    _discoveryCompleter = null;

    if (context == ffi.nullptr) {
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StateError('Service discovery returned a null service'),
        );
      }
      return;
    }

    final discoveredServicePointer = context.cast<NativeDiscoveredService>();

    try {
      final serviceRef = discoveredServicePointer.ref;
      final service = DiscoveredServiceEvent(
        fullName: utf8.decode(
          serviceRef.fullName.asTypedList(serviceRef.fullNameLength),
        ),
        host: utf8.decode(
          serviceRef.hostTarget.asTypedList(serviceRef.hostTargetLength),
        ),
        port: serviceRef.port,
      );

      if (!_closed && completer != null && !completer.isCompleted) {
        completer.complete(service);
      }
    } catch (error, stackTrace) {
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    } finally {
      listenerDiscoveredServiceRelease(discoveredServicePointer);
    }
  }
}
