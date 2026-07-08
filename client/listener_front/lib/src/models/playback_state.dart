import 'package:listener_front/src/models/track.dart';

final class PlaybackState {
  final Track? track;
  final PlaybackStatus status;
  final String? errorMessage;

  const PlaybackState({
    required this.track,
    required this.status,
    this.errorMessage,
  });

  factory PlaybackState.initial() {
    return PlaybackState(track: null, status: PlaybackStatus.stopped);
  }
}

enum PlaybackStatus { starting, playing, stopped, paused, error }
