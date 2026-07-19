import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/services/playback_engine.dart';

const _controlCallTimeout = Duration(seconds: 5);

class PlaybackCubit extends Cubit<PlaybackState> {
  PlaybackCubit._(this._engine, this._control)
    : super(PlaybackState.initial()) {
    _engineEvents = _engine.events.listen(_onEngineEvent);
  }

  factory PlaybackCubit.connect(
    ListenerEngine engine,
    control.ListenerControlClient controlClient,
  ) {
    return PlaybackCubit._(engine, controlClient);
  }

  final ListenerEngine _engine;
  final control.ListenerControlClient _control;
  late final StreamSubscription<PlaybackEngineEvent> _engineEvents;

  String? _playbackId;

  Future<void> play([Track? selectedTrack]) async {
    if (state.status == PlaybackStatus.starting ||
        state.status == PlaybackStatus.playing) {
      return;
    }

    final track = selectedTrack ?? state.track;
    if (track == null) {
      emit(
        const PlaybackState(
          track: null,
          status: PlaybackStatus.error,
          errorMessage: 'Select a track to play',
        ),
      );
      return;
    }

    emit(PlaybackState(track: track, status: PlaybackStatus.starting));

    String? playbackId;
    try {
      final response = await _control.start(
        control.StartRequest(trackId: track.id),
        options: CallOptions(timeout: _controlCallTimeout),
      );
      playbackId = response.playbackId;

      final status = _engine.startStream(playbackId: playbackId);
      if (status != ListenerStatus.ok) {
        throw StateError('Engine start failed: ${status.name}');
      }

      _playbackId = playbackId;
      emit(PlaybackState(track: track, status: PlaybackStatus.playing));
    } catch (error) {
      if (playbackId != null && playbackId.isNotEmpty) {
        try {
          await _control.stop(
            control.StopRequest(playbackId: playbackId),
            options: CallOptions(timeout: _controlCallTimeout),
          );
        } catch (_) {
          // Preserve the original playback failure.
        }
      }

      emit(
        PlaybackState(
          track: state.track,
          status: PlaybackStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> stop() async {
    final playbackId = _playbackId;
    if (playbackId == null) return;
    _playbackId = null;

    try {
      final status = _engine.stop();
      if (status != ListenerStatus.ok) {
        throw StateError('Engine stop failed: ${status.name}');
      }

      await _control.stop(
        control.StopRequest(playbackId: playbackId),
        options: CallOptions(timeout: _controlCallTimeout),
      );
      emit(PlaybackState(track: state.track, status: PlaybackStatus.stopped));
    } catch (error) {
      emit(
        PlaybackState(
          track: state.track,
          status: PlaybackStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> pause() async {
    final playbackId = _playbackId;
    if (playbackId == null || state.status != PlaybackStatus.playing) return;

    try {
      final status = _engine.pause();
      if (status != ListenerStatus.ok) {
        throw StateError('Engine pause failed: ${status.name}');
      }

      await _control.pause(
        control.PauseRequest(playbackId: playbackId),
        options: CallOptions(timeout: _controlCallTimeout),
      );
      emit(PlaybackState(track: state.track, status: PlaybackStatus.paused));
    } catch (error) {
      emit(
        PlaybackState(
          track: state.track,
          status: PlaybackStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> resume() async {
    final playbackId = _playbackId;
    if (playbackId == null || state.status != PlaybackStatus.paused) return;

    try {
      await _control.resume(
        control.ResumeRequest(playbackId: playbackId),
        options: CallOptions(timeout: _controlCallTimeout),
      );

      final status = _engine.resume();
      if (status != ListenerStatus.ok) {
        throw StateError('Engine resume failed: ${status.name}');
      }

      emit(PlaybackState(track: state.track, status: PlaybackStatus.playing));
    } catch (error) {
      emit(
        PlaybackState(
          track: state.track,
          status: PlaybackStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _engineEvents.cancel();
    if (_playbackId != null) {
      _engine.stop();
    }
    _engine.close();
    return super.close();
  }

  void _onEngineEvent(PlaybackEngineEvent event) {
    if (event == PlaybackEngineEvent.ended) {
      unawaited(_handlePlaybackEnded());
    }
  }

  Future<void> _handlePlaybackEnded() async {
    final playbackId = _playbackId;
    if (playbackId == null || isClosed) return;
    _playbackId = null;

    final status = _engine.stop();
    if (status != ListenerStatus.ok) {
      emit(
        PlaybackState(
          track: state.track,
          status: PlaybackStatus.error,
          errorMessage: 'Engine cleanup failed: ${status.name}',
        ),
      );
      return;
    }

    emit(PlaybackState(track: state.track, status: PlaybackStatus.stopped));

    try {
      await _control.stop(
        control.StopRequest(playbackId: playbackId),
        options: CallOptions(timeout: _controlCallTimeout),
      );
    } catch (_) {
      // Playback has already ended locally; server cleanup is best-effort.
    }
  }
}
