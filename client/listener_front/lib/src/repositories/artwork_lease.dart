import 'package:flutter/foundation.dart';
import 'package:listener_front/src/utils/result.dart';

class ArtworkLease<T> {
  factory ArtworkLease({
    required Future<Result<T>> result,
    required VoidCallback onRelease,
  }) {
    return ArtworkLease._(result, onRelease);
  }

  ArtworkLease._(this.result, this._onRelease);

  final Future<Result<T>> result;
  final VoidCallback _onRelease;

  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}
