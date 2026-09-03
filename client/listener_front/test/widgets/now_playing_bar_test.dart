import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;
import 'package:listener_front/src/generated/listener/v1/listener.pb.dart'
    as listener;
import 'package:listener_front/src/app.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/services/playback_control.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';
import 'package:listener_front/src/view_models/output_device_cubit.dart';
import 'package:listener_front/src/widgets/now_playing_bar.dart';
import 'package:listener_front/src/widgets/sidebar.dart';

void main() {
  testWidgets('wide player centers transport in the library pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = _FakePlaybackEngine();
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 1600,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: cubit),
                  BlocProvider.value(value: outputCubit),
                ],
                child: const NowPlayingBar(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getCenter(find.byKey(const Key('transport-controls'))).dx,
      closeTo(800, 0.1),
    );
    expect(tester.getSize(find.byType(NowPlayingBar)).height, 108);
    expect(
      tester.getSize(find.byType(PlaybackTimeline)).width,
      greaterThan(
        tester.getSize(find.byKey(const Key('transport-button-cluster'))).width,
      ),
    );
    final playerTop = tester.getTopLeft(find.byType(NowPlayingBar)).dy;
    expect(
      tester.getTopLeft(find.byKey(const Key('transport-button-row'))).dy -
          playerTop,
      greaterThanOrEqualTo(8),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop player spans beneath the sidebar', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = _FakePlaybackEngine();
    final playbackCubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, playbackCubit);
    final libraryCubit = LibraryCubit(
      (_) async => listener.ListTracksResponse(),
    );
    addTearDown(libraryCubit.close);
    addTearDown(playbackCubit.close);
    addTearDown(outputCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: libraryCubit),
          BlocProvider.value(value: playbackCubit),
          BlocProvider.value(value: outputCubit),
        ],
        child: const MainApp(),
      ),
    );

    final sidebarRect = tester.getRect(find.byType(Sidebar));
    final playerRect = tester.getRect(find.byType(NowPlayingBar));
    expect(sidebarRect, const Rect.fromLTWH(0, 0, sidebarWidth, 692));
    expect(playerRect.left, 0);
    expect(playerRect.right, 1600);
    expect(playerRect.bottom, 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact player centers transport and keeps seeking visible', (
    tester,
  ) async {
    final engine = _FakePlaybackEngine()..currentFrameValue = 30000;
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);
    await cubit.play(selectedTrack: _track);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: 700,
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: cubit),
                    BlocProvider.value(value: outputCubit),
                  ],
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
    final engine = _FakePlaybackEngine();
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);

    for (final width in [320.0, 500.0, 700.0, 1000.0, 1200.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: width,
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: cubit),
                    BlocProvider.value(value: outputCubit),
                  ],
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

  testWidgets('opens and edits the playback queue', (tester) async {
    final engine = _FakePlaybackEngine();
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);
    final tracks = [_track, _hiResTrack];
    await cubit.play(selectedTrack: tracks.first, queueTracks: tracks);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: cubit),
                BlocProvider.value(value: outputCubit),
              ],
              child: const NowPlayingBar(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('playback-queue-button')));
    await tester.pumpAndSettle();

    expect(find.text('Playback queue'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    expect(find.text('Now playing · Artist'), findsOneWidget);
    expect(find.text('High Resolution Track'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remove-queue-item-track-hi-res')));
    await tester.pump();

    expect(cubit.state.queue?.tracks, [_track]);
    expect(find.text('1 track'), findsOneWidget);

    await cubit.pause();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('plays an item selected from the playback queue', (tester) async {
    final engine = _FakePlaybackEngine();
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);
    final tracks = [_track, _hiResTrack];
    await cubit.play(selectedTrack: tracks.first, queueTracks: tracks);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: cubit),
                BlocProvider.value(value: outputCubit),
              ],
              child: const NowPlayingBar(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('playback-queue-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playback-queue-item-track-hi-res')));
    await tester.pumpAndSettle();

    expect(cubit.state.queue?.currentTrack, _hiResTrack);
    expect(find.text('Playback queue'), findsNothing);

    await cubit.pause();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows the current track audio format', (tester) async {
    final engine = _FakePlaybackEngine();
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);
    await cubit.play(selectedTrack: _hiResTrack);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: 700,
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: cubit),
                    BlocProvider.value(value: outputCubit),
                  ],
                  child: const NowPlayingBar(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('now-playing-format')), findsOneWidget);
      expect(find.text('FLAC · 24-bit · 96 kHz'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await cubit.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    }
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

  testWidgets('opens the volume popover and updates software volume', (
    tester,
  ) async {
    final engine = _FakePlaybackEngine();
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);
    cubit.setVolumeMode(VolumeMode.software);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 700,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: cubit),
                  BlocProvider.value(value: outputCubit),
                ],
                child: const NowPlayingBar(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('software-volume-popover-slider')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('software-volume-button')));
    await tester.pumpAndSettle();

    final popoverRect = tester.getRect(
      find.byKey(const Key('software-volume-popover')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const Key('software-volume-button')),
    );
    expect(popoverRect.bottom, lessThanOrEqualTo(buttonRect.top));

    final slider = tester.widget<Slider>(
      find.byKey(const Key('software-volume-popover-slider')),
    );
    expect(slider.divisions, 100);
    expect(slider.label, isNull);
    slider.onChanged?.call(0.5);
    await tester.pumpAndSettle();

    expect(cubit.state.volume, 0.5);
    expect(engine.volumes, [1, 0.5]);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('explains bit-perfect and processed signal paths', (
    tester,
  ) async {
    final engine = _FakePlaybackEngine(
      devices: const [
        AudioOutputDevice(
          id: 'usb-dac',
          name: 'Reference DAC',
          isDefault: true,
          capabilities: AudioOutputCapabilities(supportsExclusiveMode: true),
        ),
      ],
    );
    final cubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, cubit);
    addTearDown(cubit.close);
    addTearDown(outputCubit.close);

    expect(await outputCubit.setExclusiveMode(true), isTrue);
    await cubit.play(selectedTrack: _hiResTrack);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 700,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: cubit),
                  BlocProvider.value(value: outputCubit),
                ],
                child: const NowPlayingBar(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bit-perfect'), findsNothing);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('signal-path-button')));
    await tester.pumpAndSettle();

    expect(find.text('FLAC · 24-bit · 96 kHz'), findsWidgets);
    expect(find.text('Reference DAC · Exclusive'), findsOneWidget);
    expect(find.text('Fixed output · 0 dB'), findsOneWidget);

    final softwareMode = find.byKey(const Key('software-volume-mode'));
    await tester.scrollUntilVisible(
      softwareMode,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(softwareMode);
    await tester.pumpAndSettle();
    expect(cubit.state.volumeMode, VolumeMode.software);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('software-volume-slider')),
    );
    expect(slider.onChanged, isNotNull);
    slider.onChanged?.call(0.5);
    await tester.pumpAndSettle();
    expect(cubit.state.volume, 0.5);
    expect(find.text('Software · 50%'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('signal-path-status')),
      -180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();

    expect(find.text('Not bit-perfect'), findsWidgets);
    expect(
      find.text('Software volume is changing the PCM samples.'),
      findsOneWidget,
    );

    await cubit.pause();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selects an external output and restores system output', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = _FakePlaybackEngine(
      devices: const [
        AudioOutputDevice(
          id: 'built-in',
          name: 'Mac Speakers',
          isDefault: true,
        ),
        AudioOutputDevice(
          id: 'usb-dac',
          name: 'Reference USB DAC',
          isDefault: false,
          capabilities: AudioOutputCapabilities(supportsExclusiveMode: true),
        ),
      ],
    )..currentFrameValue = 42000;
    final playbackCubit = PlaybackCubit.withDependencies(
      engine,
      _FakePlaybackControl(),
    );
    final outputCubit = OutputDeviceCubit(engine, playbackCubit);
    addTearDown(playbackCubit.close);
    addTearDown(outputCubit.close);
    await playbackCubit.play(selectedTrack: _track);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 1200,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: playbackCubit),
                  BlocProvider.value(value: outputCubit),
                ],
                child: const NowPlayingBar(),
              ),
            ),
          ),
        ),
      ),
    );

    final outputButton = find.byKey(const Key('output-device-picker-button'));
    expect(tester.getSize(outputButton).width, 112);
    expect(
      tester.getCenter(find.byKey(const Key('output-device-label'))).dy,
      greaterThan(
        tester.getCenter(find.byKey(const Key('output-device-icon'))).dy,
      ),
    );

    await tester.tap(outputButton);
    await tester.pumpAndSettle();

    expect(find.text('Audio output'), findsOneWidget);
    expect(
      find.text('Playback will pause at its current position.'),
      findsOneWidget,
    );
    expect(find.text('Mac Speakers'), findsOneWidget);
    expect(find.text('Reference USB DAC'), findsOneWidget);

    await tester.tap(find.byKey(const Key('output-device-option-usb-dac')));
    await tester.pumpAndSettle();

    expect(engine.selectedDeviceIds, ['usb-dac']);
    expect(engine.stopCallCount, 1);
    expect(playbackCubit.state.status, PlaybackStatus.cued);
    expect(playbackCubit.state.currentFrame, 42000);
    expect(find.text('Reference USB DAC'), findsOneWidget);

    await tester.tap(find.byKey(const Key('output-device-picker-button')));
    await tester.pumpAndSettle();

    expect(find.text('Exclusive mode'), findsOneWidget);
    await tester.tap(find.byKey(const Key('exclusive-mode-toggle')));
    await tester.pumpAndSettle();

    expect(engine.configuredOutputs.single.exclusiveMode, isTrue);
    expect(outputCubit.state.exclusiveMode, isTrue);

    await tester.tap(find.byKey(const Key('output-device-option-system')));
    await tester.pumpAndSettle();

    expect(engine.selectedDeviceIds, ['usb-dac', null]);
    expect(
      engine.configuredOutputs.map(
        (configuration) => configuration.exclusiveMode,
      ),
      [true, false],
    );
    expect(engine.stopCallCount, 1);
    expect(find.text('System Output'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    expect(engine.requestedStartFrames, [0, 42000]);
    expect(playbackCubit.state.status, PlaybackStatus.playing);

    await playbackCubit.pause();
    await tester.pumpWidget(const SizedBox.shrink());
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
  codec: 'flac',
  sampleRate: 1000,
  bitsPerSample: 24,
);

const _hiResTrack = Track(
  id: 'track-hi-res',
  number: '2',
  title: 'High Resolution Track',
  artist: 'Artist',
  album: 'Album',
  releaseDate: '2026',
  dateAdded: 'Today',
  plays: '0',
  durationMilliseconds: 120000,
  codec: 'flac',
  sampleRate: 96000,
  bitsPerSample: 24,
);

final class _FakePlaybackEngine implements PlaybackEngine {
  _FakePlaybackEngine({this.devices = const []});

  final List<AudioOutputDevice> devices;
  final List<String?> selectedDeviceIds = [];
  final List<AudioOutputConfiguration> configuredOutputs = [];
  final List<double> volumes = [];

  @override
  List<AudioOutputDevice> outputDevices() => devices;

  @override
  ListenerStatus selectOutputDevice(String? deviceId) {
    selectedDeviceIds.add(deviceId);
    return ListenerStatus.ok;
  }

  @override
  ListenerStatus configureOutput(AudioOutputConfiguration configuration) {
    configuredOutputs.add(configuration);
    return ListenerStatus.ok;
  }

  int currentFrameValue = 0;
  int stopCallCount = 0;
  final List<int> requestedStartFrames = [];
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
  }) {
    requestedStartFrames.add(requestedStartFrame);
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
  ({ListenerStatus status, int frame}) currentFrame() =>
      (status: ListenerStatus.ok, frame: currentFrameValue);

  @override
  ListenerStatus seek(int targetFrame) {
    soughtFrames.add(targetFrame);
    return ListenerStatus.ok;
  }

  @override
  ListenerStatus setVolume(double volume) {
    volumes.add(volume);
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
