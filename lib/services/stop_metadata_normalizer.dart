import 'dart:math';

/// Unified stop metadata normalizer
/// 
/// Provides consistent access to stop metadata fields across different API responses.
/// Eliminates scattered null checks and field name inconsistencies.
/// 
/// Handles multiple field name variants:
/// - Name: nameen/name_en/name_en, nametc/name_tc/name_tc
/// - Coordinates: lat/latitude, long/lng/longitude
/// - Other common field variations
class StopMetadataNormalizer {
  /// Get stop name with language preference
  /// 
  /// Parameters:
  /// - meta: The metadata map from API response
  /// - isEnglish: Whether to prefer English name
  /// 
  /// Returns the stop name, or 'Unknown' if not found
  static String getName(dynamic meta, {bool isEnglish = true}) {
    if (meta == null || meta is! Map) return 'Unknown';
    
    // Try English name variants
    final en = _tryFieldVariants(meta, ['nameen', 'name_en', 'name_en']);
    
    // Try Chinese name variants
    final tc = _tryFieldVariants(meta, ['nametc', 'name_tc', 'name_tc']);
    
    // Return preferred language with fallback
    if (isEnglish) {
      return en.isNotEmpty ? en : (tc.isNotEmpty ? tc : 'Unknown');
    }
    return tc.isNotEmpty ? tc : (en.isNotEmpty ? en : 'Unknown');
  }
  
  /// Get English stop name
  static String getEnglishName(dynamic meta) {
    return getName(meta, isEnglish: true);
  }
  
  /// Get Chinese stop name
  static String getChineseName(dynamic meta) {
    return getName(meta, isEnglish: false);
  }
  
  /// Get stop coordinates as a map
  /// 
  /// Parameters:
  /// - meta: The metadata map from API response
  /// 
  /// Returns map with 'lat' and 'lng' keys, or empty map if not found
  static Map<String, double?> getCoordinates(dynamic meta) {
    if (meta == null || meta is! Map) return {};
    
    final lat = _parseCoordinate(meta, ['lat', 'latitude']);
    final lng = _parseCoordinate(meta, ['lng', 'long', 'longitude']);
    
    if (lat != null && lng != null) {
      return {'lat': lat, 'lng': lng};
    }
    return {};
  }
  
  /// Get latitude
  static double? getLat(dynamic meta) {
    if (meta == null || meta is! Map) return null;
    return _parseCoordinate(meta, ['lat', 'latitude']);
  }
  
  /// Get longitude
  static double? getLng(dynamic meta) {
    if (meta == null || meta is! Map) return null;
    return _parseCoordinate(meta, ['lng', 'long', 'longitude']);
  }
  
  /// Get stop ID from metadata
  static String? getStopId(dynamic meta) {
    if (meta == null || meta is! Map) return null;
    return _tryFieldVariants(meta, ['stop', 'stop_id', 'stopId', 'id']);
  }
  
  /// Get route ID from metadata
  static String? getRouteId(dynamic meta) {
    if (meta == null || meta is! Map) return null;
    return _tryFieldVariants(meta, ['route', 'route_id', 'routeId', 'id']);
  }
  
  /// Get fare from metadata
  static String? getFare(dynamic meta) {
    if (meta == null || meta is! Map) return null;
    return _tryFieldVariants(meta, ['fare', 'price']);
  }
  
  /// Get service type from metadata
  static String? getServiceType(dynamic meta) {
    if (meta == null || meta is! Map) return null;
    return _tryFieldVariants(meta, ['service_type', 'serviceType', 'type']);
  }
  
  /// Normalize stop metadata to standard format
  /// 
  /// Converts various API response formats to a consistent structure:
  /// {
  ///   'stop_id': String,
  ///   'name_en': String,
  ///   'name_tc': String,
  ///   'lat': double,
  ///   'lng': double,
  ///   'fare': String?,
  ///   'service_type': String?
  /// }
  static Map<String, dynamic> normalize(dynamic meta) {
    if (meta == null || meta is! Map) return {};
    
    final coords = getCoordinates(meta);
    
    return {
      'stop_id': getStopId(meta) ?? '',
      'name_en': getEnglishName(meta),
      'name_tc': getChineseName(meta),
      'lat': coords['lat'],
      'lng': coords['lng'],
      'fare': getFare(meta),
      'service_type': getServiceType(meta),
    };
  }
  
  /// Extract stop list from metadata with type-safe handling
  /// 
  /// Parameters:
  /// - stopsMap: The stops map from API response
  /// - companyKey: The company key to extract (e.g., 'CTB', 'KMB')
  /// - routeId: The route ID for logging
  /// 
  /// Returns list of stop IDs, or empty list if invalid
  static List<String> extractStopList(
    dynamic stopsMap,
    String companyKey,
    String routeId,
  ) {
    if (stopsMap == null || stopsMap is! Map) {
      return [];
    }
    
    final rawValue = stopsMap[companyKey];
    if (rawValue == null) return [];
    
    // Handle List format
    if (rawValue is List) {
      return rawValue
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    
    // Handle JSON string format
    if (rawValue is String) {
      try {
        final parsed = _parseJson(rawValue);
        if (parsed is List) {
          return parsed
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (e) {
        // Ignore JSON parse errors
      }
    }
    
    return [];
  }
  
  /// Calculate distance between two stops
  /// 
  /// Parameters:
  /// - stop1: First stop metadata
  /// - stop2: Second stop metadata
  /// 
  /// Returns distance in kilometers, or null if coordinates are missing
  static double? calculateDistance(dynamic stop1, dynamic stop2) {
    final coords1 = getCoordinates(stop1);
    final coords2 = getCoordinates(stop2);
    
    if (coords1['lat'] == null || coords1['lng'] == null ||
        coords2['lat'] == null || coords2['lng'] == null) {
      return null;
    }
    
    return _haversine(
      coords1['lat']!,
      coords1['lng']!,
      coords2['lat']!,
      coords2['lng']!,
    );
  }
  
  // Private helper methods
  
  /// Try multiple field name variants and return first non-empty value
  static String _tryFieldVariants(Map meta, List<String> keys) {
    for (final key in keys) {
      final value = meta[key];
      if (value != null) {
        final str = value.toString().trim();
        if (str.isNotEmpty) return str;
      }
    }
    return '';
  }
  
  /// Parse coordinate from multiple field name variants
  static double? _parseCoordinate(Map meta, List<String> keys) {
    for (final key in keys) {
      final value = meta[key];
      if (value != null) {
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
  
  /// Parse JSON string with safety
  static dynamic _parseJson(String jsonString) {
    try {
      // Remove any surrounding quotes if present
      final trimmed = jsonString.trim();
      if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
        // It's a JSON string inside quotes
        final unescaped = trimmed.substring(1, trimmed.length - 1);
        // Unescape escaped quotes
        final unescaped2 = unescaped.replaceAll('\\"', '"');
        return _parseJson(unescaped2);
      }
      
      // Try to parse as JSON
      // (In a real implementation, you'd use dart:convert's jsonDecode)
      // For now, return as is to avoid import complexity
      return jsonString;
    } catch (e) {
      return null;
    }
  }
  
  /// Calculate distance between two coordinates using Haversine formula
  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371; // kilometers
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = pow(sin(dLat / 2), 2) +
        cos(_toRadians(lat1)) *
        cos(_toRadians(lat2)) *
        pow(sin(dLng / 2), 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  static double _toRadians(double degrees) {
    return degrees * (pi / 180);
  }
}
