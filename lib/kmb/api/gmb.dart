// gmb.dart
// Implementation based on GMB ETA API Specification v1.1
// Base URL: https://data.etagmb.gov.hk

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Green Minibus (GMB) API Client
/// 
/// Supports real-time arrival information for Hong Kong Green Minibus routes.
/// API Version: 1.1
/// Documentation: https://data.etagmb.gov.hk/static/GMB_ETA_API_Specification.pdf
class GMB {
  static const String _baseUrl = 'https://data.etagmb.gov.hk';

  // Cache keys
  static const String _routesCachePrefKey = 'gmb_routes_cache_json';
  static const String _routesCacheAtPrefKey = 'gmb_routes_cache_at';
  static const String _stopsCachePrefKey = 'gmb_stops_cache_json';
  static const String _stopsCacheAtPrefKey = 'gmb_stops_cache_at';
  static const String _routeStopsCachePrefKey = 'gmb_route_stops_cache_json';
  static const String _routeStopsCacheAtPrefKey = 'gmb_route_stops_cache_at';
  static const String _pinnedRoutesKey = 'pinnedGmbRoutes';
  static const String _pinnedStopsKey = 'pinnedGmbStops';
  static const String _routeHistoryKey = 'gmbRouteHistory';

  // Default TTL values
  static const Duration _defaultRoutesTtl = Duration(hours: 24);
  static const Duration _defaultStopsTtl = Duration(hours: 24);
  static const Duration _defaultRouteStopsTtl = Duration(hours: 24);

  // In-memory caches
  static Map<String, List<String>>? _routesCache; // region -> route codes
  static DateTime? _routesCacheAt;
  static Map<String, Map<String, dynamic>>? _stopsCache; // stop_id -> stop info
  static DateTime? _stopsCacheAt;
  static Map<String, List<Map<String, dynamic>>>? _routeStopsCache; // route_id -> stops
  static DateTime? _routeStopsCacheAt;

  // ============================================
  // Helper Methods
  // ============================================

  static Uri _u(String path) => Uri.parse('$_baseUrl$path');

  static Future<Map<String, dynamic>> _getJson(Uri url, {Duration timeout = const Duration(seconds: 20)}) async {
    final resp = await http.get(url).timeout(timeout);
    if (resp.statusCode != 200) {
      final snippet = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
      throw Exception('HTTP ${resp.statusCode}: $snippet');
    }
    try {
      final decoded = json.decode(resp.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw Exception('Unexpected JSON root type: ${decoded.runtimeType}');
    } on FormatException {
      throw Exception('Invalid JSON from $url');
    }
  }

  // ============================================
  // Route Listing API
  // ============================================

  /// Fetch all GMB routes grouped by region.
  /// Endpoint: GET /route
  /// 
  /// Returns a map where keys are regions (HKI, KLN, NT) and values are lists of route codes.
  static Future<Map<String, List<String>>> fetchAllRoutes({
    Duration ttl = _defaultRoutesTtl,
  }) async {
    // Check in-memory cache
    if (_routesCache != null && _routesCacheAt != null) {
      if (DateTime.now().difference(_routesCacheAt!) < ttl) return _routesCache!;
    }

    // Try SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_routesCachePrefKey);
      final cachedAtStr = prefs.getString(_routesCacheAtPrefKey);
      
      if (cachedJson != null && cachedAtStr != null) {
        final cachedAt = DateTime.parse(cachedAtStr);
        if (DateTime.now().difference(cachedAt) < ttl) {
          final decoded = json.decode(cachedJson) as Map<String, dynamic>;
          final result = decoded.map((k, v) => MapEntry(
            k.toString(),
            List<String>.from(v as List),
          ));
          _routesCache = result;
          _routesCacheAt = cachedAt;
          return result;
        }
      }
    } catch (_) {}

    // Fetch from API
    final url = _u('/route');
    final obj = await _getJson(url);
    final data = obj['data'] as Map<String, dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    final routes = data['routes'] as Map<String, dynamic>?;
    if (routes == null) throw Exception('Invalid response: missing routes');

    final result = routes.map((k, v) => MapEntry(
      k.toString(),
      List<String>.from(v as List),
    ));

    // Update cache
    _routesCache = result;
    _routesCacheAt = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_routesCachePrefKey, json.encode(result));
      await prefs.setString(_routesCacheAtPrefKey, _routesCacheAt!.toIso8601String());
    } catch (_) {}

    return result;
  }

  /// Fetch routes for a specific region.
  /// Endpoint: GET /route/{region}
  /// 
  /// Regions: HKI (Hong Kong Island), KLN (Kowloon), NT (New Territories)
  static Future<List<String>> fetchRoutesByRegion(String region, {
    Duration ttl = _defaultRoutesTtl,
  }) async {
    final normalizedRegion = region.toUpperCase().trim();
    if (!['HKI', 'KLN', 'NT'].contains(normalizedRegion)) {
      throw ArgumentError('Invalid region: $region. Must be HKI, KLN, or NT');
    }

    // Try to get from all routes cache first
    final allRoutes = await fetchAllRoutes(ttl: ttl);
    if (allRoutes.containsKey(normalizedRegion)) {
      return allRoutes[normalizedRegion]!;
    }

    // Fetch specific region from API
    final url = _u('/route/$normalizedRegion');
    final obj = await _getJson(url);
    final data = obj['data'] as Map<String, dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null) throw Exception('Invalid response: missing routes');

    return List<String>.from(routes);
  }

  // ============================================
  // Route API
  // ============================================

  /// Fetch route information by region and route code.
  /// Endpoint: GET /route/{region}/{route_code}
  ///
  /// Returns a list of route variations (different service types/directions).
  static Future<List<Map<String, dynamic>>> fetchRouteInfo(
    String region,
    String routeCode,
  ) async {
    final normalizedRegion = region.toUpperCase().trim();
    final normalizedRouteCode = routeCode.trim();
    
    final url = _u('/route/$normalizedRegion/${Uri.encodeComponent(normalizedRouteCode)}');
    final obj = await _getJson(url);
    final data = obj['data'] as List<dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch route information by route ID.
  /// Endpoint: GET /route/{route_id}
  static Future<List<Map<String, dynamic>>> fetchRouteInfoById(int routeId) async {
    final url = _u('/route/$routeId');
    final obj = await _getJson(url);
    final data = obj['data'] as List<dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ============================================
  // Stop API
  // ============================================

  /// Fetch stop details by stop ID.
  /// Endpoint: GET /stop/{stop_id}
  ///
  /// Returns stop coordinates and status information.
  static Future<Map<String, dynamic>?> fetchStopInfo(int stopId) async {
    final url = _u('/stop/$stopId');
    try {
      final obj = await _getJson(url);
      final data = obj['data'] as Map<String, dynamic>?;
      return data;
    } catch (e) {
      if (e.toString().contains('404')) return null;
      rethrow;
    }
  }

  /// Build and cache a map of StopId -> Stop Details.
  static Future<Map<String, Map<String, dynamic>>> buildStopMap({
    Duration ttl = _defaultStopsTtl,
  }) async {
    // Check in-memory cache
    if (_stopsCache != null && _stopsCacheAt != null) {
      if (DateTime.now().difference(_stopsCacheAt!) < ttl) return _stopsCache!;
    }

    // Try bundled asset first
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/gmb_stops.json');
      if (raw.isNotEmpty) {
        final map = await compute(_parseStopsMap, raw);
        _stopsCache = map;
        _stopsCacheAt = DateTime.now();
        
        // Persist to SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_stopsCachePrefKey, json.encode(map));
          await prefs.setString(_stopsCacheAtPrefKey, _stopsCacheAt!.toIso8601String());
        } catch (_) {}
        
        return map;
      }
    } catch (_) {}

    // Try app documents prebuilt
    try {
      final doc = await getApplicationDocumentsDirectory();
      final file = File('${doc.path}/prebuilt/gmb_stops.json');
      if (file.existsSync()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final map = await compute(_parseStopsMap, raw);
          _stopsCache = map;
          _stopsCacheAt = DateTime.now();
          
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_stopsCachePrefKey, json.encode(map));
            await prefs.setString(_stopsCacheAtPrefKey, _stopsCacheAt!.toIso8601String());
          } catch (_) {}
          
          return map;
        }
      }
    } catch (_) {}

    // Try SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_stopsCachePrefKey);
      final cachedAtStr = prefs.getString(_stopsCacheAtPrefKey);
      
      if (cachedJson != null && cachedAtStr != null) {
        final cachedAt = DateTime.parse(cachedAtStr);
        if (DateTime.now().difference(cachedAt) < ttl) {
          final map = await compute(_parseStopsMap, cachedJson);
          _stopsCache = map;
          _stopsCacheAt = cachedAt;
          return map;
        }
      }
    } catch (_) {}

    // Return empty map since GMB has no "all stops" endpoint
    return {};
  }

  static Map<String, Map<String, dynamic>> _parseStopsMap(String raw) {
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final Map<String, Map<String, dynamic>> map = {};
    decoded.forEach((k, v) {
      map[k] = Map<String, dynamic>.from(v as Map);
    });
    return map;
  }

  // ============================================
  // Route-Stop API
  // ============================================

  /// Fetch stop list for a specific route and sequence.
  /// Endpoint: GET /route-stop/{route_id}/{route_seq}
  ///
  /// Returns ordered list of stops for the route direction.
  static Future<List<Map<String, dynamic>>> fetchRouteStops(
    int routeId,
    int routeSeq,
  ) async {
    final url = _u('/route-stop/$routeId/$routeSeq');
    final obj = await _getJson(url);
    final data = obj['data'] as Map<String, dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    final routeStops = data['route_stops'] as List<dynamic>?;
    if (routeStops == null) throw Exception('Invalid response: missing route_stops');

    return routeStops.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Build route to stops mapping with caching.
  /// Since GMB requires fetching stops per route individually, this uses prebuilt data.
  static Future<Map<String, List<Map<String, dynamic>>>> buildRouteToStopsMap({
    Duration ttl = _defaultRouteStopsTtl,
  }) async {
    // Check in-memory cache
    if (_routeStopsCache != null && _routeStopsCacheAt != null) {
      if (DateTime.now().difference(_routeStopsCacheAt!) < ttl) return _routeStopsCache!;
    }

    // Try bundled asset first
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/gmb_route_stops.json');
      if (raw.isNotEmpty) {
        final map = await compute(_parseRouteStopsMap, raw);
        _routeStopsCache = map;
        _routeStopsCacheAt = DateTime.now();
        return map;
      }
    } catch (_) {}

    // Try app documents prebuilt
    try {
      final doc = await getApplicationDocumentsDirectory();
      final file = File('${doc.path}/prebuilt/gmb_route_stops.json');
      if (file.existsSync()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final map = await compute(_parseRouteStopsMap, raw);
          _routeStopsCache = map;
          _routeStopsCacheAt = DateTime.now();
          return map;
        }
      }
    } catch (_) {}

    // Return empty map - GMB requires prebuilt data
    return {};
  }

  static Map<String, List<Map<String, dynamic>>> _parseRouteStopsMap(String raw) {
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final Map<String, List<Map<String, dynamic>>> map = {};
    decoded.forEach((k, v) {
      if (v is List) {
        map[k] = v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    });
    return map;
  }

  // ============================================
  // Stop-Route API
  // ============================================

  /// Fetch routes that serve a specific stop.
  /// Endpoint: GET /stop-route/{stop_id}
  static Future<List<Map<String, dynamic>>> fetchStopRoutes(int stopId) async {
    final url = _u('/stop-route/$stopId');
    final obj = await _getJson(url);
    final data = obj['data'] as List<dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ============================================
  // ETA APIs
  // ============================================

  /// Fetch ETA for a specific route-stop combination.
  /// Endpoint: GET /eta/route-stop/{route_id}/{route_seq}/{stop_seq}
  ///
  /// Returns ETA list including arrival times in relative minutes.
  static Future<Map<String, dynamic>> fetchRouteStopEta(
    int routeId,
    int routeSeq,
    int stopSeq,
  ) async {
    final url = _u('/eta/route-stop/$routeId/$routeSeq/$stopSeq');
    final obj = await _getJson(url);
    final data = obj['data'] as Map<String, dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    return data;
  }

  /// Fetch ETA for a specific route and stop ID.
  /// Endpoint: GET /eta/route-stop/{route_id}/{stop_id}
  ///
  /// Returns ETA for all occurrences of the stop along the route.
  static Future<List<Map<String, dynamic>>> fetchRouteStopEtaByStopId(
    int routeId,
    int stopId,
  ) async {
    final url = _u('/eta/route-stop/$routeId/$stopId');
    final obj = await _getJson(url);
    final data = obj['data'] as List<dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch ETA for a specific stop (all routes).
  /// Endpoint: GET /eta/stop/{stop_id}
  ///
  /// Returns ETA for all routes serving this stop.
  static Future<List<Map<String, dynamic>>> fetchStopEta(int stopId) async {
    final url = _u('/eta/stop/$stopId');
    final obj = await _getJson(url);
    final data = obj['data'] as List<dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch ETA for a stop on a specific route.
  /// Convenience method that tries multiple approaches.
  static Future<List<Map<String, dynamic>>> fetchEtaForRouteStop(
    int routeId,
    int stopId, {
    int? routeSeq,
    int? stopSeq,
  }) async {
    // If we have routeSeq and stopSeq, use the direct endpoint
    if (routeSeq != null && stopSeq != null) {
      try {
        final result = await fetchRouteStopEta(routeId, routeSeq, stopSeq);
        if (result['enabled'] == true && result['eta'] is List) {
          return List<Map<String, dynamic>>.from(result['eta']);
        }
        return [];
      } catch (_) {}
    }

    // Fall back to stop_id based endpoint
    try {
      final results = await fetchRouteStopEtaByStopId(routeId, stopId);
      // Flatten ETA lists from all occurrences
      final etas = <Map<String, dynamic>>[];
      for (final result in results) {
        if (result['enabled'] == true && result['eta'] is List) {
          etas.addAll(List<Map<String, dynamic>>.from(result['eta']));
        }
      }
      return etas;
    } catch (_) {}

    return [];
  }

  // ============================================
  // Last Update API
  // ============================================

  /// Fetch last update timestamp for all routes.
  /// Endpoint: GET /last-update/route
  static Future<List<Map<String, dynamic>>> fetchRoutesLastUpdate() async {
    final url = _u('/last-update/route');
    final obj = await _getJson(url);
    final data = obj['data'] as Map<String, dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    final timestamps = data['data_timestamp'] as List<dynamic>?;
    if (timestamps == null) return [];

    return timestamps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch last update timestamp for all stops.
  /// Endpoint: GET /last-update/stop
  static Future<List<Map<String, dynamic>>> fetchStopsLastUpdate() async {
    final url = _u('/last-update/stop');
    final obj = await _getJson(url);
    final data = obj['data'] as Map<String, dynamic>?;
    
    if (data == null) throw Exception('Invalid response: missing data');
    
    final timestamps = data['data_timestamp'] as List<dynamic>?;
    if (timestamps == null) return [];

    return timestamps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ============================================
  // Pinning & History
  // ============================================

  /// Pin a route variant
  static Future<void> pinRoute(
    int routeId,
    int routeSeq,
    String routeCode,
    String region,
    String label,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);

    // Remove duplicate
    pinned.removeWhere((item) => 
      item is Map && 
      item['routeId'] == routeId && 
      item['routeSeq'] == routeSeq
    );

    pinned.add({
      'routeId': routeId,
      'routeSeq': routeSeq,
      'routeCode': routeCode,
      'region': region,
      'label': label,
      'pinnedAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  static Future<List<Map<String, dynamic>>> getPinnedRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> unpinRoute(int routeId, int routeSeq) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);

    pinned.removeWhere((item) => 
      item is Map && 
      item['routeId'] == routeId && 
      item['routeSeq'] == routeSeq
    );

    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  /// Pin a stop
  static Future<void> pinStop({
    required int stopId,
    required String stopName,
    required String routeCode,
    int? routeId,
    int? routeSeq,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);

    pinned.removeWhere((item) => 
      item is Map && 
      item['stopId'] == stopId && 
      item['routeCode'] == routeCode
    );

    pinned.add({
      'stopId': stopId,
      'stopName': stopName,
      'routeCode': routeCode,
      'routeId': routeId,
      'routeSeq': routeSeq,
      'pinnedAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }

  static Future<List<Map<String, dynamic>>> getPinnedStops() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> unpinStop(int stopId, String routeCode) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);

    pinned.removeWhere((item) => 
      item is Map && 
      item['stopId'] == stopId && 
      item['routeCode'] == routeCode
    );

    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }

  /// Add to history
  static Future<void> addToHistory(
    int routeId,
    int routeSeq,
    String routeCode,
    String region,
    String label,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List<dynamic> history = json.decode(historyJson);

    history.removeWhere((item) => 
      item is Map && 
      item['routeId'] == routeId && 
      item['routeSeq'] == routeSeq
    );

    history.insert(0, {
      'routeId': routeId,
      'routeSeq': routeSeq,
      'routeCode': routeCode,
      'region': region,
      'label': label,
      'accessedAt': DateTime.now().toIso8601String(),
    });

    if (history.length > 50) {
      history.removeRange(50, history.length);
    }

    await prefs.setString(_routeHistoryKey, json.encode(history));
  }

  static Future<List<Map<String, dynamic>>> getRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List<dynamic> history = json.decode(historyJson);
    return history.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> clearRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeHistoryKey, '[]');
  }

  // ============================================
  // Cache Management
  // ============================================

  /// Clear all in-memory caches
  static void clearMemoryCache() {
    _routesCache = null;
    _routesCacheAt = null;
    _stopsCache = null;
    _stopsCacheAt = null;
    _routeStopsCache = null;
    _routeStopsCacheAt = null;
  }

  /// Clear all persisted caches
  static Future<void> clearPersistedCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_routesCachePrefKey);
    await prefs.remove(_routesCacheAtPrefKey);
    await prefs.remove(_stopsCachePrefKey);
    await prefs.remove(_stopsCacheAtPrefKey);
    await prefs.remove(_routeStopsCachePrefKey);
    await prefs.remove(_routeStopsCacheAtPrefKey);
  }

  /// Force refresh all caches
  static Future<void> refreshAllCaches() async {
    clearMemoryCache();
    await clearPersistedCache();
    await fetchAllRoutes(ttl: Duration.zero);
  }
}
