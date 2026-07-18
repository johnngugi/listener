import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/repositories/artwork_repository.dart';
import 'package:listener_front/src/utils/result.dart';

void main() {
  group('ArtworkRepository', () {
    test('returns cached artwork without fetching it again', () async {
      var callCount = 0;
      final repository = ArtworkRepository((request) async {
        callCount++;
        return _response(request.artworkId.toInt());
      });

      final first = await repository.get(42);
      final second = await repository.get(42);

      expect(callCount, 1);
      expect(first, isA<Ok<ArtworkResponse>>());
      expect(second, isA<Ok<ArtworkResponse>>());
      expect(
        identical(
          (first as Ok<ArtworkResponse>).value,
          (second as Ok<ArtworkResponse>).value,
        ),
        isTrue,
      );
    });

    test('shares one fetch between concurrent callers', () async {
      var callCount = 0;
      final response = Completer<grpc.GetArtworkResponse>();
      final repository = ArtworkRepository((request) {
        callCount++;
        return response.future;
      });

      final first = repository.get(42);
      final second = repository.get(42);

      expect(callCount, 1);
      response.complete(_response(42));

      final results = await Future.wait([first, second]);
      expect(results, everyElement(isA<Ok<ArtworkResponse>>()));
      expect(
        identical(
          (results[0] as Ok<ArtworkResponse>).value,
          (results[1] as Ok<ArtworkResponse>).value,
        ),
        isTrue,
      );
    });

    test('retries after a failed fetch', () async {
      var callCount = 0;
      final repository = ArtworkRepository((request) async {
        callCount++;
        if (callCount == 1) throw Exception('connection lost');
        return _response(request.artworkId.toInt());
      });

      final first = await repository.get(42);
      final second = await repository.get(42);

      expect(first, isA<Error<ArtworkResponse>>());
      expect(second, isA<Ok<ArtworkResponse>>());
      expect(callCount, 2);
    });

    test('evicts the least recently used artwork when full', () async {
      final fetchedIds = <int>[];
      final repository = ArtworkRepository((request) async {
        final artworkId = request.artworkId.toInt();
        fetchedIds.add(artworkId);
        return _response(artworkId, byteLength: 3);
      }, maxCacheBytes: 6);

      await repository.get(1);
      await repository.get(2);
      await repository.get(1); // Make 1 more recent than 2.
      await repository.get(3); // Evicts 2.
      await repository.get(2); // Must fetch 2 again.

      expect(fetchedIds, [1, 2, 3, 2]);
    });
  });
}

grpc.GetArtworkResponse _response(int artworkId, {int byteLength = 3}) {
  return grpc.GetArtworkResponse(
    artworkId: Int64(artworkId),
    mimeType: 'image/png',
    width: 1,
    height: 1,
    data: List<int>.filled(byteLength, artworkId),
  );
}
