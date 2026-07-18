import 'dart:collection';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/utils/result.dart';

typedef GetArtworkCall =
    Future<grpc.GetArtworkResponse> Function(grpc.GetArtworkRequest request);

class ArtworkRepository {
  ArtworkRepository(this._getArtwork, {int maxCacheBytes = 64 * 1024 * 1024})
    : assert(maxCacheBytes >= 0),
      _maxCacheBytes = maxCacheBytes;

  factory ArtworkRepository.connect(grpc.ListenerLibraryClient libraryClient) {
    return ArtworkRepository(libraryClient.getArtwork);
  }

  final GetArtworkCall _getArtwork;
  final int _maxCacheBytes;

  final LinkedHashMap<int, ArtworkResponse> _cache = LinkedHashMap();
  final Map<int, Future<Result<ArtworkResponse>>> _inFlight = {};

  int _cacheBytes = 0;

  Future<Result<ArtworkResponse>> get(int artworkId) async {
    final cached = _cache.remove(artworkId);
    if (cached != null) {
      // Reinsert it at the end: it is now most recently used.
      _cache[artworkId] = cached;
      return Future.value(Result.ok(cached));
    }

    final existingRequest = _inFlight[artworkId];
    if (existingRequest != null) {
      return existingRequest;
    }

    final request = _load(artworkId);
    _inFlight[artworkId] = request;

    return request;
  }

  Future<Result<ArtworkResponse>> _load(int artworkId) async {
    try {
      final result = await _fetch(artworkId);

      switch (result) {
        case Ok<ArtworkResponse>():
          _store(artworkId, result.value);
        case Error<ArtworkResponse>():
          break;
      }

      return result;
    } finally {
      _inFlight.remove(artworkId);
    }
  }

  Future<Result<ArtworkResponse>> _fetch(int artworkId) async {
    Int64 artworkId64 = Int64(artworkId);

    try {
      final response = await _getArtwork(
        grpc.GetArtworkRequest(artworkId: artworkId64),
      );

      final artworkResponse = ArtworkResponse(
        mimeType: response.mimeType,
        width: response.width,
        height: response.height,
        data: Uint8List.fromList(response.data),
      );

      return Result.ok(artworkResponse);
    } on Exception catch (err) {
      return Result.error(err);
    }
  }

  void _store(int artworkId, ArtworkResponse artwork) {
    final previous = _cache.remove(artworkId);
    if (previous != null) {
      _cacheBytes -= previous.data.lengthInBytes;
    }

    final size = artwork.data.lengthInBytes;

    if (size > _maxCacheBytes) return;

    while (_cacheBytes + size > _maxCacheBytes && _cache.isNotEmpty) {
      final oldestId = _cache.keys.first;
      final oldest = _cache.remove(oldestId)!;
      _cacheBytes -= oldest.data.lengthInBytes;
    }

    _cache[artworkId] = artwork;
    _cacheBytes += size;
  }
}

class ArtworkResponse {
  const ArtworkResponse({
    required this.mimeType,
    required this.width,
    required this.height,
    required this.data,
  });

  final String mimeType;
  final int width;
  final int height;
  final Uint8List data;
}
