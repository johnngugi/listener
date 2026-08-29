// Copyright (c) 2026 John Ngugi
// SPDX-License-Identifier: MIT

/// A local audio output reported by the platform audio backend.
final class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
    this.capabilities = const AudioOutputCapabilities(),
  });

  /// An opaque, persistent identifier understood only by the native backend.
  final String id;

  /// The human-readable device name supplied by the operating system.
  final String name;

  /// Whether this is currently the operating system's default output.
  final bool isDefault;

  /// Portable features this output can provide.
  final AudioOutputCapabilities capabilities;
}

/// Optional output features supported by a device.
final class AudioOutputCapabilities {
  const AudioOutputCapabilities({this.supportsExclusiveMode = false});

  /// Whether other applications can be prevented from using the output.
  final bool supportsExclusiveMode;
}

/// Portable settings applied when the next output stream is opened.
final class AudioOutputConfiguration {
  const AudioOutputConfiguration({this.exclusiveMode = false});

  /// Whether Listener should request sole access to the selected output.
  final bool exclusiveMode;
}
