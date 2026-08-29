import 'package:flutter_test/flutter_test.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/models/output_device_state.dart';
import 'package:listener_front/src/models/playback_queue.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/signal_path.dart';
import 'package:listener_front/src/models/track.dart';

void main() {
  group('SignalPath', () {
    test('reports bit-perfect for lossless unity-gain exclusive playback', () {
      final result = SignalPath.evaluate(
        _playback(),
        _output(exclusiveMode: true),
      );

      expect(result.quality, SignalPathQuality.bitPerfect);
      expect(result.title, 'Bit-perfect');
    });

    test('reports each reason the path is not bit-perfect', () {
      final result = SignalPath.evaluate(
        _playback(codec: 'aac', volumeMode: VolumeMode.software, volume: 0.5),
        _output(exclusiveMode: false),
      );

      expect(result.quality, SignalPathQuality.processed);
      expect(result.reasons, [
        'The source codec is lossy.',
        'Shared output allows macOS to mix or resample audio.',
        'Software volume is changing the PCM samples.',
      ]);
    });

    test('software volume at unity remains bit-perfect', () {
      final result = SignalPath.evaluate(
        _playback(volumeMode: VolumeMode.software),
        _output(exclusiveMode: true),
      );

      expect(result.quality, SignalPathQuality.bitPerfect);
    });
  });
}

PlaybackState _playback({
  String codec = 'flac',
  VolumeMode volumeMode = VolumeMode.fixed,
  double volume = 1,
}) {
  final track = Track(
    id: 'track-1',
    number: '1',
    title: 'Track',
    artist: 'Artist',
    album: 'Album',
    releaseDate: '2026',
    dateAdded: 'Today',
    plays: '0',
    durationMilliseconds: 120000,
    codec: codec,
    sampleRate: 96000,
    bitsPerSample: 24,
  );
  return PlaybackState(
    status: PlaybackStatus.playing,
    queue: PlaybackQueue(tracks: [track], currentIndex: 0),
    volumeMode: volumeMode,
    volume: volume,
  );
}

OutputDeviceState _output({required bool exclusiveMode}) {
  return OutputDeviceState(
    status: OutputDeviceStatus.ready,
    devices: const [
      AudioOutputDevice(
        id: 'dac',
        name: 'DAC',
        isDefault: true,
        capabilities: AudioOutputCapabilities(supportsExclusiveMode: true),
      ),
    ],
    selectedDeviceId: null,
    exclusiveMode: exclusiveMode,
  );
}
