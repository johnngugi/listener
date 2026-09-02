import 'package:equatable/equatable.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/utils/result.dart';

class PlaybackQueue extends Equatable {
  final List<Track> tracks;
  final int currentIndex;

  const PlaybackQueue({required this.tracks, required this.currentIndex});

  Track get currentTrack => tracks[currentIndex];

  bool get hasPrevious => currentIndex > 0;

  bool get hasNext => currentIndex < tracks.length - 1;

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

  PlaybackQueue reorder(int oldIndex, int newIndex) {
    RangeError.checkValidIndex(oldIndex, tracks, 'oldIndex');
    RangeError.checkValidIndex(newIndex, tracks, 'newIndex');

    final reordered = tracks.toList();
    final movedTrack = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, movedTrack);

    var nextCurrentIndex = currentIndex;
    if (oldIndex == currentIndex) {
      nextCurrentIndex = newIndex;
    } else {
      if (oldIndex < nextCurrentIndex) nextCurrentIndex--;
      if (newIndex <= nextCurrentIndex) nextCurrentIndex++;
    }

    return PlaybackQueue(
      tracks: List<Track>.unmodifiable(reordered),
      currentIndex: nextCurrentIndex,
    );
  }

  PlaybackQueue removeAt(int index) {
    RangeError.checkValidIndex(index, tracks, 'index');
    if (index == currentIndex) {
      throw StateError('The current track cannot be removed from the queue');
    }

    final remaining = tracks.toList()..removeAt(index);
    return PlaybackQueue(
      tracks: List<Track>.unmodifiable(remaining),
      currentIndex: index < currentIndex ? currentIndex - 1 : currentIndex,
    );
  }

  @override
  List<Object?> get props => [tracks, currentIndex];
}
