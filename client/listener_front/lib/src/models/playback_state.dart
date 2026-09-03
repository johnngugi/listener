import 'package:listener_front/src/models/playback_queue.dart';
import 'package:equatable/equatable.dart';

final class PlaybackState extends Equatable {
  final PlaybackStatus status;
  final PlaybackQueue? queue;
  final int currentFrame;
  final double volume;
  final VolumeMode volumeMode;
  final String? errorMessage;

  const PlaybackState({
    required this.status,
    required this.queue,
    this.currentFrame = 0,
    this.volume = 1,
    this.volumeMode = VolumeMode.software,
    this.errorMessage,
  });

  factory PlaybackState.initial() {
    return PlaybackState(
      status: PlaybackStatus.stopped,
      queue: null,
      currentFrame: 0,
      volume: 1,
      volumeMode: VolumeMode.software,
      errorMessage: null,
    );
  }

  PlaybackState copyWith({
    PlaybackStatus? status,
    PlaybackQueue? queue,
    int? currentFrame,
    double? volume,
    VolumeMode? volumeMode,
    String? errorMessage,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      queue: queue ?? this.queue,
      currentFrame: currentFrame ?? this.currentFrame,
      volume: volume ?? this.volume,
      volumeMode: volumeMode ?? this.volumeMode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    queue,
    currentFrame,
    volume,
    volumeMode,
    errorMessage,
  ];
}

enum VolumeMode { fixed, software }

enum PlaybackStatus { starting, playing, stopped, paused, cued, error }
