import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;
import 'package:listener_front/src/models/playback_queue.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/services/playback_control.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/utils/result.dart';

class PlaybackCubit extends Cubit<PlaybackState> {
  PlaybackCubit._(this._engine, this._control)
    : super(PlaybackState.initial()) {
    _engineEvents = _engine.events.listen(_onEngineEvent);
  }

  factory PlaybackCubit.connect(
    PlaybackEngine engine,
    control.ListenerControlClient controlClient,
  ) {
    return PlaybackCubit._(engine, GrpcPlaybackControl(controlClient));
  }

  factory PlaybackCubit.withDependencies(
    PlaybackEngine engine,
    PlaybackControl controlClient,
  ) {
    return PlaybackCubit._(engine, controlClient);
  }

  final PlaybackEngine _engine;
  final PlaybackControl _control;
  late final StreamSubscription<PlaybackEngineEvent> _engineEvents;

  Timer? _playbackFrameTimer;

  String? _playbackId;

  bool _isSwitchingTrack = false;

  bool _isSeeking = false;

  int _cuedStartFrame = 0;

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

    final requestedStartFrame = selectedTrack == null ? _cuedStartFrame : 0;
    String? playbackId;
    _isSwitchingTrack = true;
    try {
      if (_playbackId != null) {
        await stop();
      }

      emit(
        PlaybackState(
          queue: queue,
          status: PlaybackStatus.starting,
          currentFrame: requestedStartFrame,
        ),
      );

      final response = await _control.start(
        control.StartRequest(
          trackId: track.id,
          startFrame: Int64(requestedStartFrame),
        ),
      );
      playbackId = response.playbackId;

      final status = _engine.startStream(
        playbackId: playbackId,
        requestedStartFrame: requestedStartFrame,
      );
      if (status != ListenerStatus.ok) {
        throw StateError('Engine start failed: ${status.name}');
      }

      _playbackId = playbackId;
      _cuedStartFrame = 0;
      emit(
        PlaybackState(
          queue: queue,
          status: PlaybackStatus.playing,
          currentFrame: requestedStartFrame,
        ),
      );
      _startPositionPolling();
    } catch (error) {
      if (playbackId != null && playbackId.isNotEmpty) {
        try {
          await _control.stop(control.StopRequest(playbackId: playbackId));
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
    _stopPositionPolling();
    _cuedStartFrame = 0;
    final playbackId = _playbackId;
    if (playbackId == null) {
      emit(PlaybackState(queue: state.queue, status: PlaybackStatus.stopped));
      return;
    }
    _playbackId = null;

    try {
      final status = _engine.stop();
      if (status != ListenerStatus.ok) {
        throw StateError('Engine stop failed: ${status.name}');
      }

      await _control.stop(control.StopRequest(playbackId: playbackId));
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

      _updateCurrentFrame();
      _stopPositionPolling();
      await _control.pause(control.PauseRequest(playbackId: playbackId));
      emit(state.copyWith(status: PlaybackStatus.paused));
    } catch (error) {
      _stopPositionPolling();
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
      await _control.resume(control.ResumeRequest(playbackId: playbackId));

      final status = _engine.resume();
      if (status != ListenerStatus.ok) {
        throw StateError('Engine resume failed: ${status.name}');
      }

      emit(state.copyWith(status: PlaybackStatus.playing));
      _startPositionPolling();
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

  Future<void> seekTo(double milliseconds) async {
    if (_isSeeking) return;

    final track = state.queue?.currentTrack;
    if (track == null || track.sampleRate <= 0) return;

    final targetFrame = (milliseconds * track.sampleRate / 1000).round();
    if (_playbackId == null) {
      if (state.status == PlaybackStatus.cued) {
        _cuedStartFrame = targetFrame;
        emit(state.copyWith(currentFrame: targetFrame));
      }
      return;
    }
    _isSeeking = true;
    _stopPositionPolling();

    emit(state.copyWith(currentFrame: targetFrame));

    try {
      final status = _engine.seek(targetFrame);
      if (status != ListenerStatus.ok) {
        throw StateError('Engine seek failed: ${status.name}');
      }

      _updateCurrentFrame();
      if (state.status == PlaybackStatus.playing) {
        _startPositionPolling();
      }
    } catch (error) {
      final playbackId = _playbackId;
      _playbackId = null;

      emit(
        PlaybackState(
          queue: state.queue,
          status: PlaybackStatus.error,
          currentFrame: state.currentFrame,
          errorMessage: error.toString(),
        ),
      );

      if (playbackId != null) {
        try {
          await _control.stop(control.StopRequest(playbackId: playbackId));
        } catch (_) {
          // Native seek has already stopped local playback. Remote cleanup is
          // best-effort and must not replace the original seek failure.
        }
      }
    } finally {
      _isSeeking = false;
    }
  }

  Future<void> switchOutputDevice(String? deviceId) async {
    await _cuePlaybackForOutputChange();

    final selectStatus = _engine.selectOutputDevice(deviceId);
    if (selectStatus != ListenerStatus.ok) {
      throw StateError('Unable to select audio output: ${selectStatus.name}');
    }
  }

  Future<void> configureOutput(AudioOutputConfiguration configuration) async {
    await _cuePlaybackForOutputChange();

    final configureStatus = _engine.configureOutput(configuration);
    if (configureStatus != ListenerStatus.ok) {
      throw StateError(
        'Unable to configure audio output: ${configureStatus.name}',
      );
    }
  }

  Future<void> _cuePlaybackForOutputChange() async {
    final playbackId = _playbackId;
    if (playbackId != null) {
      final position = _engine.currentFrame();
      if (position.status != ListenerStatus.ok) {
        throw StateError(
          'Unable to capture playback position: ${position.status.name}',
        );
      }

      _stopPositionPolling();
      final stopStatus = _engine.stop();
      if (stopStatus != ListenerStatus.ok) {
        throw StateError('Engine stop failed: ${stopStatus.name}');
      }

      _playbackId = null;
      _cuedStartFrame = position.frame;
      emit(
        PlaybackState(
          queue: state.queue,
          status: PlaybackStatus.cued,
          currentFrame: position.frame,
        ),
      );

      try {
        await _control.stop(control.StopRequest(playbackId: playbackId));
      } catch (_) {
        // Local playback is already stopped and safe to reconfigure. The
        // abandoned remote session will be reclaimed by the server.
      }
    }
  }

  void _startPositionPolling() {
    _stopPositionPolling();
    _updateCurrentFrame();
    _playbackFrameTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _updateCurrentFrame(),
    );
  }

  void _stopPositionPolling() {
    _playbackFrameTimer?.cancel();
    _playbackFrameTimer = null;
  }

  void _updateCurrentFrame() {
    if (_playbackId == null || isClosed) return;

    final result = _engine.currentFrame();
    if (result.status == ListenerStatus.ok) {
      emit(state.copyWith(currentFrame: result.frame));
    }
  }

  @override
  Future<void> close() async {
    _stopPositionPolling();
    await _engineEvents.cancel();
    if (_playbackId != null) {
      _engine.stop();
    }
    _engine.close();
    return super.close();
  }

  void _onEngineEvent(PlaybackEngineEvent event) {
    switch (event) {
      case Ended():
        unawaited(_handlePlaybackEnded());
      case Failed():
        unawaited(_handlePlaybackFailure());
      default:
        break;
    }
  }

  Future<void> _handlePlaybackFailure() async {
    final playbackId = _playbackId;
    if (playbackId == null || isClosed) return;
    _playbackId = null;
    _cuedStartFrame = 0;
    _stopPositionPolling();

    final status = _engine.stop();
    emit(
      PlaybackState(
        queue: state.queue,
        status: PlaybackStatus.error,
        errorMessage: 'Audio receiver failed: ${status.name}',
      ),
    );

    try {
      await _control.stop(control.StopRequest(playbackId: playbackId));
    } catch (_) {
      // The local receiver has already stopped; remote cleanup is best-effort.
    }
  }

  Future<void> _handlePlaybackEnded() async {
    final playbackId = _playbackId;
    if (playbackId == null || isClosed) return;

    final queue = state.queue;
    if (queue != null) {
      switch (queue.nextTrack) {
        case Ok<Track>(:final value):
          await play(selectedTrack: value, queueTracks: queue.tracks);
          return;
        case Error<Track>():
          _playbackId = null;
          _cuedStartFrame = 0;
          _stopPositionPolling();

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
      }
    }

    emit(PlaybackState(queue: state.queue, status: PlaybackStatus.stopped));

    try {
      await _control.stop(control.StopRequest(playbackId: playbackId));
    } catch (_) {
      // Playback has already ended locally; server cleanup is best-effort.
    }
  }
}
