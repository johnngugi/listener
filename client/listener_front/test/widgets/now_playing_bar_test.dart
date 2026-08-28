import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/services/playback_control.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';
import 'package:listener_front/src/widgets/now_playing_bar.dart';

void main() {
  testWidgets('compact player centers transport and keeps seeking visible', (
    tester,
  ) async {
    final engine = _FakePlaybackEngine()..currentFrameValue = 30000;
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    addTearDown(cubit.close);
    await cubit.play(selectedTrack: _track);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: 700,
                child: BlocProvider.value(
                  value: cubit,
                  child: const NowPlayingBar(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Slider), findsOneWidget);

      final previousCenter = tester.getCenter(find.byIcon(Icons.skip_previous));
      final pauseCenter = tester.getCenter(find.byIcon(Icons.pause));
      final nextCenter = tester.getCenter(find.byIcon(Icons.skip_next));

      expect(pauseCenter.dx, closeTo(350, 0.1));
      expect((previousCenter.dx + nextCenter.dx) / 2, closeTo(350, 0.1));
      expect(tester.takeException(), isNull);
    } finally {
      await cubit.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('now playing bar does not overflow at responsive widths', (
    tester,
  ) async {
    final cubit = PlaybackCubit.withDependencies(
      _FakePlaybackEngine(),
      _FakePlaybackControl(),
    );
    addTearDown(cubit.close);

    for (final width in [320.0, 500.0, 700.0, 1000.0, 1200.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: width,
                child: BlocProvider.value(
                  value: cubit,
                  child: const NowPlayingBar(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'overflowed at $width px');
    }
  });

  testWidgets('keeps the timeline compact when no track is playing', (
    tester,
  ) async {
    final cubit = PlaybackCubit.withDependencies(
      _FakePlaybackEngine(),
      _FakePlaybackControl(),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_timelineHarness(cubit));

    expect(tester.getSize(find.byType(PlaybackTimeline)).height, 34);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('updates elapsed time while scrubbing and seeks on release', (
    tester,
  ) async {
    final engine = _FakePlaybackEngine()..currentFrameValue = 30000;
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    addTearDown(cubit.close);
    await cubit.play(selectedTrack: _track);

    try {
      await tester.pumpWidget(_timelineHarness(cubit));

      expect(find.text('0:30'), findsOneWidget);
      expect(find.text('2:00'), findsOneWidget);

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart?.call(60000);
      slider.onChanged?.call(60000);
      await tester.pump();

      expect(find.text('1:00'), findsOneWidget);

      slider.onChangeEnd?.call(60000);
      await tester.pump();

      expect(engine.soughtFrames, [60000]);
    } finally {
      await cubit.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Widget _timelineHarness(PlaybackCubit cubit) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 820,
          child: BlocProvider.value(
            value: cubit,
            child: const PlaybackTimeline(),
          ),
        ),
      ),
    ),
  );
}

const _track = Track(
  id: 'track-1',
  number: '1',
  title: 'Track 1',
  artist: 'Artist',
  album: 'Album',
  releaseDate: '2026',
  dateAdded: 'Today',
  plays: '0',
  durationMilliseconds: 120000,
  sampleRate: 1000,
);

final class _FakePlaybackEngine implements PlaybackEngine {
  int currentFrameValue = 0;
  final List<int> soughtFrames = [];

  @override
  Stream<PlaybackEngineEvent> get events => const Stream.empty();

  @override
  Future<DiscoveredServiceEvent> discoverService() {
    throw UnsupportedError('Discovery is not used by this fake');
  }

  @override
  ListenerStatus startStream({
    required String playbackId,
    int requestedStartFrame = 0,
  }) => ListenerStatus.ok;

  @override
  ListenerStatus stop() => ListenerStatus.ok;

  @override
  ListenerStatus pause() => ListenerStatus.ok;

  @override
  ListenerStatus resume() => ListenerStatus.ok;

  @override
  ({ListenerStatus status, int frame}) currentFrame() =>
      (status: ListenerStatus.ok, frame: currentFrameValue);

  @override
  ListenerStatus seek(int targetFrame) {
    soughtFrames.add(targetFrame);
    return ListenerStatus.ok;
  }

  @override
  void close() {}
}

final class _FakePlaybackControl implements PlaybackControl {
  @override
  Future<control.StartResponse> start(control.StartRequest request) async {
    return control.StartResponse(playbackId: 'playback-1');
  }

  @override
  Future<control.CommandResponse> stop(control.StopRequest request) async {
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
