import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;
import 'package:listener_front/src/models/playback_queue.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/services/playback_engine.dart';
import 'package:listener_front/src/utils/result.dart';

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

  bool _isSwitchingTrack = false;

  Future<void> play({Track? selectedTrack, List<Track>? queueTracks}) async {
    if (_isSwitchingTrack) return;

    PlaybackQueue? queue = state.queue;
    if (selectedTrack != null) {
      if (selectedTrack.id == state.queue?.currentTrack.id &&
          (state.status == PlaybackStatus.starting ||
              state.status == PlaybackStatus.playing)) {
        return;
      }

      final tracks = List<Track>.unmodifiable(queueTracks ?? [selectedTrack]);

      final selectedIndex = tracks.indexWhere(
        (track) => track.id == selectedTrack.id,
      );

      if (selectedIndex == -1) {
        emit(
          PlaybackState(
            queue: state.queue,
            status: PlaybackStatus.error,
            errorMessage: 'Select a track to play',
          ),
        );
        return;
      }

      queue = PlaybackQueue(tracks: tracks, currentIndex: selectedIndex);
    }

    final track = queue?.currentTrack;
    if (track == null) {
      emit(
        const PlaybackState(
          queue: null,
          status: PlaybackStatus.error,
          errorMessage: 'Select a track to play',
        ),
      );
      return;
    }

    String? playbackId;
    _isSwitchingTrack = true;
    try {
      if (_playbackId != null) {
        await stop();
      }

      emit(PlaybackState(queue: queue, status: PlaybackStatus.starting));

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
      emit(PlaybackState(queue: queue, status: PlaybackStatus.playing));
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
          queue: state.queue,
          status: PlaybackStatus.error,
          errorMessage: error.toString(),
        ),
      );
    } finally {
      _isSwitchingTrack = false;
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
      emit(PlaybackState(queue: state.queue, status: PlaybackStatus.stopped));
    } catch (error) {
      emit(
        PlaybackState(
          queue: state.queue,
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
      emit(PlaybackState(queue: state.queue, status: PlaybackStatus.paused));
    } catch (error) {
      emit(
        PlaybackState(
          queue: state.queue,
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

      emit(PlaybackState(queue: state.queue, status: PlaybackStatus.playing));
    } catch (error) {
      emit(
        PlaybackState(
          queue: state.queue,
          status: PlaybackStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> previous() async {
    final queue = state.queue;
    if (queue == null || queue.tracks.isEmpty) return;

    switch (queue.previousTrack) {
      case Ok<Track>(:final value):
        await play(selectedTrack: value, queueTracks: queue.tracks);
      case Error<Track>():
        return;
    }
  }

  Future<void> next() async {
    final queue = state.queue;
    if (queue == null || queue.tracks.isEmpty) return;

    switch (queue.nextTrack) {
      case Ok<Track>(:final value):
        await play(selectedTrack: value, queueTracks: queue.tracks);
      case Error<Track>():
        return;
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
    switch (event) {
      case PlaybackEngineEvent.ended:
        unawaited(_handlePlaybackEnded());
      case PlaybackEngineEvent.failed:
        unawaited(_handlePlaybackFailure());
    }
  }

  Future<void> _handlePlaybackFailure() async {
    final playbackId = _playbackId;
    if (playbackId == null || isClosed) return;
    _playbackId = null;

    final status = _engine.stop();
    emit(
      PlaybackState(
        queue: state.queue,
        status: PlaybackStatus.error,
        errorMessage: 'Audio receiver failed: ${status.name}',
      ),
    );

    try {
      await _control.stop(
        control.StopRequest(playbackId: playbackId),
        options: CallOptions(timeout: _controlCallTimeout),
      );
    } catch (_) {
      // The local receiver has already stopped; remote cleanup is best-effort.
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
          queue: null,
          status: PlaybackStatus.error,
          errorMessage: 'Engine cleanup failed: ${status.name}',
        ),
      );
      return;
    }

    emit(PlaybackState(queue: state.queue, status: PlaybackStatus.stopped));

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
