// nlb.dart
// Implementation based on NLB Open API Documentation v2.0
// Base URL: https://rt.data.gov.hk/v2/transport/nlb/

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Nlb {
  static const String _baseUrl = 'https://rt.data.gov.hk/v2/transport/nlb';
  
  // Cache keys
  static const String _routeStopsCachePrefKey = 'nlb_route_stops_cache_json';
  static const String _stopsCachePrefKey = 'nlb_stops_cache_json';
  static const String _pinnedRoutesKey = 'pinnedNlbRoutes';
  static const String _pinnedStopsKey = 'pinnedNlbStops';
  static const String _routeHistoryKey = 'nlbRouteHistory';
  
  // In-memory caches
  static Map<String, dynamic>? _routeStopsCache;
  static DateTime? _routeStopsCacheAt;
  static Map<String, Map<String, dynamic>>? _stopsCache;
  static DateTime? _stopsCacheAt;

  /// Fetch all routes from the API.
  /// Endpoint: route.php?action=list
  static Future<List<Map<String, dynamic>>> fetchRoutes() async {
    final url = Uri.parse('$_baseUrl/route.php?action=list');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        return List<Map<String, dynamic>>.from(routes.map((e) => Map<String, dynamic>.from(e)));
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to load NLB routes');
      }
    } catch (e) {
      throw Exception('Failed to fetch NLB routes: $e');
    }
  }

  /// Build and cache a map of RouteNo -> RouteId -> Variant Data.
  /// Structure: { "37": { "37": { "orig_en":..., "stops": [...] } } }
  /// Uses prebuilt assets first, then falls back to API.
  static Future<Map<String, dynamic>> buildRouteToStopsMap({Duration ttl = const Duration(hours: 24)}) async {
    // Check in-memory cache
    if (_routeStopsCache != null && _routeStopsCacheAt != null) {
      if (DateTime.now().difference(_routeStopsCacheAt!) < ttl) {
        return _routeStopsCache!;
      }
    }

    // 1. Try App Documents (Prebuilt/Updated)
    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/nlb_route_stops.json');
      if (prebuiltFile.existsSync()) {
        final raw = await prebuiltFile.readAsString();
        if (raw.isNotEmpty) {
          final map = await compute(json.decode, raw) as Map<String, dynamic>;
          _routeStopsCache = map;
          _routeStopsCacheAt = DateTime.now();
          return map;
        }
      }
    } catch (_) {}

    // 2. Try Bundled Asset
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/nlb_route_stops.json');
      if (raw.isNotEmpty) {
        final map = await compute(json.decode, raw) as Map<String, dynamic>;
        _routeStopsCache = map;
        _routeStopsCacheAt = DateTime.now();
        return map;
      }
    } catch (_) {}

    // 3. Fallback: Fetch fresh from API (Expensive operation!)
    // Note: NLB API requires fetching stops per routeId individually.
    // Ideally, we rely on prebuilt assets, but here is a basic implementation.
    try {
      final routes = await fetchRoutes();
      final Map<String, dynamic> fullMap = {};
      
      // Group by RouteNo
      for (final r in routes) {
        final routeNo = r['routeNo'].toString();
        final routeId = r['routeId'].toString();
        
        // Parse names
        final nameE = r['routeName_e'].toString();
        final partsE = nameE.split('>');
        final origEn = partsE.isNotEmpty ? partsE[0].trim() : nameE;
        final destEn = partsE.length > 1 ? partsE[1].trim() : '';

        // Fetch stops for this variant
        final stopsUrl = Uri.parse('$_baseUrl/stop.php?action=list&routeId=$routeId');
        final stopResp = await http.get(stopsUrl);
        if (stopResp.statusCode == 200) {
          final stopData = json.decode(stopResp.body);
          final stopList = stopData['stops'] as List;
          
          final variantData = {
            'orig_en': origEn,
            'dest_en': destEn,
            'service_type': r['specialRoute'].toString() == '1' ? 'Special' : 'Normal',
            'stops': stopList.map((s) => {
              'seq': (stopList.indexOf(s) + 1).toString(), // NLB stops are ordered by sequence
              'stop': s['stopId'].toString(),
              'fare': s['fare'],
              'fareHoliday': s['fareHoliday']
            }).toList()
          };
          
          fullMap.putIfAbsent(routeNo, () => {});
          fullMap[routeNo][routeId] = variantData;
        }
      }
      
      _routeStopsCache = fullMap;
      _routeStopsCacheAt = DateTime.now();
      
      // Persist
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_routeStopsCachePrefKey, json.encode(fullMap));
      
      return fullMap;
    } catch (e) {
      // Try loading from SharedPreferences if network failed
       try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_routeStopsCachePrefKey);
        if (raw != null) {
          final map = json.decode(raw) as Map<String, dynamic>;
          _routeStopsCache = map;
          return map;
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Build and cache a map of StopId -> Stop Details.
  static Future<Map<String, Map<String, dynamic>>> buildStopMap({Duration ttl = const Duration(hours: 24)}) async {
    if (_stopsCache != null && _stopsCacheAt != null) {
      if (DateTime.now().difference(_stopsCacheAt!) < ttl) {
        return _stopsCache!;
      }
    }

    // 1. Try App Documents
    try {
      final doc = await getApplicationDocumentsDirectory();
      final file = File('${doc.path}/prebuilt/nlb_stops.json');
      if (file.existsSync()) {
        final raw = await file.readAsString();
        final map = await compute(_parseStopsMap, raw);
        _stopsCache = map;
        _stopsCacheAt = DateTime.now();
        return map;
      }
    } catch (_) {}

    // 2. Try Bundled Asset
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/nlb_stops.json');
      final map = await compute(_parseStopsMap, raw);
      _stopsCache = map;
      _stopsCacheAt = DateTime.now();
      return map;
    } catch (_) {}

    // 3. Fallback: Since NLB has no "All Stops" endpoint, we can't easily build this
    // from scratch without iterating all routes. Return empty or cached if available.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stopsCachePrefKey);
      if (raw != null) {
        final map = await compute(_parseStopsMap, raw);
        _stopsCache = map;
        return map;
      }
    } catch (_) {}
    
    return {};
  }
  
  /// Helper to parse stops JSON string to strongly typed map
  static Map<String, Map<String, dynamic>> _parseStopsMap(String raw) {
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final Map<String, Map<String, dynamic>> map = {};
    decoded.forEach((k, v) {
      map[k] = Map<String, dynamic>.from(v as Map);
    });
    return map;
  }

  /// Fetch Estimated Arrivals for a specific stop on a specific route.
  /// Endpoint: stop.php?action=estimatedArrivals&routeId={routeId}&stopId={stopId}&language={language}
  static Future<List<Map<String, dynamic>>> fetchEstimatedArrivals({
    required String routeId,
    required String stopId,
    String language = 'en', // 'en', 'zh', 'cn'
  }) async {
    final url = Uri.parse(
      '$_baseUrl/stop.php?action=estimatedArrivals&routeId=$routeId&stopId=$stopId&language=$language'
    );
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final arrivals = data['estimatedArrivals'] as List?;
        if (arrivals == null) return [];
        
        return List<Map<String, dynamic>>.from(arrivals.map((e) => Map<String, dynamic>.from(e)));
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch ETAs: $e');
    }
  }

  /// Discover variants (RouteIds) for a given Route Number.
  /// Returns a list of variant objects with metadata.
  static Future<List<Map<String, dynamic>>> getVariantsForRoute(String routeNo) async {
    final map = await buildRouteToStopsMap();
    if (map.containsKey(routeNo)) {
      final variantsMap = map[routeNo] as Map<String, dynamic>;
      final List<Map<String, dynamic>> variants = [];
      
      variantsMap.forEach((routeId, data) {
        variants.add({
          'routeId': routeId,
          ...data as Map<String, dynamic>
        });
      });
      return variants;
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Pinning & History (Similar to KMB implementation)
  // ---------------------------------------------------------------------------

  /// Pin a route variant
  static Future<void> pinRoute(String routeNo, String routeId, String label) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    
    // Remove duplicate
    pinned.removeWhere((item) => item['routeId'] == routeId);
    
    pinned.add({
      'routeNo': routeNo,
      'routeId': routeId,
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
  
  static Future<void> unpinRoute(String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    
    pinned.removeWhere((item) => item['routeId'] == routeId);
    
    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  /// Add to History
  static Future<void> addToHistory(String routeNo, String routeId, String label) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List<dynamic> history = json.decode(historyJson);
    
    history.removeWhere((item) => item['routeId'] == routeId);
    
    history.insert(0, {
      'routeNo': routeNo,
      'routeId': routeId,
      'label': label,
      'accessedAt': DateTime.now().toIso8601String(),
    });
    
    if (history.length > 50) history.removeRange(50, history.length);
    
    await prefs.setString(_routeHistoryKey, json.encode(history));
  }

  static Future<List<Map<String, dynamic>>> getRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List<dynamic> history = json.decode(historyJson);
    return history.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}