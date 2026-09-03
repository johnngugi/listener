import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/output_device_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/models/signal_path.dart';
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
          height: compact ? 92 : 108,
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
    final transportWidth = math.min(640.0, math.max(300.0, width - 620));

    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          children: [
            const SizedBox(width: 16),
            const _NowPlayingArtwork(size: 56),
            const SizedBox(width: 14),
            const SizedBox(width: 210, child: NowPlayingText()),
            const Spacer(),
            const SignalPathButton(),
            const SizedBox(width: 12),
            const OutputControl(),
            const SizedBox(width: 8),
            const VolumePopoverButton(),
            const SizedBox(width: 12),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: SizedBox(
              width: transportWidth,
              child: const TransportControls(topPadding: 8),
            ),
          ),
        ),
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
              if (width < 480)
                const Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(child: PlaybackQueueButton()),
                ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (width >= 480) ...[
                        const PlaybackQueueButton(),
                        const SizedBox(width: 2),
                      ],
                      const SignalPathButton(),
                      if (width >= 400) ...[
                        const SizedBox(width: 2),
                        const VolumePopoverButton(),
                      ],
                    ],
                  ),
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

class SignalPathButton extends StatelessWidget {
  const SignalPathButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaybackCubit, PlaybackState>(
      builder: (context, playback) =>
          BlocBuilder<OutputDeviceCubit, OutputDeviceState>(
            builder: (context, output) {
              final signalPath = SignalPath.evaluate(playback, output);
              final color = _signalPathColor(signalPath.quality);
              return Tooltip(
                message: '${signalPath.title}. Open signal path.',
                child: InkWell(
                  key: const Key('signal-path-button'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _showSignalPathDialog(context),
                  child: Semantics(
                    button: true,
                    label: '${signalPath.title}. Open signal path details.',
                    excludeSemantics: true,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        border: Border.all(
                          color: color.withValues(alpha: 0.42),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        _signalPathIcon(signalPath.quality),
                        color: color,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}

class SoftwareVolumeControl extends StatelessWidget {
  const SoftwareVolumeControl({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      PlaybackCubit,
      PlaybackState,
      ({double volume, VolumeMode mode})
    >(
      selector: (state) => (volume: state.volume, mode: state.volumeMode),
      builder: (context, selection) => Row(
        children: [
          IconButton(
            key: const Key('software-volume-mute-button'),
            tooltip: selection.mode == VolumeMode.fixed
                ? 'Fixed output'
                : selection.volume == 0
                ? 'Unmute'
                : 'Mute',
            onPressed: selection.mode == VolumeMode.software
                ? context.read<PlaybackCubit>().toggleMute
                : null,
            icon: Icon(
              selection.mode == VolumeMode.fixed
                  ? Icons.lock_outline_rounded
                  : _volumeIcon(selection.volume),
              color: selection.mode == VolumeMode.fixed
                  ? mutedColor
                  : textColor,
            ),
          ),
          Expanded(
            child: _SoftwareVolumeSlider(
              volume: selection.volume,
              enabled: selection.mode == VolumeMode.software,
            ),
          ),
        ],
      ),
    );
  }
}

class VolumePopoverButton extends StatelessWidget {
  const VolumePopoverButton({super.key});

  @override
  Widget build(BuildContext context) {
    final playbackCubit = context.read<PlaybackCubit>();
    return BlocSelector<
      PlaybackCubit,
      PlaybackState,
      ({double volume, VolumeMode mode})
    >(
      selector: (state) => (volume: state.volume, mode: state.volumeMode),
      builder: (context, selection) {
        final fixed = selection.mode == VolumeMode.fixed;
        return PopupMenuButton<void>(
          key: const Key('software-volume-button'),
          tooltip: fixed
              ? 'Fixed output volume'
              : 'Volume, ${_formatVolumePercent(selection.volume)}',
          color: panelColor,
          elevation: 12,
          constraints: const BoxConstraints(minWidth: 72, maxWidth: 72),
          offset: const Offset(0, -236),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: lineColor),
          ),
          icon: Icon(
            fixed ? Icons.lock_outline_rounded : _volumeIcon(selection.volume),
            color: fixed ? mutedColor : textColor,
            size: 22,
          ),
          itemBuilder: (_) => [
            PopupMenuItem<void>(
              enabled: false,
              height: 220,
              padding: EdgeInsets.zero,
              child: BlocProvider.value(
                value: playbackCubit,
                child: const _VolumePopover(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VolumePopover extends StatelessWidget {
  const _VolumePopover();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      PlaybackCubit,
      PlaybackState,
      ({double volume, VolumeMode mode})
    >(
      selector: (state) => (volume: state.volume, mode: state.volumeMode),
      builder: (context, selection) {
        final enabled = selection.mode == VolumeMode.software;
        return SizedBox(
          key: const Key('software-volume-popover'),
          width: 72,
          height: 220,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text(
                enabled ? _formatVolumePercent(selection.volume) : 'FIXED',
                style: const TextStyle(
                  color: mutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              Expanded(
                child: _VerticalSoftwareVolumeSlider(
                  volume: selection.volume,
                  enabled: enabled,
                ),
              ),
              IconButton(
                key: const Key('software-volume-popover-mute-button'),
                tooltip: enabled
                    ? selection.volume == 0
                          ? 'Unmute'
                          : 'Mute'
                    : 'Fixed output',
                onPressed: enabled
                    ? context.read<PlaybackCubit>().toggleMute
                    : null,
                icon: Icon(
                  enabled
                      ? _volumeIcon(selection.volume)
                      : Icons.lock_outline_rounded,
                  color: enabled ? textColor : mutedColor,
                  size: 21,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }
}

class _VerticalSoftwareVolumeSlider extends StatelessWidget {
  const _VerticalSoftwareVolumeSlider({
    required this.volume,
    required this.enabled,
  });

  final double volume;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final label = _formatVolumePercent(volume);
    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: accentColor,
          inactiveTrackColor: mutedColor.withValues(alpha: 0.25),
          disabledActiveTrackColor: mutedColor.withValues(alpha: 0.35),
          disabledInactiveTrackColor: mutedColor.withValues(alpha: 0.16),
          trackHeight: 3,
          thumbColor: textColor,
          disabledThumbColor: mutedColor,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayColor: accentColor.withValues(alpha: 0.14),
        ),
        child: Slider(
          key: const Key('software-volume-popover-slider'),
          min: 0,
          max: 1,
          divisions: 100,
          value: volume,
          semanticFormatterCallback: (_) => 'Software volume $label',
          onChanged: enabled ? context.read<PlaybackCubit>().setVolume : null,
        ),
      ),
    );
  }
}

class _SoftwareVolumeSlider extends StatelessWidget {
  const _SoftwareVolumeSlider({required this.volume, required this.enabled});

  final double volume;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final label = _formatVolumePercent(volume);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: accentColor,
        inactiveTrackColor: mutedColor.withValues(alpha: 0.25),
        trackHeight: 3,
        thumbColor: textColor,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayColor: accentColor.withValues(alpha: 0.14),
      ),
      child: Slider(
        key: const Key('software-volume-slider'),
        min: 0,
        max: 1,
        divisions: 100,
        value: volume,
        semanticFormatterCallback: (_) => 'Software volume $label',
        onChanged: enabled ? context.read<PlaybackCubit>().setVolume : null,
      ),
    );
  }
}

Future<void> _showSignalPathDialog(BuildContext context) {
  final playbackCubit = context.read<PlaybackCubit>();
  final outputCubit = context.read<OutputDeviceCubit>();
  return showDialog<void>(
    context: context,
    builder: (context) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: playbackCubit),
        BlocProvider.value(value: outputCubit),
      ],
      child: const _SignalPathDialog(),
    ),
  );
}

class _SignalPathDialog extends StatelessWidget {
  const _SignalPathDialog();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaybackCubit, PlaybackState>(
      builder: (context, playback) => BlocBuilder<OutputDeviceCubit, OutputDeviceState>(
        builder: (context, output) {
          final signalPath = SignalPath.evaluate(playback, output);
          final color = _signalPathColor(signalPath.quality);
          final track = playback.queue?.currentTrack;
          final outputName = output.effectiveDevice?.name ?? 'System Output';

          return AlertDialog(
            backgroundColor: panelColor,
            surfaceTintColor: Colors.transparent,
            title: const Text('Signal path'),
            content: SizedBox(
              width: 430,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 620),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        key: const Key('signal-path-status'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _signalPathIcon(signalPath.quality),
                                  color: color,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  signalPath.title,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final reason in signalPath.reasons)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SignalPathRow(
                        label: 'Source',
                        value: track == null
                            ? 'No active track'
                            : _formatTrackAudio(track),
                      ),
                      _SignalPathRow(
                        label: 'Output',
                        value:
                            '$outputName · ${output.exclusiveMode ? 'Exclusive' : 'Shared'}',
                      ),
                      _SignalPathRow(
                        label: 'Volume',
                        value: playback.volumeMode == VolumeMode.fixed
                            ? 'Fixed output · 0 dB'
                            : 'Software · ${_formatVolumePercent(playback.volume)}',
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: lineColor),
                      ),
                      const Text(
                        'VOLUME MODE',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _VolumeModeTile(
                        key: const Key('fixed-volume-mode'),
                        mode: VolumeMode.fixed,
                        selected: playback.volumeMode == VolumeMode.fixed,
                        title: 'Fixed output',
                        subtitle:
                            'Unity gain. Control volume on your DAC or amplifier.',
                      ),
                      _VolumeModeTile(
                        key: const Key('software-volume-mode'),
                        mode: VolumeMode.software,
                        selected: playback.volumeMode == VolumeMode.software,
                        title: 'Software volume',
                        subtitle:
                            'Convenient, but attenuation changes PCM samples.',
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: playback.volumeMode == VolumeMode.software
                            ? const Padding(
                                key: Key('software-volume-controls'),
                                padding: EdgeInsets.only(top: 6),
                                child: SoftwareVolumeControl(),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(color: lineColor),
                      ),
                      SwitchListTile(
                        key: const Key('signal-path-exclusive-toggle'),
                        contentPadding: EdgeInsets.zero,
                        value: output.exclusiveMode,
                        onChanged:
                            output.status == OutputDeviceStatus.switching ||
                                !output.supportsExclusiveMode
                            ? null
                            : context
                                  .read<OutputDeviceCubit>()
                                  .setExclusiveMode,
                        title: const Text('Exclusive output'),
                        subtitle: Text(
                          output.supportsExclusiveMode
                              ? 'Lets Listener match the DAC to the track sample rate.'
                              : 'Not supported by the selected output.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SignalPathRow extends StatelessWidget {
  const _SignalPathRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: mutedColor)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeModeTile extends StatelessWidget {
  const _VolumeModeTile({
    super.key,
    required this.mode,
    required this.selected,
    required this.title,
    required this.subtitle,
  });

  final VolumeMode mode;
  final bool selected;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? accentColor : mutedColor,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: selected
          ? null
          : () => context.read<PlaybackCubit>().setVolumeMode(mode),
    );
  }
}

Color _signalPathColor(SignalPathQuality quality) {
  return switch (quality) {
    SignalPathQuality.inactive => mutedColor,
    SignalPathQuality.bitPerfect => const Color(0xFF59D69B),
    SignalPathQuality.processed => const Color(0xFFFFB45C),
  };
}

IconData _signalPathIcon(SignalPathQuality quality) {
  return switch (quality) {
    SignalPathQuality.inactive => Icons.route_outlined,
    SignalPathQuality.bitPerfect => Icons.verified_rounded,
    SignalPathQuality.processed => Icons.tune_rounded,
  };
}

IconData _volumeIcon(double volume) {
  if (volume == 0) return Icons.volume_off_rounded;
  if (volume < 0.5) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

String _formatVolumePercent(double volume) => '${(volume * 100).round()}%';

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
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            selection.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: mutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
          if (selection.format.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              selection.format,
              key: const Key('now-playing-format'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accentColor.withValues(alpha: 0.82),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TransportControls extends StatelessWidget {
  const TransportControls({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('transport-controls'),
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            key: const Key('transport-button-row'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                key: const Key('transport-button-cluster'),
                width: 264,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    const _PlayPauseButton(iconSize: 29),
                    IconButton(
                      tooltip: 'Next track',
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: textColor,
                        size: 25,
                      ),
                      onPressed: () => context.read<PlaybackCubit>().next(),
                    ),
                    const PlaybackQueueButton(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const PlaybackTimeline(),
        ],
      ),
    );
  }
}

class PlaybackQueueButton extends StatelessWidget {
  const PlaybackQueueButton({super.key});

  @override
  Widget build(BuildContext context) {
    final itemCount = context.select(
      (PlaybackCubit cubit) => cubit.state.queue?.tracks.length ?? 0,
    );
    return IconButton(
      key: const Key('playback-queue-button'),
      tooltip: itemCount == 0
          ? 'Playback queue'
          : 'Playback queue ($itemCount)',
      onPressed: () => _showPlaybackQueue(context),
      icon: const Icon(Icons.queue_music_rounded, color: mutedColor, size: 22),
    );
  }
}

Future<void> _showPlaybackQueue(BuildContext context) {
  final playbackCubit = context.read<PlaybackCubit>();
  return showDialog<void>(
    context: context,
    builder: (context) => BlocProvider.value(
      value: playbackCubit,
      child: const _PlaybackQueueDialog(),
    ),
  );
}

class _PlaybackQueueDialog extends StatelessWidget {
  const _PlaybackQueueDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: BlocBuilder<PlaybackCubit, PlaybackState>(
          builder: (context, state) {
            final queue = state.queue;
            final tracks = queue?.tracks ?? const <Track>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Playback queue',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (tracks.isNotEmpty)
                        Text(
                          '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                          style: const TextStyle(color: mutedColor),
                        ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: lineColor),
                if (queue == null || tracks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 54, horizontal: 28),
                    child: Column(
                      children: [
                        Icon(
                          Icons.queue_music_rounded,
                          color: mutedColor,
                          size: 36,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Your queue is empty',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Play a track from the library to start a queue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: mutedColor),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tracks.length,
                      onReorderItem: context.read<PlaybackCubit>().reorderQueue,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final isCurrent = index == queue.currentIndex;
                        return _PlaybackQueueRow(
                          key: ValueKey(track.id),
                          track: track,
                          index: index,
                          isCurrent: isCurrent,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlaybackQueueRow extends StatelessWidget {
  const _PlaybackQueueRow({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
  });

  final Track track;
  final int index;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlaybackCubit>();
    return Material(
      color: isCurrent
          ? accentColor.withValues(alpha: 0.08)
          : Colors.transparent,
      child: ListTile(
        key: Key('playback-queue-item-${track.id}'),
        contentPadding: const EdgeInsets.only(left: 18, right: 8),
        onTap: isCurrent
            ? null
            : () async {
                Navigator.of(context).pop();
                await cubit.playQueueItem(index);
              },
        leading: SizedBox(
          width: 28,
          child: Center(
            child: isCurrent
                ? const Icon(
                    Icons.graphic_eq_rounded,
                    color: accentColor,
                    size: 21,
                  )
                : Text(
                    '${index + 1}',
                    style: const TextStyle(color: mutedColor),
                  ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent ? accentColor : textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          isCurrent
              ? 'Now playing · ${track.artist}'
              : '${track.artist} · ${track.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: mutedColor),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('remove-queue-item-${track.id}'),
              tooltip: isCurrent ? 'Current track' : 'Remove from queue',
              onPressed: isCurrent ? null : () => cubit.removeQueueItem(index),
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle_rounded, color: mutedColor),
              ),
            ),
          ],
        ),
      ),
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
          return const SizedBox(width: double.infinity, height: 34);
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
typedef _NowPlayingTextSelection = ({
  String title,
  String artist,
  String format,
});
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
  if (!_showsTrack(state)) return (title: '', artist: '', format: '');
  final track = state.queue?.currentTrack;
  return (
    title: track?.title ?? '',
    artist: track?.artist ?? '',
    format: track == null ? '' : _formatTrackAudio(track),
  );
}

String _formatTrackAudio(Track track) {
  final parts = <String>[
    if (track.codec.trim().isNotEmpty) track.codec.trim().toUpperCase(),
    if (track.bitsPerSample > 0) '${track.bitsPerSample}-bit',
    if (track.sampleRate > 0) _formatSampleRate(track.sampleRate),
  ];
  return parts.join(' · ');
}

String _formatSampleRate(int sampleRate) {
  if (sampleRate < 1000) return '$sampleRate Hz';

  final kilohertz = sampleRate / 1000;
  return kilohertz == kilohertz.roundToDouble()
      ? '${kilohertz.toInt()} kHz'
      : '${kilohertz.toStringAsFixed(1)} kHz';
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
              ? '$selectedName. Choose audio output.'
              : isSwitching
              ? 'Switching audio output'
              : 'Wait for playback to start',
          child: Semantics(
            button: true,
            label: 'Audio output: $selectedName',
            child: InkWell(
              key: const Key('output-device-picker-button'),
              borderRadius: BorderRadius.circular(10),
              onTap: canChangeOutput ? () => _showOutputPicker(context) : null,
              child: SizedBox(
                width: 112,
                height: 68,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (outputState.status == OutputDeviceStatus.loading ||
                        outputState.status == OutputDeviceStatus.switching)
                      const SizedBox.square(
                        key: Key('output-device-progress'),
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    else
                      Icon(
                        key: const Key('output-device-icon'),
                        outputState.selectedDeviceId == null
                            ? Icons.speaker_outlined
                            : Icons.speaker_group_outlined,
                        color: canChangeOutput ? mutedColor : lineColor,
                        size: 23,
                      ),
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        key: const Key('output-device-label'),
                        selectedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: canChangeOutput ? mutedColor : lineColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
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
