// Copyright (c) 2026 Listener contributors. All rights reserved.

/// A local audio output reported by the platform audio backend.
final class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  /// An opaque, persistent identifier understood only by the native backend.
  final String id;

  /// The human-readable device name supplied by the operating system.
  final String name;

  /// Whether this is currently the operating system's default output.
  final bool isDefault;
}
