import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Utility class for polygon calculations
class PolygonCalculator {
  /// Earth's radius in meters
  static const double earthRadiusMeters = 6371000;

  /// Calculate the area of a polygon using the Shoelace formula
  /// Returns the area in hectares (1 hectare = 10,000 m²)
  /// Coordinates should be in lat/lng format in decimal degrees
  static double calculatePolygonAreaInHectares(List<LatLng> coordinates) {
    if (coordinates.length < 3) {
      return 0.0;
    }

    // Convert to Web Mercator and use Shoelace formula
    double areaInSquareMeters = _calculateAreaWithHaversine(coordinates);
    
    // Convert from square meters to hectares (1 hectare = 10,000 m²)
    double areaInHectares = areaInSquareMeters / 10000.0;
    
    return areaInHectares;
  }

  /// Calculate polygon area using Haversine formula for lat/lng coordinates
  /// Returns area in square meters
  static double _calculateAreaWithHaversine(List<LatLng> coordinates) {
    // Close the polygon if not already closed
    List<LatLng> closedCoordinates = List.from(coordinates);
    if (closedCoordinates.first != closedCoordinates.last) {
      closedCoordinates.add(closedCoordinates.first);
    }

    double area = 0.0;

    for (int i = 0; i < closedCoordinates.length - 1; i++) {
      final p1 = closedCoordinates[i];
      final p2 = closedCoordinates[i + 1];

      // Convert to radians
      double lat1Rad = _toRadians(p1.latitude);
      double lon1Rad = _toRadians(p1.longitude);
      double lat2Rad = _toRadians(p2.latitude);
      double lon2Rad = _toRadians(p2.longitude);

      // Calculate angle between points using spherical law of cosines
      double dLon = lon2Rad - lon1Rad;
      double E = 2 * math.atan2(
        math.tan(dLon / 2) * (math.tan(lat1Rad / 2) + math.tan(lat2Rad / 2)),
        1 + math.tan(lat1Rad / 2) * math.tan(lat2Rad / 2),
      );

      area += E;
    }

    area = area.abs() * earthRadiusMeters * earthRadiusMeters / 2;
    return area;
  }

  /// Convert degrees to radians
  static double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  /// Calculate perimeter of polygon in kilometers
  static double calculatePerimeterInKm(List<LatLng> coordinates) {
    if (coordinates.isEmpty) return 0.0;

    double perimeter = 0.0;
    List<LatLng> closedCoordinates = List.from(coordinates);
    if (closedCoordinates.first != closedCoordinates.last) {
      closedCoordinates.add(closedCoordinates.first);
    }

    for (int i = 0; i < closedCoordinates.length - 1; i++) {
      final p1 = closedCoordinates[i];
      final p2 = closedCoordinates[i + 1];
      perimeter += _distanceBetweenPoints(p1, p2);
    }

    return perimeter / 1000.0; // Convert meters to km
  }

  /// Calculate distance between two points in meters using Haversine formula
  static double _distanceBetweenPoints(LatLng point1, LatLng point2) {
    double lat1Rad = _toRadians(point1.latitude);
    double lat2Rad = _toRadians(point2.latitude);
    double dLatRad = _toRadians(point2.latitude - point1.latitude);
    double dLonRad = _toRadians(point2.longitude - point1.longitude);

    double a = math.sin(dLatRad / 2) * math.sin(dLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLonRad / 2) *
            math.sin(dLonRad / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Check if coordinates form a valid polygon (minimum 3 points, preferably 4+)
  static bool isValidPolygon(List<LatLng> coordinates) {
    return coordinates.length >= 3;
  }

  /// Get centroid of polygon (center point)
  static LatLng getPolygonCentroid(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      return const LatLng(0, 0);
    }

    double sumLat = 0.0;
    double sumLng = 0.0;

    for (final coord in coordinates) {
      sumLat += coord.latitude;
      sumLng += coord.longitude;
    }

    return LatLng(
      sumLat / coordinates.length,
      sumLng / coordinates.length,
    );
  }
}

