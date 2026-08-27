import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/models/library_state.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';

void main() {
  group('LibraryCubit', () {
    test('maps the optional artwork ID onto a track', () {
      final response = grpc.ListTracksResponse(
        tracks: [
          grpc.Track(
            id: '00000000-0000-4000-8000-000000000007',
            artworkId: Int64(42),
            sampleRate: 48000,
            dateAddedUnixSeconds: Int64(
              DateTime.utc(2026, 3, 18, 12).millisecondsSinceEpoch ~/
                  Duration.millisecondsPerSecond,
            ),
          ),
          grpc.Track(id: '00000000-0000-4000-8000-000000000008'),
        ],
      );

      final tracks = mapTracks(response.tracks);

      expect(tracks[0].artworkId, 42);
      expect(tracks[0].sampleRate, 48000);
      expect(tracks[0].dateAdded, '18 Mar 2026');
      expect(tracks[1].artworkId, isNull);
      expect(tracks[1].dateAdded, isEmpty);
    });

    test('loads the first page and exposes the server total', () async {
      late grpc.ListTracksRequest request;
      final cubit = LibraryCubit((value) async {
        request = value;
        return _response(ids: [7, 8], nextPageToken: '8', totalSize: 3);
      });

      final load = cubit.listTracks();

      expect(cubit.state.status, LibraryStatus.loadingFirstPage);
      await load;
      expect(request.pageSize, LibraryCubit.libraryPageSize);
      expect(request.pageToken, isEmpty);
      expect(
        request.sortField,
        grpc.TrackSortField.TRACK_SORT_FIELD_ALBUM_ARTIST,
      );
      expect(
        request.sortDirection,
        grpc.SortDirection.SORT_DIRECTION_ASCENDING,
      );
      expect(cubit.state.status, LibraryStatus.ready);
      expect(cubit.state.tracks.map((track) => track.number), ['7', '8']);
      expect(cubit.state.nextPageToken, '8');
      expect(cubit.state.totalSize, 3);

      await cubit.close();
    });

    test(
      'keeps loaded rows stable until the sorted server page arrives',
      () async {
        var callCount = 0;
        final sortedPage = Completer<grpc.ListTracksResponse>();
        late grpc.ListTracksRequest sortRequest;
        final cubit = LibraryCubit((request) async {
          callCount++;
          if (callCount == 1) {
            return _response(ids: [2, 1], totalSize: 2);
          }
          sortRequest = request;
          return sortedPage.future;
        });

        await cubit.listTracks();
        final sort = cubit.setSort(LibrarySortField.trackNumber);

        expect(cubit.state.sortField, LibrarySortField.trackNumber);
        expect(cubit.state.sortDirection, LibrarySortDirection.ascending);
        expect(cubit.state.tracks.map((track) => track.number), ['2', '1']);
        expect(cubit.state.isRefreshing, isTrue);
        expect(
          sortRequest.sortField,
          grpc.TrackSortField.TRACK_SORT_FIELD_TRACK_NUMBER,
        );
        expect(
          sortRequest.sortDirection,
          grpc.SortDirection.SORT_DIRECTION_ASCENDING,
        );
        expect(sortRequest.pageToken, isEmpty);

        sortedPage.complete(_response(ids: [1, 2], totalSize: 2));
        await sort;

        expect(cubit.state.tracks.map((track) => track.number), ['1', '2']);
        expect(cubit.state.isRefreshing, isFalse);
        expect(cubit.state.status, LibraryStatus.ready);
        await cubit.close();
      },
    );

    test('toggles direction when the active sort field is selected', () async {
      final requests = <grpc.ListTracksRequest>[];
      final cubit = LibraryCubit((request) async {
        requests.add(request);
        return _response(ids: [1], totalSize: 1);
      });

      await cubit.listTracks();
      await cubit.setSort(LibrarySortField.title);
      await cubit.setSort(LibrarySortField.title);

      expect(
        requests[1].sortDirection,
        grpc.SortDirection.SORT_DIRECTION_ASCENDING,
      );
      expect(
        requests[2].sortDirection,
        grpc.SortDirection.SORT_DIRECTION_DESCENDING,
      );
      expect(cubit.state.sortDirection, LibrarySortDirection.descending);
      await cubit.close();
    });

    test('ignores a stale response after another sort is selected', () async {
      var callCount = 0;
      final titlePage = Completer<grpc.ListTracksResponse>();
      final albumPage = Completer<grpc.ListTracksResponse>();
      final cubit = LibraryCubit((request) {
        callCount++;
        return switch (callCount) {
          1 => Future.value(_response(ids: [1], totalSize: 1)),
          2 => titlePage.future,
          _ => albumPage.future,
        };
      });

      await cubit.listTracks();
      final titleSort = cubit.setSort(LibrarySortField.title);
      final albumSort = cubit.setSort(LibrarySortField.album);

      albumPage.complete(_response(ids: [3], totalSize: 1));
      await albumSort;
      titlePage.complete(_response(ids: [2], totalSize: 1));
      await titleSort;

      expect(cubit.state.sortField, LibrarySortField.album);
      expect(cubit.state.tracks.single.number, '3');
      expect(cubit.state.isRefreshing, isFalse);
      await cubit.close();
    });

    test('appends the next page and ignores overlapping requests', () async {
      var callCount = 0;
      final secondPage = Completer<grpc.ListTracksResponse>();
      final cubit = LibraryCubit((request) async {
        callCount++;
        if (callCount == 1) {
          return _response(ids: [1], nextPageToken: '1', totalSize: 2);
        }
        expect(request.pageToken, '1');
        expect(
          request.sortField,
          grpc.TrackSortField.TRACK_SORT_FIELD_ALBUM_ARTIST,
        );
        expect(
          request.sortDirection,
          grpc.SortDirection.SORT_DIRECTION_ASCENDING,
        );
        return secondPage.future;
      });

      await cubit.listTracks();
      final loadMore = cubit.loadNextPage();
      await cubit.loadNextPage();

      expect(cubit.state.status, LibraryStatus.loadingMore);
      expect(callCount, 2);

      secondPage.complete(_response(ids: [2], totalSize: 2));
      await loadMore;

      expect(cubit.state.status, LibraryStatus.ready);
      expect(cubit.state.tracks.map((track) => track.number), ['1', '2']);
      expect(cubit.state.hasMore, isFalse);

      await cubit.loadNextPage();
      expect(callCount, 2);
      await cubit.close();
    });

    test(
      'retains loaded tracks when loading more fails and can retry',
      () async {
        var callCount = 0;
        final cubit = LibraryCubit((request) async {
          callCount++;
          if (callCount == 1) {
            return _response(ids: [1], nextPageToken: '1', totalSize: 2);
          }
          if (callCount == 2) throw Exception('connection lost');
          return _response(ids: [2], totalSize: 2);
        });

        await cubit.listTracks();
        await cubit.loadNextPage();

        expect(cubit.state.status, LibraryStatus.failure);
        expect(cubit.state.tracks.single.number, '1');
        expect(cubit.state.errorMessage, contains('connection lost'));

        await cubit.retry();

        expect(cubit.state.status, LibraryStatus.ready);
        expect(cubit.state.tracks.map((track) => track.number), ['1', '2']);
        expect(cubit.state.errorMessage, isNull);
        await cubit.close();
      },
    );
  });
}

grpc.ListTracksResponse _response({
  required List<int> ids,
  String nextPageToken = '',
  required int totalSize,
}) {
  return grpc.ListTracksResponse(
    tracks: [
      for (final id in ids)
        grpc.Track(
          id: '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
          trackNumber: id,
        ),
    ],
    nextPageToken: nextPageToken,
    totalSize: Int64(totalSize),
  );
}
