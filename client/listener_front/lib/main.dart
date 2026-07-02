import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';

const _listenerEngineDylibEnv = "LISTENER_ENGINE_DYLIB";
const _devListenerEngineDylibPath =
    "/Users/johnngugi/Coding/listener/client/engine/zig-out/lib/liblistener_engine.dylib";

void main() {
  final listenerEngine = ffi.DynamicLibrary.open(_listenerEngineLibraryPath());

  final engineVersion = listenerEngine
      .lookupFunction<ffi.Uint32 Function(), int Function()>(
        "listener_engine_abi_version",
      );

  final sendHello = listenerEngine
      .lookupFunction<ffi.Void Function(), void Function()>(
        "listener_engine_send_hello",
      );

  debugPrint("listener engine ABI version: ${engineVersion()}");

  sendHello();
  runApp(const MainApp());
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

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              //
            },
            child: Text("test"),
          ),
        ),
      ),
    );
  }
}
