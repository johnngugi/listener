import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/services/playback_control.dart';
import 'package:listener_front/src/services/playback_engine.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';

void main() {
  group('PlaybackCubit continuous playback', () {
    test(
      'samples the engine position immediately and preserves it on pause',
      () async {
        final engine = _FakePlaybackEngine()..currentFrameValue = 1250;
        final controlClient = _FakePlaybackControl();
        final cubit = PlaybackCubit.withDependencies(engine, controlClient);

        await cubit.play(selectedTrack: _track(1));

        expect(cubit.state.currentFrame, 1250);
        expect(engine.currentFrameCallCount, 1);

        engine.currentFrameValue = 2000;
        await cubit.pause();

        expect(cubit.state.status, PlaybackStatus.paused);
        expect(cubit.state.currentFrame, 2000);
        expect(engine.currentFrameCallCount, 2);

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(engine.currentFrameCallCount, 2);

        await cubit.close();
      },
    );

    test('plays the next track when the current track ends', () async {
      final engine = _FakePlaybackEngine();
      final controlClient = _FakePlaybackControl();
      final cubit = PlaybackCubit.withDependencies(engine, controlClient);
      final tracks = [_track(1), _track(2)];

      await cubit.play(selectedTrack: tracks.first, queueTracks: tracks);
      engine.addEvent(PlaybackEngineEvent.ended);
      await _waitForState(
        cubit,
        (state) =>
            state.status == PlaybackStatus.playing &&
            state.queue?.currentTrack == tracks.last,
      );
      await _flushEvents();

      expect(cubit.state.status, PlaybackStatus.playing);
      expect(cubit.state.queue?.currentTrack, tracks.last);
      expect(controlClient.startedTrackIds, ['track-1', 'track-2']);
      expect(controlClient.stoppedPlaybackIds, ['playback-1']);
      expect(engine.startedPlaybackIds, ['playback-1', 'playback-2']);
      expect(engine.stopCallCount, 1);

      await cubit.close();
    });

    test('stops when the final track ends', () async {
      final engine = _FakePlaybackEngine();
      final controlClient = _FakePlaybackControl();
      final cubit = PlaybackCubit.withDependencies(engine, controlClient);
      final tracks = [_track(1), _track(2)];

      await cubit.play(selectedTrack: tracks.last, queueTracks: tracks);
      final stopped = _waitForState(
        cubit,
        (state) => state.status == PlaybackStatus.stopped,
      );
      engine.addEvent(PlaybackEngineEvent.ended);
      await stopped;

      expect(cubit.state.queue?.currentTrack, tracks.last);
      expect(controlClient.startedTrackIds, ['track-2']);
      expect(controlClient.stoppedPlaybackIds, ['playback-1']);
      expect(engine.stopCallCount, 1);

      await cubit.close();
    });

    test('preserves an error when the next track cannot start', () async {
      final engine = _FakePlaybackEngine();
      final controlClient = _FakePlaybackControl(failStartCall: 2);
      final cubit = PlaybackCubit.withDependencies(engine, controlClient);
      final tracks = [_track(1), _track(2)];

      await cubit.play(selectedTrack: tracks.first, queueTracks: tracks);
      engine.addEvent(PlaybackEngineEvent.ended);
      await _waitForState(
        cubit,
        (state) => state.status == PlaybackStatus.error,
      );
      await _flushEvents();

      expect(cubit.state.status, PlaybackStatus.error);
      expect(cubit.state.errorMessage, contains('start failed'));
      expect(cubit.state.queue?.currentTrack, tracks.last);

      await cubit.close();
    });

    test('clears the playback session when native seeking fails', () async {
      final engine = _FakePlaybackEngine();
      final controlClient = _FakePlaybackControl();
      final cubit = PlaybackCubit.withDependencies(engine, controlClient);

      await cubit.play(selectedTrack: _track(1));
      engine.seekStatus = ListenerStatus.invalidSeekFrame;

      await cubit.seekTo(42000);

      expect(engine.soughtFrames, [42000]);
      expect(engine.stopCallCount, 0);
      expect(controlClient.stoppedPlaybackIds, ['playback-1']);
      expect(cubit.state.status, PlaybackStatus.error);
      expect(cubit.state.errorMessage, contains('invalidSeekFrame'));

      await cubit.close();
    });
  });
}

Future<PlaybackState> _waitForState(
  PlaybackCubit cubit,
  bool Function(PlaybackState state) matches,
) {
  if (matches(cubit.state)) return Future.value(cubit.state);
  return cubit.stream.firstWhere(matches);
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Track _track(int number) {
  return Track(
    id: 'track-$number',
    number: '$number',
    title: 'Track $number',
    artist: 'Artist',
    album: 'Album',
    releaseDate: '2026',
    dateAdded: 'Today',
    plays: '0',
    durationMilliseconds: 180000,
    sampleRate: 1000,
  );
}

final class _FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackEngineEvent> _events =
      StreamController<PlaybackEngineEvent>.broadcast();

  final List<String> startedPlaybackIds = [];
  int stopCallCount = 0;
  int currentFrameCallCount = 0;
  int currentFrameValue = 0;
  ListenerStatus seekStatus = ListenerStatus.ok;
  final List<int> soughtFrames = [];

  @override
  Stream<PlaybackEngineEvent> get events => _events.stream;

  void addEvent(PlaybackEngineEvent event) => _events.add(event);

  @override
  ListenerStatus startStream({
    required String playbackId,
    int requestedStartFrame = 0,
  }) {
    startedPlaybackIds.add(playbackId);
    return ListenerStatus.ok;
  }

  @override
  ListenerStatus stop() {
    stopCallCount++;
    return ListenerStatus.ok;
  }

  @override
  ListenerStatus pause() => ListenerStatus.ok;

  @override
  ListenerStatus resume() => ListenerStatus.ok;

  @override
  ({ListenerStatus status, int frame}) currentFrame() {
    currentFrameCallCount++;
    return (status: ListenerStatus.ok, frame: currentFrameValue);
  }

  @override
  ListenerStatus seek(int targetFrame) {
    soughtFrames.add(targetFrame);
    return seekStatus;
  }

  @override
  void close() {
    unawaited(_events.close());
  }
}

final class _FakePlaybackControl implements PlaybackControl {
  _FakePlaybackControl({this.failStartCall});

  final int? failStartCall;
  final List<String> startedTrackIds = [];
  final List<String> stoppedPlaybackIds = [];

  int _startCallCount = 0;

  @override
  Future<control.StartResponse> start(control.StartRequest request) async {
    _startCallCount++;
    startedTrackIds.add(request.trackId);
    if (_startCallCount == failStartCall) {
      throw StateError('start failed');
    }
    return control.StartResponse(playbackId: 'playback-$_startCallCount');
  }

  @override
  Future<control.CommandResponse> stop(control.StopRequest request) async {
    stoppedPlaybackIds.add(request.playbackId);
    return control.CommandResponse(playbackId: request.playbackId);
  }

  @override
  Future<control.CommandResponse> pause(control.PauseRequest request) async {
    return control.CommandResponse(playbackId: request.playbackId);
  }

  @override
  Future<control.CommandResponse> resume(control.ResumeRequest request) async {
    return control.CommandResponse(playbackId: request.playbackId);
  }
}
