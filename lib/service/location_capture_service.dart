import 'package:geolocator/geolocator.dart';

/// The result of a [LocationCaptureService.capture] call — the position,
/// plus whether it's a fresh fix or a fallback to the device's last known
/// location (so callers can warn the user it may be stale).
class LocationCaptureResult {
  final Position position;
  final bool isFallback;

  const LocationCaptureResult({
    required this.position,
    required this.isFallback,
  });
}

/// Wraps [Geolocator.getCurrentPosition] with a longer timeout and a
/// last-known-position fallback.
///
/// A fresh GPS fix normally comes back quickly online because "assisted
/// GPS" downloads satellite almanac/ephemeris data over the network. With
/// no connectivity, the device has to do a cold GPS-only fix, which can
/// easily take longer than a short timeout — that's what was producing a
/// generic "unable to update data" failure specifically in offline mode.
class LocationCaptureService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Attempts a fresh GPS fix (tolerant of slow/offline fixes via a 30s
  /// timeout); if that fails for any reason, falls back to the last known
  /// position rather than failing outright. Throws only when neither a
  /// fresh fix nor any last known position is available.
  static Future<LocationCaptureResult> capture() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _timeout,
      );
      return LocationCaptureResult(position: position, isFallback: false);
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LocationCaptureResult(position: lastKnown, isFallback: true);
      }
      rethrow;
    }
  }
}
