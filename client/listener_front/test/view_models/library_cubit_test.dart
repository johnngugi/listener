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
            id: Int64(7),
            path: '/music/track-7.flac',
            artworkId: Int64(42),
          ),
          grpc.Track(id: Int64(8), path: '/music/track-8.flac'),
        ],
      );

      final tracks = mapTracks(response.tracks);

      expect(tracks[0].artworkId, 42);
      expect(tracks[1].artworkId, isNull);
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
      expect(cubit.state.status, LibraryStatus.ready);
      expect(cubit.state.tracks.map((track) => track.number), ['7', '8']);
      expect(cubit.state.nextPageToken, '8');
      expect(cubit.state.totalSize, 3);

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
        grpc.Track(id: Int64(id), path: '/music/track-$id.flac'),
    ],
    nextPageToken: nextPageToken,
    totalSize: Int64(totalSize),
  );
}
