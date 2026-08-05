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
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        color: panelColor,
        border: Border(top: BorderSide(color: lineColor)),
      ),
      child: Row(
        children: [
          SizedBox(width: 20),
          BlocSelector<PlaybackCubit, PlaybackState, _ArtworkSelection>(
            selector: _selectArtwork,
            builder: (context, artwork) {
              if (artwork.visible) {
                return ArtworkImage(artworkId: artwork.artworkId, size: 78);
              } else {
                return const SizedBox(width: 78, height: 78);
              }
            },
          ),
          SizedBox(width: 18),
          SizedBox(width: 270, child: NowPlayingText()),
          Spacer(),
          TransportControls(),
          Spacer(),
          OutputControl(),
          SizedBox(width: 32),
        ],
      ),
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            selection.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textColor,
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
    return SizedBox(
      width: 820,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.fiber_manual_record,
                color: Color(0xFF656568),
                size: 14,
              ),
              SizedBox(width: 62),
              IconButton(
                icon: Icon(Icons.skip_previous, color: textColor, size: 28),
                onPressed: () => context.read<PlaybackCubit>().previous(),
              ),
              SizedBox(width: 34),
              BlocListener<PlaybackCubit, PlaybackState>(
                listenWhen: (previous, current) =>
                    previous.errorMessage != current.errorMessage &&
                    current.errorMessage != null,
                listener: (context, state) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
                },
                child:
                    BlocSelector<PlaybackCubit, PlaybackState, PlaybackStatus>(
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
                          icon = const Icon(
                            Icons.pause,
                            color: textColor,
                            size: 40,
                          );
                        } else if (isPaused) {
                          onPressed = context.read<PlaybackCubit>().resume;
                          icon = const Icon(
                            Icons.play_arrow,
                            color: textColor,
                            size: 40,
                          );
                        } else {
                          onPressed = context.read<PlaybackCubit>().play;
                          icon = const Icon(
                            Icons.play_arrow,
                            color: textColor,
                            size: 40,
                          );
                        }

                        return IconButton(onPressed: onPressed, icon: icon);
                      },
                    ),
              ),
              SizedBox(width: 34),
              IconButton(
                icon: const Icon(Icons.skip_next, color: textColor, size: 28),
                onPressed: () => context.read<PlaybackCubit>().next(),
              ),
              SizedBox(width: 52),
              Icon(Icons.queue_music, color: textColor, size: 24),
            ],
          ),
          const SizedBox(height: 18),
          const PlaybackTimeline(),
        ],
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

        final progressBar = Slider(
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
        );

        return Row(
          children: [
            PlaybackElapsedTime(
              elapsedSeconds: displayedMilliseconds.toInt() ~/ 1000,
            ),
            const SizedBox(width: 16),
            Expanded(child: SizedBox(height: 34, child: progressBar)),
            const SizedBox(width: 16),
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
  color: textColor,
  fontSize: 13,
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
    return SizedBox(
      width: 210,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.speaker, color: textColor, size: 38),
              SizedBox(height: 8),
              Text(
                'System Output',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 36),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.volume_up_outlined, color: textColor, size: 38),
              SizedBox(height: 9),
              Text(
                '100',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
