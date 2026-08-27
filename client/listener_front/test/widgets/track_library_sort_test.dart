import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/widgets/track_library.dart';

void main() {
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
}
