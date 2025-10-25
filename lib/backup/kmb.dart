// kmb.dart
// Implementation based on kmb.md spec and kmb_dictionary.md

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show compute;
import 'dart:io';
import 'package:path_provider/path_provider.dart';


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
    String? lastError;
    for (final u in urlCandidates) {
      try {
        final resp = await http.get(Uri.parse(u));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload is List) {
            return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
          } else {
            lastError = 'Unexpected payload type at $u: ${payload.runtimeType}';
          }
        } else {
          final snippet = resp.body.length > 200 ? resp.body.substring(0, 200) + '...' : resp.body;
          lastError = 'HTTP ${resp.statusCode} from $u: $snippet';
        }
      } catch (e) {
        lastError = 'Error fetching $u: ${e.toString()}';
      }
    }
    throw Exception('Failed to fetch route-stop list. Last error: ${lastError ?? 'no response'}');
  }

  /// Fetch the full stop list (all bus stops) from the public endpoints.
  static Future<List<Map<String, dynamic>>> fetchStopsAll() async {
    final urlCandidates = [
      'https://data.etabus.gov.hk/v1/transport/kmb/stop',
      'https://data.etabus.gov.hk/v1/transport/kmb/stop/',
    ];
    String? lastError;
    for (final u in urlCandidates) {
      try {
        final resp = await http.get(Uri.parse(u));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload is List) {
            return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
          } else {
            lastError = 'Unexpected payload type at $u: ${payload.runtimeType}';
          }
        } else {
          final snippet = resp.body.length > 200 ? resp.body.substring(0, 200) + '...' : resp.body;
          lastError = 'HTTP ${resp.statusCode} from $u: $snippet';
        }
      } catch (e) {
        lastError = 'Error fetching $u: ${e.toString()}';
      }
    }
    throw Exception('Failed to fetch stop list. Last error: ${lastError ?? 'no response'}');
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
    // First, try to load a prebuilt stops asset from app documents, then from bundled assets.
    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/kmb_stops.json');
      if (prebuiltFile.existsSync()) {
        final raw = await prebuiltFile.readAsString();
        if (raw.isNotEmpty) {
          final map = await compute(_parseStopsAsset, raw);
          _stopsCache = map;
          _stopsCacheAt = DateTime.now();
          // persist to shared_prefs for fallback
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_stopsCachePrefKey, json.encode(map));
          } catch (_) {}
          return map;
        }
      }
    } catch (_) {}

    // Next, try bundled asset
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/kmb_stops.json');
      if (raw.isNotEmpty) {
        final map = await compute(_parseStopsAsset, raw);
        _stopsCache = map;
        _stopsCacheAt = DateTime.now();
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_stopsCachePrefKey, json.encode(map));
        } catch (_) {}
        return map;
      }
    } catch (_) {}

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

    // Try to load a prebuilt JSON asset from app documents, then bundled assets.
    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/kmb_route_stops.json');
      if (prebuiltFile.existsSync()) {
        final raw = await prebuiltFile.readAsString();
        if (raw.isNotEmpty) {
          final map = await compute(_parseRouteStopsAsset, raw);
          _routeStopsCache = map;
          _routeStopsCacheAt = DateTime.now();
          return _routeStopsCache!;
        }
      }
    } catch (_) {}

    try {
      final raw = await rootBundle.loadString('assets/prebuilt/kmb_route_stops.json');
      if (raw.isNotEmpty) {
        final map = await compute(_parseRouteStopsAsset, raw);
        _routeStopsCache = map;
        _routeStopsCacheAt = DateTime.now();
        return _routeStopsCache!;
      }
    } catch (_) {}

    Map<String, List<Map<String, dynamic>>> map;
    try {
      final routeStops = await fetchRouteStopsAll();
      // build route map in background isolate to avoid blocking UI
      map = await compute(_buildRouteMapFromList, routeStops);
    } catch (e) {
      // If network fetch failed, try to load a persisted cache from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_routeStopsCachePrefKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw) as Map<String, dynamic>;
          final Map<String, List<Map<String, dynamic>>> restored = {};
          decoded.forEach((k, v) {
            try {
              restored[k] = List<Map<String, dynamic>>.from((v as List).map((e) => Map<String, dynamic>.from(e)));
            } catch (_) {}
          });
          map = restored;
        } else {
          rethrow;
        }
      } catch (_) {
        // rethrow original network error so caller can handle it
        rethrow;
      }
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

  /// Validate a saved snapshot that might be restored into the route/status page.
  /// Returns null when valid, otherwise returns an error message describing why
  /// the snapshot is not acceptable.
  static String? validateSavedSnapshot(dynamic obj) {
    if (obj is! Map<String, dynamic>) return 'Snapshot is not a JSON object';

    // Accept common shapes:
    // - { type: '...', data: ... }
    if (obj.containsKey('type') && obj.containsKey('data')) return null;

    // - { route: '11', stops: [...] } or { route: '11', data: [...] }
    if (obj.containsKey('route') && (obj.containsKey('stops') || obj.containsKey('data'))) return null;

    // - older payloads where top-level 'data' is a list and first item looks like a route/stop/eta object
    final payload = obj['data'];
    if (payload is List && payload.isNotEmpty) {
      final first = payload.first;
      if (first is Map) {
        if (first.containsKey('stop') || first.containsKey('route') || first.containsKey('seq') || first.containsKey('etaseq')) return null;
      }
    }

    return 'Snapshot does not appear to be route/stop/ETA data';
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

  /// Fetch a combined route status that merges route-stop list, stop metadata and route-level ETA entries.
  /// Returns a map with keys: 'type':'CombinedRouteStatus', 'route', 'serviceType', 'generatedtimestamp', 'data': { 'stops': [...] , 'routeEta': [...] }
  static Future<Map<String, dynamic>> fetchCombinedRouteStatus(String route, {String? serviceType}) async {
    final r = route.trim().toUpperCase();

    // Get route stops (from cache or API)
    Map<String, List<Map<String, dynamic>>> routeMap = await buildRouteToStopsMap();
    final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
    final routeStops = routeMap[r] ?? routeMap[base] ?? [];

    // Build stop map for metadata
    final stopMap = await buildStopMap();

    // Determine serviceType to query for ETA
    String? svc = serviceType;
    if (svc == null) {
      final variants = discoverRouteVariants(r);
      final svcs = variants['serviceTypes'] ?? [];
      if (svcs.isNotEmpty) svc = svcs.first;
    }

    List<Map<String, dynamic>> routeEta = [];
    if (svc != null) {
      try {
        routeEta = await fetchRouteEta(r, svc);
      } catch (_) {
        routeEta = [];
      }
    }

    // Group ETA by stop
    final Map<String, List<Map<String, dynamic>>> etaByStop = {};
    for (final e in routeEta) {
      final stopId = e['stop']?.toString() ?? '';
      if (stopId.isEmpty) continue;
      etaByStop.putIfAbsent(stopId, () => []).add(Map<String, dynamic>.from(e));
    }

    // Build enriched stops list
    final List<Map<String, dynamic>> enriched = [];
    for (final s in routeStops) {
      final stopId = s['stop']?.toString() ?? '';
      final seq = s['seq']?.toString() ?? '';
      final stopInfo = stopMap[stopId];
      final etas = etaByStop[stopId] ?? [];
      etas.sort((a, b) => (int.tryParse(a['etaseq']?.toString() ?? '') ?? 0).compareTo(int.tryParse(b['etaseq']?.toString() ?? '') ?? 0));
      enriched.add({
        'seq': seq,
        'stop': stopId,
        'stopInfo': stopInfo,
        'routeStop': s,
        'etas': etas,
      });
    }

    return {
      'type': 'CombinedRouteStatus',
      'route': r,
      'serviceType': svc,
      'generatedtimestamp': DateTime.now().toIso8601String(),
      'data': {
        'stops': enriched,
        'routeEta': routeEta,
      }
    };
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

  // ----------------------------
  // Request JSON persistence helpers
  // ----------------------------
  static const String _savedRequestsPrefPrefix = 'kmb_saved_request_';

  /// Save a JSON-serializable map (or string) under [key]. Overwrites existing.
  static Future<void> saveRequestJson(String key, dynamic jsonObj) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = json.encode(jsonObj);
    await prefs.setString('$_savedRequestsPrefPrefix$key', raw);
  }

  /// Load a saved JSON blob by key. Returns null if missing or invalid.
  static Future<dynamic> loadRequestJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_savedRequestsPrefPrefix$key');
    if (raw == null) return null;
    try {
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// List all saved request keys (without prefix).
  static Future<List<String>> listSavedRequestKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final out = <String>[];
    for (final k in keys) {
      if (k.startsWith(_savedRequestsPrefPrefix)) {
        out.add(k.substring(_savedRequestsPrefPrefix.length));
      }
    }
    return out..sort();
  }

  /// Delete a saved request by key.
  static Future<void> deleteSavedRequest(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_savedRequestsPrefPrefix$key');
  }



  /// Save JSON to app documents directory (or external storage where available).
  /// Save JSON to app documents directory (or external storage where available).
  /// Returns a SaveResult describing success or error.
  static Future<SaveResult> saveRequestJsonToFile(String filename, dynamic jsonObj) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory('${dir.path}/kmb_saved_requests');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final f = File('${outDir.path}/$filename.json');
      await f.writeAsString(json.encode(jsonObj));
      return SaveResult(path: f.path);
    } catch (e) {
      return SaveResult(error: e.toString());
    }
  }

  /// Load JSON from file path saved by saveRequestJsonToFile.
  static Future<dynamic> loadRequestJsonFromFile(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/kmb_saved_requests/$filename.json');
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// List filenames stored in the kmb_saved_requests documents folder.
  static Future<List<String>> listSavedRequestFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/kmb_saved_requests');
    if (!outDir.existsSync()) return [];
    final files = outDir.listSync().whereType<File>().toList();
    return files.map((f) => f.uri.pathSegments.last).toList();
  }

  /// Delete a saved request file by filename.
  static Future<bool> deleteSavedRequestFile(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/kmb_saved_requests/$filename');
      if (!f.existsSync()) return false;
      await f.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Atomically write bytes to a file by writing to a temporary file then renaming.
  static Future<void> _writeAtomicFile(File outFile, List<int> bytes) async {
    final tmp = File('${outFile.path}.tmp');
    if (tmp.existsSync()) await tmp.delete();
    await tmp.create(recursive: true);
    await tmp.writeAsBytes(bytes, flush: true);
    if (outFile.existsSync()) await outFile.delete();
    await tmp.rename(outFile.path);
  }

  /// Fetch prebuilt route/stops data from network and write them into
  /// application documents under `prebuilt/` atomically. Returns a result with success and error details.
  static Future<PrebuildResult> writePrebuiltAssetsToDocuments({Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final routeStops = await fetchRouteStopsAll();
      final stops = await fetchStopsAll();

      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (e) {
        // Fallback for platforms where getApplicationDocumentsDirectory fails (e.g., desktop)
        docDir = Directory.systemTemp.createTempSync('kmb_app_docs');
      }
      final outDir = Directory('${docDir.path}/prebuilt');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final routeOut = File('${outDir.path}/kmb_route_stops.json');
      final stopsOut = File('${outDir.path}/kmb_stops.json');

      await _writeAtomicFile(routeOut, utf8.encode(json.encode(_buildRouteMapFromList(routeStops))));
      await _writeAtomicFile(stopsOut, utf8.encode(json.encode({'data': stops})));

      // Invalidate caches so next call will load the new files
      _routeStopsCache = null;
      _stopsCache = null;
      return PrebuildResult(ok: true);
    } catch (e) {
      final errorMsg = e.toString();
      try { stderr.writeln('writePrebuiltAssetsToDocuments error: $errorMsg'); } catch (_) {}
      return PrebuildResult(ok: false, error: errorMsg);
    }
  }

  /// Copy bundled prebuilt assets (packaged with the app under assets/prebuilt)
  /// into the application documents `prebuilt/` folder. This is useful when
  /// network regeneration isn't possible but the app bundle contains prebuilt
  /// assets (for development or fallback).
  static Future<PrebuildResult> copyBundledPrebuiltToDocuments() async {
    try {
      final routeRaw = await rootBundle.loadString('assets/prebuilt/kmb_route_stops.json');
      final stopsRaw = await rootBundle.loadString('assets/prebuilt/kmb_stops.json');

      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docDir = Directory.systemTemp.createTempSync('kmb_app_docs');
      }
      final outDir = Directory('${docDir.path}/prebuilt');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final routeOut = File('${outDir.path}/kmb_route_stops.json');
      final stopsOut = File('${outDir.path}/kmb_stops.json');

      await _writeAtomicFile(routeOut, utf8.encode(routeRaw));
      await _writeAtomicFile(stopsOut, utf8.encode(stopsRaw));

      _routeStopsCache = null;
      _stopsCache = null;
      return PrebuildResult(ok: true);
    } catch (e) {
      final err = e.toString();
      try { stderr.writeln('copyBundledPrebuiltToDocuments error: $err'); } catch (_) {}
      return PrebuildResult(ok: false, error: err);
    }
  }
}

/// Result of attempting to save a JSON request to file.
class SaveResult {
  final String? path;
  final String? error;
  SaveResult({this.path, this.error});
  bool get ok => path != null && (error == null || error!.isEmpty);
}

/// Result of attempting to write prebuilt assets to documents.
class PrebuildResult {
  final bool ok;
  final String? error;
  PrebuildResult({required this.ok, this.error});
  @override
  String toString() => ok ? 'Success' : 'Error: $error';
}

// Example dictionary initialization (replace with actual data from kmb_dictionary.md)
final Map<String, String> kmbDictionary = {
  // 'key1': 'value1',
  // 'key2': 'value2',
};

final Kmb kmb = Kmb(kmbDictionary);

// (normalized version of _parseRouteStopsAsset is defined later)

// Top-level helper for compute() to build a route->stops map from a List of route-stop entries.
Map<String, List<Map<String, dynamic>>> _buildRouteMapFromList(List<dynamic> routeStops) {
  // Work on copies to avoid concurrent modification during iteration
  final List<Map<String, dynamic>> entriesCopy = routeStops.map((e) {
    try {
      return Map<String, dynamic>.from(e as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }).toList(growable: false);

  final Map<String, List<Map<String, dynamic>>> map = {};
  for (final entry in entriesCopy) {
    final route = (entry['route'] ?? '').toString().toUpperCase();
    // Normalize entry keys to the shape expected by the app (e.g. service_type -> servicetype)
    final normalized = <String, dynamic>{};
    entry.forEach((k, v) {
      var nk = k;
      if (k == 'service_type') nk = 'servicetype';
      normalized[nk] = v;
    });
    map.putIfAbsent(route, () => []).add(normalized);
  }

  // Also add entries grouped by numeric base (so 11A and 11 map under 11)
  final Map<String, List<Map<String, dynamic>>> extended = {};
  // copy existing groups
  for (final k in List<String>.from(map.keys)) {
    extended[k] = List<Map<String, dynamic>>.from(map[k]!);
  }

  final baseRe = RegExp(r'^(\d+)');
  for (final key in List<String>.from(map.keys)) {
    final m = baseRe.firstMatch(key);
    if (m != null) {
      final base = m.group(1)!;
      extended.putIfAbsent(base, () => []);
      extended[base]!.addAll(List<Map<String, dynamic>>.from(map[key]!));
    }
  }

  // Sort each list by seq (operate on copies)
  for (final k in List<String>.from(extended.keys)) {
    final listCopy = List<Map<String, dynamic>>.from(extended[k]!);
    listCopy.sort((a, b) {
      final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });
    extended[k] = listCopy;
  }

  return extended;
}

// Top-level helper for compute() to parse a raw stops JSON asset into a stopId->stopInfo map.
Map<String, Map<String, dynamic>> _parseStopsAsset(String raw) {
  final decoded = json.decode(raw) as Map<String, dynamic>;
  final payload = decoded['data'];
  final Map<String, Map<String, dynamic>> map = {};
  if (payload is List) {
    for (final s in payload) {
      final id = s['stop']?.toString() ?? '';
      if (id.isEmpty) continue;
      map[id] = Map<String, dynamic>.from(s);
    }
  } else if (payload is Map) {
    // Possibly the asset is already a map keyed by stop id
    payload.forEach((k, v) {
      try {
        map[k.toString()] = Map<String, dynamic>.from(v as Map);
      } catch (_) {}
    });
  }
  return map;
}

// Normalize a single route-stop entry object coming from network or asset so the
// rest of the app can rely on consistent key names.
Map<String, dynamic> _normalizeRouteStopEntry(Map<String, dynamic> src) {
  final out = <String, dynamic>{};
  src.forEach((k, v) {
    var nk = k;
    if (k == 'service_type') nk = 'servicetype';
    // keep other keys as-is
    out[nk] = v;
  });
  return out;
}

// Top-level helper for compute() to parse a raw JSON asset string into route->stops map.
Map<String, List<Map<String, dynamic>>> _parseRouteStopsAsset(String raw) {
  final decoded = json.decode(raw) as Map<String, dynamic>;
  final Map<String, List<Map<String, dynamic>>> map = {};
  decoded.forEach((k, v) {
    try {
      final list = (v as List).map((e) => _normalizeRouteStopEntry(Map<String, dynamic>.from(e))).toList();
      map[k] = List<Map<String, dynamic>>.from(list);
    } catch (_) {
      // fallback: try to coerce without normalization
      map[k] = List<Map<String, dynamic>>.from((v as List).map((e) => Map<String, dynamic>.from(e)));
    }
  });
  return map;
}


