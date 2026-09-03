import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/widgets/sidebar.dart';
import 'package:listener_front/src/widgets/track_library.dart';

void main() {
  testWidgets('sidebar settings button invokes its callback', (tester) async {
    var openedSettings = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Sidebar(onSettings: () => openedSettings = true)),
      ),
    );

    await tester.tap(find.byKey(const Key('server-settings-button')));

    expect(openedSettings, isTrue);
    expect(tester.getSize(find.byType(Sidebar)).width, sidebarWidth);
  });

  testWidgets('compact library top bar opens the navigation drawer', (
    tester,
  ) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: const Drawer(width: sidebarWidth, child: Sidebar()),
          body: const LibraryTopBar(showSidebarButton: true),
        ),
      ),
    );

    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);

    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();

    expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);
    expect(find.text('Listener'), findsOneWidget);
  });

  testWidgets('clicking a sortable header updates its arrow and request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requests = <grpc.ListTracksRequest>[];
    final cubit = LibraryCubit((request) async {
      requests.add(request);
      return grpc.ListTracksResponse(totalSize: Int64.ZERO);
    });
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: const TrackTableHeader(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

    await tester.tap(find.text('Album'));
    await tester.pump();

    expect(requests, hasLength(1));
    expect(
      requests.single.sortField,
      grpc.TrackSortField.TRACK_SORT_FIELD_ALBUM,
    );
    expect(
      requests.single.sortDirection,
      grpc.SortDirection.SORT_DIRECTION_ASCENDING,
    );
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);

    await tester.tap(find.text('Album'));
    await tester.pump();

    expect(requests, hasLength(2));
    expect(
      requests.last.sortDirection,
      grpc.SortDirection.SORT_DIRECTION_DESCENDING,
    );
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
  });

  testWidgets('library content does not overflow at responsive widths', (
    tester,
  ) async {
    final cubit = LibraryCubit(
      (_) async => grpc.ListTracksResponse(totalSize: Int64(1)),
    );
    addTearDown(cubit.close);

    for (final width in [320.0, 600.0, 900.0, 1400.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LibraryTopBar(),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: LibraryTitle(),
                      ),
                      TrackTableHeader(),
                      TrackRow(track: _responsiveTrack),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'overflowed at $width px');
    }
  });

  testWidgets('library toolbar reports search text and offers sorting', (
    tester,
  ) async {
    final cubit = LibraryCubit(
      (_) async => grpc.ListTracksResponse(totalSize: Int64.ZERO),
    );
    addTearDown(cubit.close);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var query = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SizedBox(
              width: 700,
              child: LibraryToolbar(
                controller: controller,
                query: query,
                onQueryChanged: (value) => query = value,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('library-search-field')),
      'Alan Walker',
    );

    expect(query, 'Alan Walker');
    expect(find.byTooltip('Sort tracks'), findsOneWidget);
  });

  testWidgets('compact track row combines artist and album metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: TrackRow(track: _responsiveTrack, isCurrent: true),
          ),
        ),
      ),
    );

    expect(
      find.text('A long album artist name · A long album title'),
      findsOne,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _responsiveTrack = Track(
  id: 'track-1',
  number: '12',
  title: 'A deliberately long track title for compact layouts',
  artist: 'A long album artist name',
  album: 'A long album title',
  releaseDate: '2026-08-28',
  dateAdded: 'Today',
  plays: '120',
  durationMilliseconds: 245000,
  codec: 'flac',
  sampleRate: 48000,
  bitsPerSample: 24,
);
