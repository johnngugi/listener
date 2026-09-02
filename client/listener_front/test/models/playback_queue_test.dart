import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/models/playback_queue.dart';
import 'package:listener_front/src/models/track.dart';

void main() {
  group('PlaybackQueue', () {
    test('reorders tracks while preserving the current track', () {
      final tracks = [_track(1), _track(2), _track(3), _track(4)];
      final queue = PlaybackQueue(tracks: tracks, currentIndex: 2);

      final reordered = queue.reorder(0, 3);

      expect(reordered.tracks, [tracks[1], tracks[2], tracks[3], tracks[0]]);
      expect(reordered.currentTrack, tracks[2]);
      expect(reordered.currentIndex, 1);
    });

    test('moves the current track and updates its index', () {
      final tracks = [_track(1), _track(2), _track(3)];
      final queue = PlaybackQueue(tracks: tracks, currentIndex: 0);

      final reordered = queue.reorder(0, 2);

      expect(reordered.tracks, [tracks[1], tracks[2], tracks[0]]);
      expect(reordered.currentTrack, tracks[0]);
      expect(reordered.currentIndex, 2);
    });

    test('removes a queued track and preserves the current track', () {
      final tracks = [_track(1), _track(2), _track(3)];
      final queue = PlaybackQueue(tracks: tracks, currentIndex: 1);

      final remaining = queue.removeAt(0);

      expect(remaining.tracks, [tracks[1], tracks[2]]);
      expect(remaining.currentTrack, tracks[1]);
      expect(remaining.currentIndex, 0);
    });

    test('does not allow removing the current track', () {
      final queue = PlaybackQueue(tracks: [_track(1)], currentIndex: 0);

      expect(() => queue.removeAt(0), throwsStateError);
    });
  });
}

Track _track(int number) => Track(
  id: 'track-$number',
  number: '$number',
  title: 'Track $number',
  artist: 'Artist',
  album: 'Album',
  releaseDate: '2026',
  dateAdded: 'Today',
  plays: '0',
  durationMilliseconds: 180000,
  codec: 'flac',
  sampleRate: 1000,
  bitsPerSample: 24,
);
