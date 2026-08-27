import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';
import 'package:listener_front/src/widgets/artwork_image.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        return Container(
          height: compact ? 104 : 108,
          decoration: const BoxDecoration(
            color: panelColor,
            border: Border(top: BorderSide(color: lineColor)),
          ),
          child: compact
              ? _CompactNowPlayingBar(width: constraints.maxWidth)
              : _WideNowPlayingBar(width: constraints.maxWidth),
        );
      },
    );
  }
}

class _WideNowPlayingBar extends StatelessWidget {
  const _WideNowPlayingBar({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final showOutput = width >= 1180;

    return Row(
      children: [
        const SizedBox(width: 20),
        const _NowPlayingArtwork(size: 68),
        const SizedBox(width: 16),
        SizedBox(width: showOutput ? 250 : 210, child: const NowPlayingText()),
        const SizedBox(width: 18),
        const Expanded(child: TransportControls()),
        if (showOutput) ...[const SizedBox(width: 18), const OutputControl()],
        const SizedBox(width: 20),
      ],
    );
  }
}

class _CompactNowPlayingBar extends StatelessWidget {
  const _CompactNowPlayingBar({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final showArtwork = width >= 700;
    final showTrack = width >= 480;
    final trackWidth = (width / 2 - 96).clamp(0.0, 270.0);

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (showTrack)
                Positioned(
                  left: 12,
                  top: 6,
                  bottom: 2,
                  width: trackWidth,
                  child: Row(
                    children: [
                      if (showArtwork) ...[
                        const _NowPlayingArtwork(size: 48),
                        const SizedBox(width: 12),
                      ],
                      const Expanded(child: NowPlayingText()),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous track',
                      icon: const Icon(
                        Icons.skip_previous,
                        color: textColor,
                        size: 25,
                      ),
                      onPressed: () => context.read<PlaybackCubit>().previous(),
                    ),
                    const _PlayPauseButton(iconSize: 27, compact: true),
                    IconButton(
                      tooltip: 'Next track',
                      icon: const Icon(
                        Icons.skip_next,
                        color: textColor,
                        size: 25,
                      ),
                      onPressed: () => context.read<PlaybackCubit>().next(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: PlaybackTimeline(),
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PlaybackCubit, PlaybackState, _ArtworkSelection>(
      selector: _selectArtwork,
      builder: (context, artwork) {
        if (artwork.visible) {
          return ArtworkImage(artworkId: artwork.artworkId, size: size);
        }
        return SizedBox.square(dimension: size);
      },
    );
  }
}

class NowPlayingText extends StatelessWidget {
  const NowPlayingText({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PlaybackCubit, PlaybackState, _NowPlayingTextSelection>(
      selector: _selectNowPlayingText,
      builder: (context, selection) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selection.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            selection.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: mutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class TransportControls extends StatelessWidget {
  const TransportControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous track',
              icon: const Icon(
                Icons.skip_previous_rounded,
                color: textColor,
                size: 25,
              ),
              onPressed: () => context.read<PlaybackCubit>().previous(),
            ),
            const SizedBox(width: 14),
            const _PlayPauseButton(iconSize: 29),
            const SizedBox(width: 14),
            IconButton(
              tooltip: 'Next track',
              icon: const Icon(
                Icons.skip_next_rounded,
                color: textColor,
                size: 25,
              ),
              onPressed: () => context.read<PlaybackCubit>().next(),
            ),
            const SizedBox(width: 18),
            const Tooltip(
              message: 'Playback queue',
              child: Icon(
                Icons.queue_music_rounded,
                color: mutedColor,
                size: 22,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const PlaybackTimeline(),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.iconSize, this.compact = false});

  final double iconSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocListener<PlaybackCubit, PlaybackState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
      },
      child: BlocSelector<PlaybackCubit, PlaybackState, PlaybackStatus>(
        selector: (state) => state.status,
        builder: (context, status) {
          final isStarting = status == PlaybackStatus.starting;
          final isPlaying = status == PlaybackStatus.playing;
          final isPaused = status == PlaybackStatus.paused;

          VoidCallback? onPressed;
          Widget icon;

          if (isStarting) {
            onPressed = null;
            icon = const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          } else if (isPlaying) {
            onPressed = context.read<PlaybackCubit>().pause;
            icon = Icon(Icons.pause, color: textColor, size: iconSize);
          } else if (isPaused) {
            onPressed = context.read<PlaybackCubit>().resume;
            icon = Icon(Icons.play_arrow, color: textColor, size: iconSize);
          } else {
            onPressed = context.read<PlaybackCubit>().play;
            icon = Icon(Icons.play_arrow, color: textColor, size: iconSize);
          }

          return Tooltip(
            message: isPlaying ? 'Pause' : 'Play',
            child: Container(
              width: compact ? 42 : 46,
              height: compact ? 42 : 46,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.24),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: onPressed,
                icon: icon,
              ),
            ),
          );
        },
      ),
    );
  }
}

class PlaybackElapsedTime extends StatelessWidget {
  const PlaybackElapsedTime({super.key, required this.elapsedSeconds});

  final int elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    return Text(_formatSeconds(elapsedSeconds), style: _playbackTimeStyle);
  }
}

class PlaybackDuration extends StatelessWidget {
  const PlaybackDuration({super.key, required this.durationSeconds});

  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    return Text(_formatSeconds(durationSeconds), style: _playbackTimeStyle);
  }
}

class PlaybackTimeline extends StatefulWidget {
  const PlaybackTimeline({super.key});

  @override
  State<PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<PlaybackTimeline> {
  double? _progressValue;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      PlaybackCubit,
      PlaybackState,
      _PlaybackProgressSelection
    >(
      selector: _selectPlaybackProgress,
      builder: (context, progress) {
        if (!progress.visible) {
          return const SizedBox(height: 34);
        }
        final displayedMilliseconds =
            (_progressValue ?? progress.positionMilliseconds).clamp(
              0.0,
              progress.maxMilliseconds,
            );

        final progressBar = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accentColor,
            inactiveTrackColor: mutedColor.withValues(alpha: 0.25),
            trackHeight: 3,
            thumbColor: textColor,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayColor: accentColor.withValues(alpha: 0.14),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            min: 0,
            max: progress.maxMilliseconds,
            value: displayedMilliseconds,
            onChangeStart: (double milliseconds) {
              setState(() {
                _progressValue = milliseconds;
              });
            },
            onChanged: (double milliseconds) {
              setState(() {
                _progressValue = milliseconds;
              });
            },
            onChangeEnd: (double milliseconds) {
              context.read<PlaybackCubit>().seekTo(milliseconds);
              setState(() {
                _progressValue = null;
              });
            },
          ),
        );

        return Row(
          children: [
            PlaybackElapsedTime(
              elapsedSeconds: displayedMilliseconds.toInt() ~/ 1000,
            ),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 34, child: progressBar)),
            const SizedBox(width: 8),
            PlaybackDuration(
              durationSeconds: progress.maxMilliseconds.toInt() ~/ 1000,
            ),
          ],
        );
      },
    );
  }
}

const _playbackTimeStyle = TextStyle(
  color: mutedColor,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

typedef _ArtworkSelection = ({bool visible, int? artworkId});
typedef _NowPlayingTextSelection = ({String title, String artist});
typedef _PlaybackProgressSelection = ({
  bool visible,
  double positionMilliseconds,
  double maxMilliseconds,
});

bool _showsTrack(PlaybackState state) =>
    state.status == PlaybackStatus.playing ||
    state.status == PlaybackStatus.paused;

_ArtworkSelection _selectArtwork(PlaybackState state) => (
  visible: _showsTrack(state),
  artworkId: state.queue?.currentTrack.artworkId,
);

_NowPlayingTextSelection _selectNowPlayingText(PlaybackState state) {
  if (!_showsTrack(state)) return (title: '', artist: '');
  final track = state.queue?.currentTrack;
  return (title: track?.title ?? '', artist: track?.artist ?? '');
}

_PlaybackProgressSelection _selectPlaybackProgress(PlaybackState state) {
  final track = state.queue?.currentTrack;
  final visible = track != null && _showsTrack(state);
  if (!visible) {
    return (visible: false, positionMilliseconds: 0, maxMilliseconds: 1);
  }

  final maxMilliseconds = track.durationMilliseconds > 0
      ? track.durationMilliseconds.toDouble()
      : 1.0;
  final positionMilliseconds = _positionMilliseconds(
    state,
  ).toDouble().clamp(0.0, maxMilliseconds);

  return (
    visible: true,
    positionMilliseconds: positionMilliseconds,
    maxMilliseconds: maxMilliseconds,
  );
}

int _positionMilliseconds(PlaybackState state) {
  final track = state.queue?.currentTrack;
  if (track == null || track.sampleRate <= 0) return 0;
  return state.currentFrame * 1000 ~/ track.sampleRate;
}

String _formatSeconds(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height / 2;
    final paint = Paint()
      ..color = mutedColor.withValues(alpha: .28)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 190; i++) {
      final x = i * size.width / 190;
      final envelope =
          math.sin(i * .1).abs() * .55 + math.sin(i * .031).abs() * .45;
      final h = size.height * (.1 + envelope * .36);
      canvas.drawLine(
        Offset(x, baseline - h / 2),
        Offset(x, baseline + h / 2),
        paint,
      );
    }

    final playedPaint = Paint()
      ..color = accentColor.withValues(alpha: .72)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 12; i++) {
      final x = i * size.width / 190;
      final h = size.height * (.14 + math.sin(i * .7).abs() * .38);
      canvas.drawLine(
        Offset(x, baseline - h / 2),
        Offset(x, baseline + h / 2),
        playedPaint,
      );
    }

    canvas.drawLine(
      Offset(size.width * .028, 0),
      Offset(size.width * .028, size.height),
      Paint()
        ..color = const Color(0xFFFF2C75)
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OutputControl extends StatelessWidget {
  const OutputControl({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.55),
        border: Border.all(color: lineColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.speaker_outlined, color: mutedColor, size: 24),
          const SizedBox(width: 9),
          const Text(
            'System Output',
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 24, color: lineColor),
          const SizedBox(width: 12),
          const Tooltip(
            message: 'Volume 100%',
            child: Row(
              children: [
                Icon(Icons.volume_up_outlined, color: textColor, size: 24),
                SizedBox(width: 5),
                Text(
                  '100',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
