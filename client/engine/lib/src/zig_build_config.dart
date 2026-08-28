import 'package:code_assets/code_assets.dart';

/// Returns the Zig target expected for a Dart native-asset build.
String zigTarget({
  required OS operatingSystem,
  required Architecture architecture,
  required int macOSVersion,
}) {
  if (operatingSystem != OS.macOS) {
    throw UnsupportedError(
      'Listener engine does not support ${operatingSystem.name}',
    );
  }

  final architectureName = switch (architecture) {
    Architecture.arm64 => 'aarch64',
    Architecture.x64 => 'x86_64',
    _ => throw UnsupportedError(
      'Listener engine does not support ${architecture.name} on macOS',
    ),
  };

  return '$architectureName-macos.$macOSVersion.0';
}

/// Arguments passed to `zig build` for one native-asset architecture.
List<String> zigBuildArguments({
  required String target,
  required String outputDirectory,
  required String cacheDirectory,
  required String macOSSDKPath,
}) {
  return [
    'build',
    '-Dtarget=$target',
    '-Doptimize=ReleaseFast',
    '-Dmacos-sdk-path=$macOSSDKPath',
    '--prefix',
    outputDirectory,
    '--cache-dir',
    cacheDirectory,
  ];
}
