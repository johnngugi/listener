import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/output_device_state.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/view_models/output_device_cubit.dart';
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
    state.status == PlaybackStatus.paused ||
    state.status == PlaybackStatus.cued;

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
    return BlocConsumer<OutputDeviceCubit, OutputDeviceState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
      },
      builder: (context, outputState) {
        final playbackStatus = context.select(
          (PlaybackCubit cubit) => cubit.state.status,
        );
        final isSwitching = outputState.status == OutputDeviceStatus.switching;
        final canChangeOutput =
            playbackStatus != PlaybackStatus.starting && !isSwitching;
        final selectedName =
            outputState.selectedDevice?.name ?? 'System Output';

        return Tooltip(
          message: canChangeOutput
              ? 'Choose audio output'
              : isSwitching
              ? 'Switching audio output'
              : 'Wait for playback to start',
          child: InkWell(
            key: const Key('output-device-picker-button'),
            borderRadius: BorderRadius.circular(12),
            onTap: canChangeOutput ? () => _showOutputPicker(context) : null,
            child: Container(
              constraints: const BoxConstraints(minWidth: 238),
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: backgroundColor.withValues(alpha: 0.55),
                border: Border.all(color: lineColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    outputState.selectedDeviceId == null
                        ? Icons.speaker_outlined
                        : Icons.speaker_group_outlined,
                    color: canChangeOutput ? mutedColor : lineColor,
                    size: 24,
                  ),
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 126),
                    child: Text(
                      selectedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: canChangeOutput ? textColor : mutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (outputState.status == OutputDeviceStatus.loading ||
                      outputState.status == OutputDeviceStatus.switching)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: mutedColor,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOutputPicker(BuildContext context) {
    final playbackStatus = context.read<PlaybackCubit>().state.status;
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<OutputDeviceCubit>(),
        child: _OutputDeviceDialog(
          willCuePlayback:
              playbackStatus == PlaybackStatus.playing ||
              playbackStatus == PlaybackStatus.paused,
        ),
      ),
    );
  }
}

class _OutputDeviceDialog extends StatelessWidget {
  const _OutputDeviceDialog({required this.willCuePlayback});

  final bool willCuePlayback;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutputDeviceCubit, OutputDeviceState>(
      builder: (context, state) {
        return AlertDialog(
          backgroundColor: panelColor,
          surfaceTintColor: Colors.transparent,
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audio output',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      willCuePlayback
                          ? 'Playback will pause at its current position.'
                          : 'Choose where Listener plays music.',
                      style: const TextStyle(
                        color: mutedColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh audio outputs',
                onPressed: state.status == OutputDeviceStatus.switching
                    ? null
                    : context.read<OutputDeviceCubit>().refresh,
                icon: const Icon(Icons.refresh_rounded, color: mutedColor),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _OutputDeviceTile(
                    key: const Key('output-device-option-system'),
                    title: 'System Output',
                    subtitle: 'Follow the macOS default output',
                    icon: Icons.computer_rounded,
                    selected: state.selectedDeviceId == null,
                    onTap: state.status == OutputDeviceStatus.switching
                        ? null
                        : () => _select(context, null),
                  ),
                  if (state.devices.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 12, 14, 7),
                      child: Text(
                        'AVAILABLE OUTPUTS',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  for (final device in state.devices)
                    _OutputDeviceTile(
                      key: Key('output-device-option-${device.id}'),
                      title: device.name,
                      subtitle: device.isDefault
                          ? 'Current macOS default'
                          : 'Available audio output',
                      icon: Icons.speaker_group_outlined,
                      selected: state.selectedDeviceId == device.id,
                      onTap: state.status == OutputDeviceStatus.switching
                          ? null
                          : () => _select(context, device.id),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(color: lineColor, height: 24),
                  ),
                  SwitchListTile(
                    key: const Key('exclusive-mode-toggle'),
                    value: state.exclusiveMode,
                    onChanged:
                        state.status == OutputDeviceStatus.switching ||
                            !state.supportsExclusiveMode
                        ? null
                        : (enabled) => context
                              .read<OutputDeviceCubit>()
                              .setExclusiveMode(enabled),
                    activeTrackColor: accentColor.withValues(alpha: 0.5),
                    activeThumbColor: accentColor,
                    title: const Text(
                      'Exclusive mode',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      state.supportsExclusiveMode
                          ? 'Prevent other apps from using this output while '
                                'Listener is playing.'
                          : 'Not supported by the selected output.',
                      style: const TextStyle(color: mutedColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _select(BuildContext context, String? deviceId) async {
    if (await context.read<OutputDeviceCubit>().selectDevice(deviceId) &&
        context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _OutputDeviceTile extends StatelessWidget {
  const _OutputDeviceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: ListTile(
        selected: selected,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selectedTileColor: accentColor.withValues(alpha: 0.13),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.18)
                : backgroundColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 21,
            color: selected ? accentColor : mutedColor,
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? textColor : mutedColor,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: mutedColor, fontSize: 12),
        ),
        trailing: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: selected ? accentColor : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? accentColor : lineColor),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: textColor, size: 15)
              : null,
        ),
      ),
    );
  }
}
