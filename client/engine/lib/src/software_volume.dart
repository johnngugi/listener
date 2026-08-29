import 'dart:math' as math;

/// Maps the UI's perceptual volume position to the linear gain used by DSP.
abstract final class SoftwareVolume {
  /// The quietest non-muted slider position.
  static const double floorDecibels = -60;

  static double decibels(double volume) {
    _validate(volume);
    if (volume == 0) return double.negativeInfinity;
    return floorDecibels * (1 - volume);
  }

  static double linearGain(double volume) {
    final level = decibels(volume);
    if (level == double.negativeInfinity) return 0;
    return math.pow(10, level / 20).toDouble();
  }

  static void _validate(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw RangeError.range(volume, 0, 1, 'volume');
    }
  }
}
