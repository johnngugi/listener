import 'package:listener_front/src/models/playback_queue.dart';
import 'package:equatable/equatable.dart';

final class PlaybackState extends Equatable {
  final PlaybackStatus status;
  final PlaybackQueue? queue;
  final int currentFrame;
  final String? errorMessage;

  const PlaybackState({
    required this.status,
    required this.queue,
    this.currentFrame = 0,
    this.errorMessage,
  });

  factory PlaybackState.initial() {
    return PlaybackState(
      status: PlaybackStatus.stopped,
      queue: null,
      currentFrame: 0,
      errorMessage: null,
    );
  }

  PlaybackState copyWith({
    PlaybackStatus? status,
    PlaybackQueue? queue,
    int? currentFrame,
    String? errorMessage,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      queue: queue ?? this.queue,
      currentFrame: currentFrame ?? this.currentFrame,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, queue, currentFrame, errorMessage];
}

enum PlaybackStatus { starting, playing, stopped, paused, cued, error }
