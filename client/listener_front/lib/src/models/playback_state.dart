import 'package:listener_front/src/models/playback_queue.dart';
import 'package:equatable/equatable.dart';

final class PlaybackState extends Equatable {
  final PlaybackStatus status;
  final PlaybackQueue? queue;
  final String? errorMessage;

  const PlaybackState({
    required this.status,
    required this.queue,
    this.errorMessage,
  });

  factory PlaybackState.initial() {
    return PlaybackState(status: PlaybackStatus.stopped, queue: null);
  }

  @override
  List<Object?> get props => [status, queue, errorMessage];
}

enum PlaybackStatus { starting, playing, stopped, paused, error }
