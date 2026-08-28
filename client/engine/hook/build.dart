import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:listener_engine/src/zig_build_config.dart';

const _assetName = 'listener_engine.dart';
const _libraryPath = 'lib/liblistener_engine.dylib';
const _ignoredDirectories = {
  '.dart_tool',
  '.git',
  '.zig-cache',
  'zig-cache',
  'zig-out',
};

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final target = zigTarget(
      operatingSystem: codeConfig.targetOS,
      architecture: codeConfig.targetArchitecture,
      macOSVersion: codeConfig.macOS.targetVersion,
    );
    final sdkPath = await _macOSSDKPath();
    final cacheDirectory = input.outputDirectory.resolve('zig-cache/');

    final result = await Process.run(
      'zig',
      zigBuildArguments(
        target: target,
        outputDirectory: input.outputDirectory.toFilePath(),
        cacheDirectory: cacheDirectory.toFilePath(),
        macOSSDKPath: sdkPath,
      ),
      workingDirectory: input.packageRoot.toFilePath(),
    );

    if ((result.stdout as String).isNotEmpty) {
      stdout.write(result.stdout);
    }
    if ((result.stderr as String).isNotEmpty) {
      stderr.write(result.stderr);
    }
    if (result.exitCode != 0) {
      throw StateError(
        'Zig failed to build listener_engine for $target '
        '(exit code ${result.exitCode})',
      );
    }

    final library = input.outputDirectory.resolve(_libraryPath);
    if (!File.fromUri(library).existsSync()) {
      throw StateError('Zig did not produce ${library.toFilePath()}');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );

    output.dependencies.addAll(
      _zigDependencies(Directory.fromUri(input.packageRoot)),
    );
    output.dependencies.addAll(
      _zigDependencies(
        Directory.fromUri(
          input.packageRoot.resolve('../../packages/lstn_protocol/'),
        ),
      ),
    );
  });
}

Future<String> _macOSSDKPath() async {
  final result = await Process.run('xcrun', [
    '--sdk',
    'macosx',
    '--show-sdk-path',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Unable to locate the macOS SDK: ${result.stderr}');
  }

  final path = (result.stdout as String).trim();
  if (path.isEmpty) {
    throw StateError('xcrun returned an empty macOS SDK path');
  }
  return path;
}

Iterable<Uri> _zigDependencies(Directory root) sync* {
  for (final entity in root.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (entity is Directory) {
      if (!_ignoredDirectories.contains(name)) {
        yield* _zigDependencies(entity);
      }
      continue;
    }

    if (entity is File && (name.endsWith('.zig') || name == 'build.zig.zon')) {
      yield entity.uri;
    }
  }
}
