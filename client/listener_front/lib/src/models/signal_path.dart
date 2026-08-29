import 'package:equatable/equatable.dart';
import 'package:listener_front/src/models/output_device_state.dart';
import 'package:listener_front/src/models/playback_state.dart';

enum SignalPathQuality { inactive, bitPerfect, processed }

final class SignalPath extends Equatable {
  const SignalPath({
    required this.quality,
    required this.title,
    required this.reasons,
  });

  factory SignalPath.evaluate(
    PlaybackState playback,
    OutputDeviceState output,
  ) {
    final track = playback.queue?.currentTrack;
    final active =
        track != null &&
        (playback.status == PlaybackStatus.playing ||
            playback.status == PlaybackStatus.paused ||
            playback.status == PlaybackStatus.cued);
    if (!active) {
      return const SignalPath(
        quality: SignalPathQuality.inactive,
        title: 'Signal path',
        reasons: ['Start playback to inspect the active signal path.'],
      );
    }

    final reasons = <String>[];
    if (!_losslessCodecs.contains(track.codec.trim().toLowerCase())) {
      reasons.add('The source codec is lossy.');
    }
    if (!output.exclusiveMode) {
      reasons.add('Shared output allows macOS to mix or resample audio.');
    }
    if (playback.volumeMode == VolumeMode.software && playback.volume < 1) {
      reasons.add('Software volume is changing the PCM samples.');
    }

    if (reasons.isEmpty) {
      return const SignalPath(
        quality: SignalPathQuality.bitPerfect,
        title: 'Bit-perfect',
        reasons: [
          'The lossless source is sent at unity gain and the DAC follows its sample rate.',
        ],
      );
    }
    return SignalPath(
      quality: SignalPathQuality.processed,
      title: 'Not bit-perfect',
      reasons: List.unmodifiable(reasons),
    );
  }

  final SignalPathQuality quality;
  final String title;
  final List<String> reasons;

  @override
  List<Object?> get props => [quality, title, reasons];
}

const _losslessCodecs = {
  'flac',
  'alac',
  'wav',
  'wave',
  'aif',
  'aiff',
  'ape',
  'wavpack',
};
