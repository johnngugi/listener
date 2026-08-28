import 'dart:ffi' as ffi;

const listenerEngineAssetId = 'package:listener_engine/listener_engine.dart';

final class NativeEngine extends ffi.Opaque {}

typedef PlaybackEventCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Uint32);

final class NativeDiscoveredService extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> fullName;

  @ffi.Size()
  external int fullNameLength;

  external ffi.Pointer<ffi.Uint8> hostTarget;

  @ffi.Size()
  external int hostTargetLength;

  @ffi.Uint16()
  external int port;
}

@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'listener_engine_abi_version',
  assetId: listenerEngineAssetId,
)
external int listenerEngineAbiVersion();

@ffi.Native<ffi.Pointer<NativeEngine> Function()>(
  symbol: 'listener_engine_create',
  assetId: listenerEngineAssetId,
)
external ffi.Pointer<NativeEngine> listenerEngineCreate();

@ffi.Native<ffi.Void Function(ffi.Pointer<NativeEngine>)>(
  symbol: 'listener_engine_destroy',
  assetId: listenerEngineAssetId,
)
external void listenerEngineDestroy(ffi.Pointer<NativeEngine> engine);

@ffi.Native<
  ffi.Uint32 Function(
    ffi.Pointer<NativeEngine>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
    ffi.Uint16,
  )
>(symbol: 'listener_engine_connect', assetId: listenerEngineAssetId)
external int listenerEngineConnect(
  ffi.Pointer<NativeEngine> engine,
  ffi.Pointer<ffi.Uint8> host,
  int hostLength,
  int port,
);

@ffi.Native<
  ffi.Uint32 Function(
    ffi.Pointer<NativeEngine>,
    ffi.Uint64,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
  )
>(symbol: 'listener_engine_start_stream', assetId: listenerEngineAssetId)
external int listenerEngineStartStream(
  ffi.Pointer<NativeEngine> engine,
  int requestedStartFrame,
  ffi.Pointer<ffi.Uint8> playbackId,
  int playbackIdLength,
);

@ffi.Native<ffi.Uint32 Function(ffi.Pointer<NativeEngine>)>(
  symbol: 'listener_engine_stop',
  assetId: listenerEngineAssetId,
)
external int listenerEngineStop(ffi.Pointer<NativeEngine> engine);

@ffi.Native<ffi.Uint32 Function(ffi.Pointer<NativeEngine>)>(
  symbol: 'listener_engine_pause',
  assetId: listenerEngineAssetId,
)
external int listenerEnginePause(ffi.Pointer<NativeEngine> engine);

@ffi.Native<ffi.Uint32 Function(ffi.Pointer<NativeEngine>)>(
  symbol: 'listener_engine_resume',
  assetId: listenerEngineAssetId,
)
external int listenerEngineResume(ffi.Pointer<NativeEngine> engine);

@ffi.Native<
  ffi.Uint32 Function(ffi.Pointer<NativeEngine>, ffi.Pointer<ffi.Uint64>)
>(symbol: 'listener_engine_current_frame', assetId: listenerEngineAssetId)
external int listenerEngineCurrentFrame(
  ffi.Pointer<NativeEngine> engine,
  ffi.Pointer<ffi.Uint64> frame,
);

@ffi.Native<ffi.Uint32 Function(ffi.Pointer<NativeEngine>, ffi.Uint64)>(
  symbol: 'listener_engine_seek',
  assetId: listenerEngineAssetId,
)
external int listenerEngineSeek(
  ffi.Pointer<NativeEngine> engine,
  int targetFrame,
);

@ffi.Native<
  ffi.Uint32 Function(
    ffi.Pointer<NativeEngine>,
    ffi.Pointer<ffi.NativeFunction<PlaybackEventCallbackNative>>,
    ffi.Pointer<ffi.Void>,
  )
>(symbol: 'listener_engine_set_event_callback', assetId: listenerEngineAssetId)
external int listenerEngineSetEventCallback(
  ffi.Pointer<NativeEngine> engine,
  ffi.Pointer<ffi.NativeFunction<PlaybackEventCallbackNative>> callback,
  ffi.Pointer<ffi.Void> context,
);

@ffi.Native<ffi.Uint32 Function(ffi.Pointer<NativeEngine>)>(
  symbol: 'listener_engine_start_discovery',
  assetId: listenerEngineAssetId,
)
external int listenerEngineStartDiscovery(ffi.Pointer<NativeEngine> engine);

@ffi.Native<ffi.Void Function(ffi.Pointer<NativeDiscoveredService>)>(
  symbol: 'listener_discovered_service_release',
  assetId: listenerEngineAssetId,
)
external void listenerDiscoveredServiceRelease(
  ffi.Pointer<NativeDiscoveredService> service,
);
