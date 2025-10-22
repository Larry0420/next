// kmb.dart
// Implementation based on kmb.md spec and kmb_dictionary.md

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Kmb {
  final Map<String, String> dictionary;

  Kmb(this.dictionary);

  /// Looks up a value in the KMB dictionary.
  String? lookup(String key) {
    return dictionary[key];
  }

  /// Add or update a key-value pair in the dictionary.
  void set(String key, String value) {
    dictionary[key] = value;
  }

  /// Removes a key from the dictionary.
  void remove(String key) {
    dictionary.remove(key);
  }

  /// Returns all keys in the dictionary.
  List<String> keys() {
    return dictionary.keys.toList();
  }

  /// Returns all values in the dictionary.
  List<String> values() {
    return dictionary.values.toList();
  }

  /// Fetches KMB routes from API
  static Future<List<String>> fetchRoutes() async {
    final url = Uri.parse('https://data.etabus.gov.hk/v1/transport/kmb/route/');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final routes = (data['data'] as List)
          .map<String>((route) => route['route'] as String)
          .toList();
      return routes;
    } else {
      throw Exception('Failed to load KMB routes');
    }
  }

  /// Fetch status/info for a specific route. Returns the raw JSON map or throws on error.
  static Future<Map<String, dynamic>> fetchRouteStatus(String route) async {
  // Normalize route (trim and uppercase)
    final candidateRoutes = <String>[];
    final r = route.trim().toUpperCase();
    candidateRoutes.add(r);

    // If route ends with non-digit (like letter variant), also try without letter
    final baseMatch = RegExp(r'^(\d+)').firstMatch(r);
    if (baseMatch != null) {
      final base = baseMatch.group(1)!;
      if (base != r) candidateRoutes.add(base);
    }

    // If we have a prebuilt route->stops cache, return from there first
    if (_routeStopsCache != null && _routeStopsCache!.isNotEmpty) {
      final found = _routeStopsCache![r] ?? _routeStopsCache![baseMatch?.group(1) ?? ''];
      if (found != null && found.isNotEmpty) {
        return {
          'type': 'RouteStopList',
          'version': 'prebuilt',
          'generatedtimestamp': DateTime.now().toIso8601String(),
          'data': found,
        };
      }
    }

    // Try each candidate against the canonical route-stop public API
    for (final cand in candidateRoutes) {
      final urlStr = 'https://data.etabus.gov.hk/v1/transport/kmb/route/route-stop/${Uri.encodeComponent(cand)}';
      try {
        final url = Uri.parse(urlStr);
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload != null && ((payload is List && payload.isNotEmpty) || (payload is Map && payload.isNotEmpty))) {
            return data;
          }
        }
      } catch (_) {
        // ignore and try next candidate
      }
    }

    throw Exception('Failed to load route status for $route');
  }

  // In-memory cache for prebuilt route->stops mapping and timestamp
  static Map<String, List<Map<String, dynamic>>>? _routeStopsCache;
  static DateTime? _routeStopsCacheAt;
  static const String _routeStopsCachePrefKey = 'kmb_route_stops_cache_json';
  static const String _routeStopsCacheAtPrefKey = 'kmb_route_stops_cache_at';

  /// Fetch the full route-stop list (all routes) from public endpoints.
  /// Returns an array of route-stop objects as maps.
  static Future<List<Map<String, dynamic>>> fetchRouteStopsAll() async {
    final urlCandidates = [
      'https://data.etabus.gov.hk/v1/transport/kmb/route/route-stop',
      'https://data.etabus.gov.hk/v1/transport/kmb/route-stop',
      'https://data.etabus.gov.hk/v1/transport/kmb/route/route-stop/',
    ];

    for (final u in urlCandidates) {
      try {
        final resp = await http.get(Uri.parse(u));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload is List) {
            return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {}
    }
    throw Exception('Failed to fetch route-stop list');
  }

  /// Fetch the full stop list (all bus stops) from the public endpoints.
  static Future<List<Map<String, dynamic>>> fetchStopsAll() async {
    final urlCandidates = [
      'https://data.etabus.gov.hk/v1/transport/kmb/stop',
      'https://data.etabus.gov.hk/v1/transport/kmb/stop/',
    ];
    for (final u in urlCandidates) {
      try {
        final resp = await http.get(Uri.parse(u));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload is List) {
            return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {}
    }
    throw Exception('Failed to fetch stop list');
  }

  // In-memory cache for stops and timestamp
  static Map<String, Map<String, dynamic>>? _stopsCache;
  static DateTime? _stopsCacheAt;

  static const String _stopsCachePrefKey = 'kmb_stops_cache_json';

  /// Build and cache a map of stopId -> stopInfo for quick lookup.
  /// TTL default 24 hours.
  static Future<Map<String, Map<String, dynamic>>> buildStopMap({Duration ttl = const Duration(hours: 24)}) async {
    if (_stopsCache != null && _stopsCacheAt != null) {
      if (DateTime.now().difference(_stopsCacheAt!) < ttl) return _stopsCache!;
    }

    try {
      final stops = await fetchStopsAll();
      final Map<String, Map<String, dynamic>> map = {};
      for (final s in stops) {
        final id = s['stop']?.toString() ?? '';
        if (id.isEmpty) continue;
        map[id] = Map<String, dynamic>.from(s);
      }

      _stopsCache = map;
      _stopsCacheAt = DateTime.now();

      // persist to shared_prefs for fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_stopsCachePrefKey, json.encode(map));
      } catch (_) {}

      return map;
    } catch (e) {
      // attempt to read from persisted snapshot
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_stopsCachePrefKey);
        if (raw != null) {
          final decoded = json.decode(raw) as Map<String, dynamic>;
          final Map<String, Map<String, dynamic>> map = {};
          decoded.forEach((k, v) {
            map[k] = Map<String, dynamic>.from(v as Map);
          });
          _stopsCache = map;
          _stopsCacheAt = DateTime.now();
          return map;
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Force refresh the persisted stops cache by fetching /stop again.
  static Future<void> refreshStopsCache() async {
    _stopsCache = null;
    await buildStopMap(ttl: Duration.zero);
  }

  /// Get stop info by id. Uses cache if available or builds it.
  static Future<Map<String, dynamic>?> getStopById(String stopId) async {
    final map = await buildStopMap();
    return map[stopId];
  }

  /// Fetch ETA entries for a particular stop id.
  /// Returns a list of ETA objects or throws on failure.
  static Future<List<Map<String, dynamic>>> fetchStopEta(String stopId) async {
    final s = stopId.trim();
    final urlCandidates = [
      'https://data.etabus.gov.hk/v1/transport/kmb/stop-eta/${Uri.encodeComponent(s)}',
      'https://data.etabus.gov.hk/v1/transport/kmb/stop/${Uri.encodeComponent(s)}/eta',
      'https://data.etabus.gov.hk/v1/transport/kmb/stop-eta/${Uri.encodeComponent(s)}/',
    ];

    for (final u in urlCandidates) {
      try {
        final resp = await http.get(Uri.parse(u));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload is List) {
            return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
          }
        }
      } catch (_) {
        // ignore and try next
      }
    }
    throw Exception('Failed to fetch ETA for stop $stopId');
  }

  /// Fetch ETA entries for a specific (stop, route, service) combination.
  /// Endpoint: /v1/transport/kmb/eta/{stop_id}/{route}/{service_type}
  static Future<List<Map<String, dynamic>>> fetchStopRouteEta(String stopId, String route, String serviceType) async {
    final s = stopId.trim();
    final r = route.trim();
    final svc = serviceType.trim();
    final url = Uri.parse('https://data.etabus.gov.hk/v1/transport/kmb/eta/${Uri.encodeComponent(s)}/${Uri.encodeComponent(r)}/${Uri.encodeComponent(svc)}');
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final payload = data['data'];
      if (payload is List) return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
    }
    throw Exception('Failed to fetch ETA for stop $stopId route $route service $serviceType');
  }

  /// Fetch ETA entries for an entire route across stops for a given service type.
  /// Endpoint: /v1/transport/kmb/route-eta/{route}/{service_type}
  static Future<List<Map<String, dynamic>>> fetchRouteEta(String route, String serviceType) async {
    final r = route.trim();
    final svc = serviceType.trim();
    final url = Uri.parse('https://data.etabus.gov.hk/v1/transport/kmb/route-eta/${Uri.encodeComponent(r)}/${Uri.encodeComponent(svc)}');
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final payload = data['data'];
      if (payload is List) return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
    }
    throw Exception('Failed to fetch route ETA for $route service $serviceType');
  }

  // Preference key for using per-route API for route stops
  static const String _useRouteApiKey = 'useRouteApiForRouteStops';

  /// Read the persisted 'use per-route API' setting.
  static Future<bool> getUseRouteApiSetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useRouteApiKey) ?? false;
  }

  /// Persist the 'use per-route API' setting.
  static Future<void> setUseRouteApiSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useRouteApiKey, value);
  }

  /// Build and cache a map of route -> ordered list of route-stop entries.
  /// TTL is optional; default 24 hours.
  static Future<Map<String, List<Map<String, dynamic>>>> buildRouteToStopsMap({Duration ttl = const Duration(hours: 24)}) async {
    if (_routeStopsCache != null && _routeStopsCacheAt != null) {
      if (DateTime.now().difference(_routeStopsCacheAt!) < ttl) {
        return _routeStopsCache!;
      }
    }

    final routeStops = await fetchRouteStopsAll();
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (final entry in routeStops) {
      final route = (entry['route'] ?? '').toString().toUpperCase();
      map.putIfAbsent(route, () => []).add(Map<String, dynamic>.from(entry));
    }

    // Also add entries grouped by numeric base (so 11A and 11 map under 11)
    final Map<String, List<Map<String, dynamic>>> extended = Map.from(map);
    final baseRe = RegExp(r'^(\d+)');
    for (final key in map.keys) {
      final m = baseRe.firstMatch(key);
      if (m != null) {
        final base = m.group(1)!;
        extended.putIfAbsent(base, () => []).addAll(map[key]!);
      }
    }

    // Sort each list by seq
    for (final k in extended.keys) {
      extended[k]!.sort((a, b) {
        final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
        final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });
    }

    _routeStopsCache = extended;
    _routeStopsCacheAt = DateTime.now();
    // persist to shared_prefs for fallback and next-run checks
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_routeStopsCachePrefKey, json.encode(extended));
      await prefs.setString(_routeStopsCacheAtPrefKey, _routeStopsCacheAt!.toIso8601String());
    } catch (_) {}
    return extended;
  }

  /// Ensure the route-stop cache is refreshed once per day after 05:00.
  /// Returns true if a refresh was performed now.
  static Future<bool> ensureRouteStopsFresh() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_routeStopsCacheAtPrefKey);
    DateTime? last;
    if (lastStr != null) {
      try { last = DateTime.parse(lastStr); } catch (_) { last = null; }
    }

    // Only attempt refresh after today's 05:00
    final todayFive = DateTime(now.year, now.month, now.day, 5);
    if (now.isBefore(todayFive)) return false;

    // If we have no last or last is before today's 05:00, refresh
    if (last == null || last.isBefore(todayFive)) {
      // force rebuild and persist
      await buildRouteToStopsMap(ttl: Duration.zero);
      return true;
    }
    return false;
  }

  /// Fetch route data for a specific route + direction + service type.
  /// Endpoint: /v1/transport/kmb/route/{route}/{direction}/{service_type}
  static Future<Map<String, dynamic>> fetchRouteWithParams(String route, String direction, String serviceType) async {
    final r = route.trim().toUpperCase();
    final dir = direction.trim().toUpperCase();
    final svc = serviceType.trim();
    final url = Uri.parse('https://data.etabus.gov.hk/v1/transport/kmb/route/${Uri.encodeComponent(r)}/${Uri.encodeComponent(dir)}/${Uri.encodeComponent(svc)}');
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data;
    }
    throw Exception('Failed to fetch route data for $route/$direction/$serviceType');
  }

  /// Inspect cached route-stop or route data to discover available directions (I/O) and service types for a route.
  /// Returns a map with keys 'directions' and 'serviceTypes' containing lists of strings.
  static Map<String, List<String>> discoverRouteVariants(String route) {
    final r = route.trim().toUpperCase();
    final results = <String, Set<String>>{
      'directions': <String>{},
      'serviceTypes': <String>{},
    };

    if (_routeStopsCache != null) {
      final entries = _routeStopsCache![r] ?? [];
      for (final e in entries) {
        if (e.containsKey('bound')) results['directions']!.add(e['bound'].toString());
        if (e.containsKey('servicetype')) results['serviceTypes']!.add(e['servicetype'].toString());
      }
    }

    // If empty, try to infer from normalized keys (e.g., base variants)
    if (results['directions']!.isEmpty && results['serviceTypes']!.isEmpty && _routeStopsCache != null) {
      final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
      final entries = _routeStopsCache![base] ?? [];
      for (final e in entries) {
        if (e.containsKey('bound')) results['directions']!.add(e['bound'].toString());
        if (e.containsKey('servicetype')) results['serviceTypes']!.add(e['servicetype'].toString());
      }
    }

    return {
      'directions': results['directions']!.toList(),
      'serviceTypes': results['serviceTypes']!.toList(),
    };
  }
}

// Example dictionary initialization (replace with actual data from kmb_dictionary.md)
final Map<String, String> kmbDictionary = {
  // 'key1': 'value1',
  // 'key2': 'value2',
};

final Kmb kmb = Kmb(kmbDictionary);
