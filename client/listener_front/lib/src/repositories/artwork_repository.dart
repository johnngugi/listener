import 'dart:async';
import 'dart:collection';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/repositories/artwork_lease.dart';
import 'package:listener_front/src/utils/result.dart';

typedef GetArtworkCall =
    Future<grpc.GetArtworkResponse> Function(grpc.GetArtworkRequest request);

class ArtworkRepository {
  ArtworkRepository(
    this._getArtwork, {
    int maxCacheBytes = 64 * 1024 * 1024,
    int maxConcurrentRequests = 6,
  }) : assert(maxCacheBytes >= 0),
       assert(maxConcurrentRequests > 0),
       _maxCacheBytes = maxCacheBytes,
       _maxConcurrentRequests = maxConcurrentRequests;

  factory ArtworkRepository.connect(grpc.ListenerLibraryClient libraryClient) {
    return ArtworkRepository(libraryClient.getArtwork);
  }

  final GetArtworkCall _getArtwork;
  final int _maxCacheBytes;
  final int _maxConcurrentRequests;

  final LinkedHashMap<int, ArtworkResponse> _cache = LinkedHashMap();
  final Map<int, _ArtworkTask> _tasks = {};
  final ListQueue<_ArtworkTask> _pending = ListQueue();

  int _activeRequests = 0;

  int _cacheBytes = 0;

  ArtworkLease<ArtworkResponse> acquire(int artworkId) {
    final cached = _cache.remove(artworkId);

    if (cached != null) {
      // Reinsert it at the end: it is now most recently used.
      _cache[artworkId] = cached;
      return ArtworkLease(
        result: Future.value(Result.ok(cached)),
        onRelease: () {},
      );
    }

    var task = _tasks[artworkId];

    if (task == null) {
      task = _ArtworkTask(artworkId);
      _tasks[artworkId] = task;
      _pending.addLast(task);
    }

    task.subscribers += 1;
    _pumpQueue();
    final acquiredTask = task;

    return ArtworkLease(
      result: acquiredTask.completer.future,
      onRelease: () => _release(acquiredTask),
    );
  }

  /// Compatibility wrapper for callers that do not yet manage a lease.
  ///
  /// New UI callers should use [acquire] so they can release queued work when
  /// it is no longer visible.
  Future<Result<ArtworkResponse>> get(int artworkId) {
    final lease = acquire(artworkId);
    return lease.result.whenComplete(lease.release);
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

  void _pumpQueue() {
    while (_activeRequests < _maxConcurrentRequests && _pending.isNotEmpty) {
      final task = _pending.removeFirst();

      if (task.subscribers == 0) {
        continue;
      }

      task.started = true;
      _activeRequests += 1;
      unawaited(_run(task));
    }
  }

  Future<void> _run(_ArtworkTask task) async {
    Result<ArtworkResponse>? result;

    try {
      result = await _fetch(task.artworkId);

      switch (result) {
        case Ok<ArtworkResponse>():
          _store(task.artworkId, result.value);
        case Error<ArtworkResponse>():
          break;
      }
    } on Exception catch (error) {
      // Defensive: _fetch currently converts Exceptions into Result.error,
      // but this also covers failures from surrounding repository logic.
      result = Result.error(error);
    } catch (error) {
      // Result.error requires an Exception.
      result = Result.error(Exception('Unexpected artwork error: $error'));
    } finally {
      task.completed = true;

      // Avoid accidentally removing a newer task for the same ID.
      if (identical(_tasks[task.artworkId], task)) {
        _tasks.remove(task.artworkId);
      }

      _activeRequests--;

      if (!task.completer.isCompleted) {
        task.completer.complete(
          result ??
              Result.error(Exception('Artwork request ended without a result')),
        );
      }

      _pumpQueue();
    }
  }

  void _release(_ArtworkTask task) {
    if (task.completed || task.subscribers == 0) return;

    task.subscribers -= 1;

    if (task.subscribers > 0 || task.started) {
      return;
    }

    task.completed = true;

    if (identical(_tasks[task.artworkId], task)) {
      _tasks.remove(task.artworkId);
    }
    _pending.remove(task);

    if (!task.completer.isCompleted) {
      task.completer.complete(Result.error(ArtworkRequestCancelledException()));
    }
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

class ArtworkRequestCancelledException implements Exception {}

class _ArtworkTask {
  _ArtworkTask(this.artworkId);

  final int artworkId;
  final completer = Completer<Result<ArtworkResponse>>();

  int subscribers = 0;
  bool started = false;
  bool completed = false;
}
