import 'package:equatable/equatable.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/utils/result.dart';

class PlaybackQueue extends Equatable {
  final List<Track> tracks;
  final int currentIndex;

  const PlaybackQueue({required this.tracks, required this.currentIndex});

  Track get currentTrack => tracks[currentIndex];

  Result<Track> get previousTrack {
    if (currentIndex == 0) {
      return Result.error(Exception('No previous track'));
    }

    return Result.ok(tracks[currentIndex - 1]);
  }

  Result<Track> get nextTrack {
    if (currentIndex == tracks.length - 1) {
      return Result.error(Exception('No next track'));
    }

    return Result.ok(tracks[currentIndex + 1]);
  }

  @override
  List<Object?> get props => [tracks, currentIndex];
}
