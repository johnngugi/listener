// Copyright (c) 2026 John Ngugi
// SPDX-License-Identifier: MIT

import 'package:code_assets/code_assets.dart';
import 'package:listener_engine/src/zig_build_config.dart';
import 'package:test/test.dart';

void main() {
  group('zigTarget', () {
    test('maps supported macOS architectures', () {
      expect(
        zigTarget(
          operatingSystem: OS.macOS,
          architecture: Architecture.arm64,
          macOSVersion: 13,
        ),
        'aarch64-macos.13.0',
      );
      expect(
        zigTarget(
          operatingSystem: OS.macOS,
          architecture: Architecture.x64,
          macOSVersion: 13,
        ),
        'x86_64-macos.13.0',
      );
    });

    test('rejects unsupported operating systems', () {
      expect(
        () => zigTarget(
          operatingSystem: OS.linux,
          architecture: Architecture.x64,
          macOSVersion: 13,
        ),
        throwsUnsupportedError,
      );
    });
  });

  test('zigBuildArguments isolates output and cache directories', () {
    expect(
      zigBuildArguments(
        target: 'aarch64-macos.13.0',
        outputDirectory: '/tmp/output',
        cacheDirectory: '/tmp/cache',
        macOSSDKPath: '/tmp/MacOSX.sdk',
      ),
      [
        'build',
        '-Dtarget=aarch64-macos.13.0',
        '-Doptimize=ReleaseFast',
        '-Dmacos-sdk-path=/tmp/MacOSX.sdk',
        '--prefix',
        '/tmp/output',
        '--cache-dir',
        '/tmp/cache',
      ],
    );
  });
}
