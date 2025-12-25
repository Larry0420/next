// kmb.dart
// Implementation based on kmb.md spec and kmb_dictionary.md

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show compute;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  /// Fetches KMB routes from API with caching support
  static Future<List<String>> fetchRoutes({Duration ttl = const Duration(hours: 24)}) async {
    // Check in-memory cache first
    if (_routesCache != null && _routesCacheAt != null) {
      if (DateTime.now().difference(_routesCacheAt!) < ttl) {
        return _routesCache!;
      }
    }

    // Try to load from SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_routesCachePrefKey);
      if (cachedJson != null) {
        final cachedRoutes = (json.decode(cachedJson) as List).map((e) => e as String).toList();
        _routesCache = cachedRoutes;
        _routesCacheAt = DateTime.now();
        return cachedRoutes;
      }
    } catch (e) {
      // Ignore cache loading errors, proceed to fetch fresh data
    }

    final url = Uri.parse('https://data.etabus.gov.hk//v1/transport/kmb/route/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final payload = data['data'];
        if (payload is List && payload.isNotEmpty) {
          final routes = payload
              .map<String>((route) => (route as Map<String, dynamic>)['route'] as String)
              .toList();

          // Cache the results
          _routesCache = routes;
          _routesCacheAt = DateTime.now();

          // Persist to SharedPreferences
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_routesCachePrefKey, json.encode(routes));
          } catch (_) {
            // Ignore persistence errors
          }

          return routes;
        } else {
          throw Exception('Invalid response: empty or missing data array');
        }
      } else if (response.statusCode == 422) {
        throw Exception('API validation error: Invalid request parameters');
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to load KMB routes');
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Invalid JSON response from routes API');
      }
      rethrow;
    }
  }

  /// Fetches KMB routes from API with full route details for enhanced display
  static Future<List<Map<String, dynamic>>> fetchRoutesWithDetails({Duration ttl = const Duration(hours: 24)}) async {
    // Check in-memory cache first
    if (_routesDetailsCache != null && _routesDetailsCacheAt != null) {
      if (DateTime.now().difference(_routesDetailsCacheAt!) < ttl) {
        return _routesDetailsCache!;
      }
    }

    // Try to load from SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache version - clear old caches if version mismatch
      final cachedVersion = prefs.getInt(_cacheVersionKey) ?? 0;
      if (cachedVersion != _currentCacheVersion) {
        // Clear all old caches
        await prefs.remove(_routesDetailsCachePrefKey);
        await prefs.remove(_routeIndexPrefKey);
        await prefs.setInt(_cacheVersionKey, _currentCacheVersion);
      } else {
        final cachedJson = prefs.getString(_routesDetailsCachePrefKey);
        if (cachedJson != null) {
          final cachedRoutes = (json.decode(cachedJson) as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _routesDetailsCache = cachedRoutes;
          _routesDetailsCacheAt = DateTime.now();
          return cachedRoutes;
        }
      }
    } catch (e) {
      // Ignore cache loading errors, proceed to fetch fresh data
    }

    final url = Uri.parse('https://data.etabus.gov.hk//v1/transport/kmb/route/');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final payload = data['data'];
        if (payload is List && payload.isNotEmpty) {
          final routes = payload
              .map<Map<String, dynamic>>((route) => Map<String, dynamic>.from(route as Map<String, dynamic>))
              .toList();

          // Cache the detailed results
          _routesDetailsCache = routes;
          _routesDetailsCacheAt = DateTime.now();

          // Persist to SharedPreferences
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_routesDetailsCachePrefKey, json.encode(routes));
          } catch (_) {
            // Ignore persistence errors
          }

          return routes;
        } else {
          throw Exception('Invalid response: empty or missing data array');
        }
      } else if (response.statusCode == 422) {
        throw Exception('API validation error: Invalid request parameters');
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to load KMB routes');
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Invalid JSON response from routes API');
      }
      rethrow;
    }
  }

  // Enhanced route details cache
  static List<Map<String, dynamic>>? _routesDetailsCache;
  static DateTime? _routesDetailsCacheAt;
  static const String _routesDetailsCachePrefKey = 'kmb_routes_details_cache_json';
  static const String _cacheVersionKey = 'kmb_cache_version';
  static const int _currentCacheVersion = 2; // Increment when API URL changes

  /// Groups routes by their origin and destination for enhanced display
  static Future<Map<String, List<Map<String, dynamic>>>> groupRoutesByDestinations() async {
    final routes = await fetchRoutesWithDetails();

    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final route in routes) {
      final routeNum = route['route'] as String;
      final bound = route['bound'] as String;
      final origEn = route['orig_en'] as String? ?? '';
      final destEn = route['dest_en'] as String? ?? '';
      final origTc = route['orig_tc'] as String? ?? '';
      final destTc = route['dest_tc'] as String? ?? '';

      // Create a key that combines route number with origin->destination
      final direction = bound == 'O' ? 'outbound' : 'inbound';
      final key = '$routeNum: $origEn → $destEn';

      // Also create a Traditional Chinese version
      final keyTc = '$routeNum: $origTc → $destTc';

      // Use English key as primary, but include both languages
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add({
        ...route,
        'display_key': key,
        'display_key_tc': keyTc,
        'direction': direction,
      });
    }

    return grouped;
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
      final urlStr = 'https://data.etabus.gov.hk//v1/transport/kmb/route/route-stop/${Uri.encodeComponent(cand)}';
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
      'https://data.etabus.gov.hk//v1/transport/kmb/route/route-stop',
      'https://data.etabus.gov.hk//v1/transport/kmb/route-stop',
      'https://data.etabus.gov.hk//v1/transport/kmb/route/route-stop/',
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

  /// Fetch route-stops for a specific route, direction, and service type.
  /// Uses the Route-Stop API: /v1/transport/kmb/route-stop/{route}/{direction}/{service_type}
  /// 
  /// Parameters:
  /// - route: Case-sensitive route number (e.g., "1", "276B")
  /// - direction: "inbound" or "outbound" (lowercase)
  /// - serviceType: Service type number as string (e.g., "1", "2", "3")
  /// 
  /// Returns ordered list of stop sequence objects with co, route, bound, service_type, seq, stop, data_timestamp.
  static Future<List<Map<String, dynamic>>> fetchRouteStops(
    String route,
    String direction,
    String serviceType,
  ) async {
    // Validate direction parameter
    final dir = direction.toLowerCase();
    if (dir != 'inbound' && dir != 'outbound') {
      throw ArgumentError('Direction must be "inbound" or "outbound", got: $direction');
    }

    final url = 'https://data.etabus.gov.hk//v1/transport/kmb/route-stop/${Uri.encodeComponent(route)}/$dir/$serviceType';
    
    try {
      final resp = await http.get(Uri.parse(url));
      
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final payload = data['data'];
        
        if (payload is List) {
          return List<Map<String, dynamic>>.from(
            payload.map((e) => Map<String, dynamic>.from(e))
          );
        } else {
          throw Exception('Unexpected payload type: ${payload.runtimeType}');
        }
      } else if (resp.statusCode == 422) {
        throw Exception('Invalid route parameters: route=$route, direction=$direction, service_type=$serviceType');
      } else {
        final snippet = resp.body.length > 200 ? resp.body.substring(0, 200) + '...' : resp.body;
        throw Exception('HTTP ${resp.statusCode}: $snippet');
      }
    } catch (e) {
      throw Exception('Failed to fetch route stops for $route/$direction/$serviceType: ${e.toString()}');
    }
  }

  /// Fetch the full stop list (all bus stops) from the public endpoints.
  static Future<List<Map<String, dynamic>>> fetchStopsAll() async {
    final urlCandidates = [
      'https://data.etabus.gov.hk//v1/transport/kmb/stop',
      'https://data.etabus.gov.hk//v1/transport/kmb/stop/',
    ];
    String? lastError;
    for (final u in urlCandidates) {
      try {
        final resp = await http.get(Uri.parse(u));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final payload = data['data'];
          if (payload is List) {
            // Validate and filter stops with valid coordinates
            final validStops = payload.where((stop) {
              final stopMap = stop as Map<String, dynamic>;
              final lat = stopMap['lat'];
              final long = stopMap['long'];
              // Skip stops without valid coordinates
              if (lat == null || long == null) return false;
              try {
                double.parse(lat.toString());
                double.parse(long.toString());
                return true;
              } catch (_) {
                return false;
              }
            }).map((e) => Map<String, dynamic>.from(e)).toList();

            return validStops;
          } else {
            lastError = 'Unexpected payload type at $u: ${payload.runtimeType}';
          }
        } else if (resp.statusCode == 422) {
          lastError = 'API validation error at $u: Invalid request parameters';
        } else {
          final snippet = resp.body.length > 200 ? resp.body.substring(0, 200) + '...' : resp.body;
          lastError = 'HTTP ${resp.statusCode} from $u: $snippet';
        }
      } catch (e) {
        lastError = 'Error fetching $u: ${e.toString()}';
      }
    }

    // If all network requests fail, try to return cached data
    try {
      if (_stopsCache != null && _stopsCache!.isNotEmpty) {
        return _stopsCache!.values.toList();
      }
      // Try loading from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_stopsCachePrefKey);
      if (cachedJson != null) {
        final cachedMap = json.decode(cachedJson) as Map<String, dynamic>;
        final stops = cachedMap.values.map((e) => Map<String, dynamic>.from(e)).toList();
        return stops;
      }
    } catch (e) {
      lastError = '${lastError ?? 'Network failed'}; cache fallback also failed: ${e.toString()}';
    }

    throw Exception('Failed to fetch stop list. Last error: ${lastError ?? 'no response'}');
  }

  // In-memory cache for routes and timestamp
  static List<String>? _routesCache;
  static DateTime? _routesCacheAt;

  /// Force refresh the routes cache by fetching from API again.
  static Future<void> refreshRoutesCache() async {
    _routesCache = null;
    _routesCacheAt = null;
    await fetchRoutes(ttl: Duration.zero);
  }

  // Enhanced route index with full route details for searching
  static Map<String, Map<String, dynamic>>? _routeIndex;
  static DateTime? _routeIndexAt;

  static const String _routeIndexPrefKey = 'kmb_route_index_json';

  /// Build comprehensive route index with full route details for enhanced searching
  static Future<Map<String, Map<String, dynamic>>> buildRouteIndex({Duration ttl = const Duration(hours: 24)}) async {
    // Check in-memory cache first
    if (_routeIndex != null && _routeIndexAt != null) {
      if (DateTime.now().difference(_routeIndexAt!) < ttl) return _routeIndex!;
    }

    // Try to load from SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache version - if mismatch, skip cache loading
      final cachedVersion = prefs.getInt(_cacheVersionKey) ?? 0;
      if (cachedVersion == _currentCacheVersion) {
        final cachedJson = prefs.getString(_routeIndexPrefKey);
        if (cachedJson != null) {
          final cachedIndex = json.decode(cachedJson) as Map<String, dynamic>;
          final index = cachedIndex.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
          _routeIndex = index;
          _routeIndexAt = DateTime.now();
          return index;
        }
      }
    } catch (e) {
      // Ignore cache loading errors, proceed to fetch fresh data
    }

    // Fetch all routes from route list API
    final routes = await fetchRoutesWithDetails(ttl: Duration.zero);
    final index = <String, Map<String, dynamic>>{};

    // Group routes by route number and direction
    final routeGroups = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final route in routes) {
      final routeNum = route['route'] as String;
      final bound = route['bound'] as String;

      if (!routeGroups.containsKey(routeNum)) {
        routeGroups[routeNum] = {};
      }
      if (!routeGroups[routeNum]!.containsKey(bound)) {
        routeGroups[routeNum]![bound] = [];
      }
      routeGroups[routeNum]![bound]!.add(route);
    }

    // For each route, create index entries for each direction/service type combination
    for (final routeEntry in routeGroups.entries) {
      final routeNum = routeEntry.key;
      final boundGroups = routeEntry.value;

      for (final boundEntry in boundGroups.entries) {
        final bound = boundEntry.key;
        final routeVariants = boundEntry.value;

        for (final route in routeVariants) {
          // Keep bound as I/O from API, but add human-readable direction
          final direction = bound == 'O' ? 'outbound' : bound == 'I' ? 'inbound' : 'unknown';

          // Create searchable index entry
          final indexEntry = {
            'route': routeNum,
            'direction': direction,  // Human-readable for display
            'service_type': route['service_type'] ?? '',
            'orig_en': route['orig_en'] ?? '',
            'orig_tc': route['orig_tc'] ?? '',
            'orig_sc': route['orig_sc'] ?? '',
            'dest_en': route['dest_en'] ?? '',
            'dest_tc': route['dest_tc'] ?? '',
            'dest_sc': route['dest_sc'] ?? '',
            'bound': bound,  // Original API value (I/O)
            'co': route['co'] ?? 'KMB',
            'data_timestamp': route['data_timestamp'] ?? '',
            // Add searchable text combining all names
            'search_text': [
              routeNum,
              route['orig_en'] ?? '',
              route['orig_tc'] ?? '',
              route['orig_sc'] ?? '',
              route['dest_en'] ?? '',
              route['dest_tc'] ?? '',
              route['dest_sc'] ?? '',
            ].join(' ').toLowerCase(),
          };

          // Use route-bound-serviceType as key (using I/O from API)
          final indexKey = '${routeNum}_${bound}_${route['service_type'] ?? ''}';
          index[indexKey] = indexEntry;
        }
      }
    }

    // Cache the index
    _routeIndex = index;
    _routeIndexAt = DateTime.now();

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_routeIndexPrefKey, json.encode(index));
    } catch (_) {
      // Ignore persistence errors
    }

    return index;
  }

  /// Search routes using enhanced index with origin/destination matching
  static Future<List<Map<String, dynamic>>> searchRoutes(String query, {int? maxResults}) async {
    if (query.trim().isEmpty) return [];

    final index = await buildRouteIndex();
    final searchTerm = query.toLowerCase().trim();

    // Find matches
    final matches = index.values.where((route) {
      final searchText = route['search_text'] as String? ?? '';
      return searchText.contains(searchTerm);
    }).toList();

    // Sort by relevance (exact route matches first, then substring matches)
    matches.sort((a, b) {
      final routeA = (a['route'] as String).toLowerCase();
      final routeB = (b['route'] as String).toLowerCase();

      // Exact route matches get highest priority
      if (routeA == searchTerm && routeB != searchTerm) return -1;
      if (routeB == searchTerm && routeA != searchTerm) return 1;

      // Route starts with search term
      if (routeA.startsWith(searchTerm) && !routeB.startsWith(searchTerm)) return -1;
      if (routeB.startsWith(searchTerm) && !routeA.startsWith(searchTerm)) return 1;

      // Otherwise maintain original order
      return 0;
    });

    // Return all matches if maxResults is null, otherwise limit
    return maxResults != null ? matches.take(maxResults).toList() : matches;
  }

  static const String _routesCachePrefKey = 'kmb_routes_cache_json';

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
    
    // First, try to load a prebuilt stops asset from app documents (mobile apps with updated data)
    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/kmb_stops.json');
      if (prebuiltFile.existsSync()) {
        final raw = await prebuiltFile.readAsString();
        if (raw.isNotEmpty) {
          final map = await compute(_parseStopsAsset, raw);
          _stopsCache = map;
          _stopsCacheAt = DateTime.now();
          print('✓ Loaded stops from app documents (${map.length} stops)');
          // persist to shared_prefs for fallback
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_stopsCachePrefKey, json.encode(map));
          } catch (_) {}
          return map;
        }
      }
    } catch (e) {
      print('→ App documents not available: $e');
    }

    // Next, try bundled asset (works for APK, web, Windows, all platforms)
    try {
      print('→ Attempting to load bundled asset: assets/prebuilt/kmb_stops.json');
      final raw = await rootBundle.loadString('assets/prebuilt/kmb_stops.json');
      print('→ Asset loaded, size: ${raw.length} bytes');
      if (raw.isNotEmpty) {
        final map = await compute(_parseStopsAsset, raw);
        _stopsCache = map;
        _stopsCacheAt = DateTime.now();
        print('✓ Loaded stops from bundled asset (${map.length} stops)');
        if (map.isNotEmpty) {
          // Debug: show first stop to verify structure
          final firstKey = map.keys.first;
          print('→ Sample stop: $firstKey = ${map[firstKey]}');
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_stopsCachePrefKey, json.encode(map));
        } catch (_) {}
        return map;
      }
    } catch (e, stack) {
      print('→ Bundled asset load failed: $e');
      print('→ Stack trace: $stack');
    }

    // Fallback to API if bundled asset is not available
    try {
      print('→ Fetching stops from API...');
      final stops = await fetchStopsAll();
      final Map<String, Map<String, dynamic>> map = {};
      for (final s in stops) {
        final id = s['stop']?.toString() ?? '';
        if (id.isEmpty) continue;
        map[id] = Map<String, dynamic>.from(s);
      }

      _stopsCache = map;
      _stopsCacheAt = DateTime.now();
      print('✓ Loaded stops from API (${map.length} stops)');

      // persist to shared_prefs for fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_stopsCachePrefKey, json.encode(map));
      } catch (_) {}

      return map;
    } catch (e) {
      print('✗ API fetch failed: $e');
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
          print('✓ Loaded stops from SharedPreferences cache (${map.length} stops)');
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
      'https://data.etabus.gov.hk//v1/transport/kmb/stop-eta/${Uri.encodeComponent(s)}',
      'https://data.etabus.gov.hk//v1/transport/kmb/stop/${Uri.encodeComponent(s)}/eta',
      'https://data.etabus.gov.hk//v1/transport/kmb/stop-eta/${Uri.encodeComponent(s)}/',
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
    final url = Uri.parse('https://data.etabus.gov.hk//v1/transport/kmb/eta/${Uri.encodeComponent(s)}/${Uri.encodeComponent(r)}/${Uri.encodeComponent(svc)}');
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
    final url = Uri.parse('https://data.etabus.gov.hk//v1/transport/kmb/route-eta/${Uri.encodeComponent(r)}/${Uri.encodeComponent(svc)}');
    
    print('=== FETCHING ROUTE-ETA API ===');
    print('URL: $url');
    print('Route: $r, Service Type: $svc');
    
    final resp = await http.get(url);
    print('Response status: ${resp.statusCode}');
    
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      print('Response keys: ${data.keys.toList()}');
      
      final payload = data['data'];
      print('Data type: ${payload.runtimeType}');
      
      if (payload is List) {
        print('Data is List with ${payload.length} entries');
        if (payload.isNotEmpty) {
          print('First entry keys: ${(payload.first as Map).keys.toList()}');
          print('First entry: ${payload.first}');
        }
        print('==============================');
        return List<Map<String, dynamic>>.from(payload.map((e) => Map<String, dynamic>.from(e)));
      }
    }
    print('API call failed!');
    print('==============================');
    throw Exception('Failed to fetch route ETA for $route service $serviceType');
  }

  // Preference key for using per-route API for route stops
  static const String _useRouteApiKey = 'useRouteApiForRouteStops';
  static const String _pinnedRoutesKey = 'pinnedKmbRoutes';
  static const String _pinnedStopsKey = 'pinnedKmbStops';
  static const String _routeHistoryKey = 'kmbRouteHistory';

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

  /// Pin a route for quick access
  static Future<void> pinRoute(String route, String direction, String serviceType, String label) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    
    // Avoid duplicates
    pinned.removeWhere((item) => 
      item['route'] == route && 
      item['direction'] == direction && 
      item['serviceType'] == serviceType
    );
    
    pinned.add({
      'route': route,
      'direction': direction,
      'serviceType': serviceType,
      'label': label,
      'pinnedAt': DateTime.now().toIso8601String(),
    });
    
    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  /// Get all pinned routes
  static Future<List<Map<String, dynamic>>> getPinnedRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Unpin a route
  static Future<void> unpinRoute(String route, String direction, String serviceType) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    
    pinned.removeWhere((item) => 
      item['route'] == route && 
      item['direction'] == direction && 
      item['serviceType'] == serviceType
    );
    
    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  /// Pin a specific stop on a route
  static Future<void> pinStop({
    required String route,
    required String stopId,
    required String seq,
    required String stopName,
    String? stopNameEn,
    String? stopNameTc,
    String? latitude,
    String? longitude,
    String? direction,
    String? serviceType,
    String? destEn,
    String? destTc,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    
    // Avoid duplicates
    pinned.removeWhere((item) => 
      item['route'] == route && 
      item['stopId'] == stopId && 
      item['seq'] == seq
    );
    
    pinned.add({
      'route': route,
      'stopId': stopId,
      'seq': seq,
      'stopName': stopName,
      'stopNameEn': stopNameEn ?? stopName,
      'stopNameTc': stopNameTc ?? stopName,
      'latitude': latitude,
      'longitude': longitude,
      'direction': direction,
      'serviceType': serviceType,
      'destEn': destEn,
      'destTc': destTc,
      'pinnedAt': DateTime.now().toIso8601String(),
    });
    
    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }

  /// Get all pinned stops
  static Future<List<Map<String, dynamic>>> getPinnedStops() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Unpin a specific stop
  static Future<void> unpinStop(String route, String stopId, String seq) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    
    pinned.removeWhere((item) => 
      item['route'] == route && 
      item['stopId'] == stopId && 
      item['seq'] == seq
    );
    
    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }

  /// Add a route to history (automatically called when viewing a route)
  static Future<void> addToHistory(String route, String direction, String serviceType, String label) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List<dynamic> history = json.decode(historyJson);
    
    // Remove existing entry to avoid duplicates (will re-add with new timestamp)
    history.removeWhere((item) => 
      item['route'] == route && 
      item['direction'] == direction && 
      item['serviceType'] == serviceType
    );
    
    // Add to front (most recent first)
    history.insert(0, {
      'route': route,
      'direction': direction,
      'serviceType': serviceType,
      'label': label,
      'accessedAt': DateTime.now().toIso8601String(),
    });
    
    // Keep only last 50 entries
    if (history.length > 50) {
      history.removeRange(50, history.length);
    }
    
    await prefs.setString(_routeHistoryKey, json.encode(history));
  }

  /// Get route history
  static Future<List<Map<String, dynamic>>> getRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List<dynamic> history = json.decode(historyJson);
    return history.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Clear all route history
  static Future<void> clearRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeHistoryKey, '[]');
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

  // In-memory cache for stop -> routes mapping
  static Map<String, List<String>>? _stopToRoutesCache;
  static DateTime? _stopToRoutesCacheAt;

  /// Build and cache a map of stopId -> list of routes that serve the stop.
  /// TTL default 24 hours.
  static Future<Map<String, List<String>>> buildStopToRoutesMap({Duration ttl = const Duration(hours: 24)}) async {
    if (_stopToRoutesCache != null && _stopToRoutesCacheAt != null) {
      if (DateTime.now().difference(_stopToRoutesCacheAt!) < ttl) return _stopToRoutesCache!;
    }

    final routeMap = await buildRouteToStopsMap();
    final Map<String, List<String>> out = {};
    routeMap.forEach((route, entries) {
      for (final e in entries) {
        final sid = e['stop']?.toString() ?? '';
        if (sid.isEmpty) continue;
        out.putIfAbsent(sid, () => []);
        if (!out[sid]!.contains(route)) out[sid]!.add(route);
      }
    });

    _stopToRoutesCache = out;
    _stopToRoutesCacheAt = DateTime.now();
    return out;
  }

  /// Returns the list of routes serving a stop id (cached). Returns empty list when none.
  static Future<List<String>> getRoutesForStop(String stopId) async {
    final map = await buildStopToRoutesMap();
    return List<String>.from(map[stopId] ?? []);
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
  /// Fetch detailed route metadata for route verification and display
  static Future<Map<String, dynamic>> fetchRouteWithParams(String route, String direction, String serviceType) async {
    final r = route.trim().toUpperCase();
    final dir = direction.trim().toLowerCase(); // API expects lowercase direction
    final svc = serviceType.trim();

    // Validate direction parameter
    if (dir != 'outbound' && dir != 'inbound') {
      throw Exception('Invalid direction: must be "outbound" or "inbound"');
    }

    final url = Uri.parse('https://data.etabus.gov.hk//v1/transport/kmb/route/${Uri.encodeComponent(r)}/${Uri.encodeComponent(dir)}/${Uri.encodeComponent(svc)}');

    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final payload = data['data'];
        if (payload != null && payload is Map<String, dynamic>) {
          return data;
        } else {
          throw Exception('Invalid response: missing or invalid route data');
        }
      } else if (resp.statusCode == 422) {
        throw Exception('Route validation error: Invalid route "$r", direction "$dir", or service type "$svc"');
      } else {
        throw Exception('HTTP ${resp.statusCode}: Failed to fetch route data for $r/$dir/$svc');
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Invalid JSON response from route API for $r/$dir/$svc');
      }
      rethrow;
    }
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

  /// Request storage permission where applicable. Returns true if permission granted.
  static Future<bool> requestStoragePermission() async {
    if (await Permission.storage.isGranted) return true;
    final status = await Permission.storage.request();
    return status.isGranted;
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
      _routeIndex = null;
      _routeIndexAt = null;
      _routesDetailsCache = null;
      _routesDetailsCacheAt = null;
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

  // Preference keys for daily update tracking
  static const String _lastPrebuiltUpdateKey = 'kmb_last_prebuilt_update';
  static const String _lastPrebuiltUpdateAttemptKey = 'kmb_last_prebuilt_update_attempt';

  /// Check if prebuilt data should be updated based on daily schedule.
  /// Updates are checked after 05:00 AM daily (matching the API update schedule).
  /// Returns true if an update was performed, false otherwise.
  /// This method runs in the background and doesn't block the UI.
  static Future<bool> checkAndUpdatePrebuiltDataDaily({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      
      // Check if we should update (after 05:00 AM daily)
      final todayFive = DateTime(now.year, now.month, now.day, 5);
      
      if (!force) {
        // Check last update time
        final lastUpdateStr = prefs.getString(_lastPrebuiltUpdateKey);
        DateTime? lastUpdate;
        if (lastUpdateStr != null) {
          try {
            lastUpdate = DateTime.parse(lastUpdateStr);
          } catch (_) {
            lastUpdate = null;
          }
        }
        
        // Check last attempt time to avoid too frequent attempts
        final lastAttemptStr = prefs.getString(_lastPrebuiltUpdateAttemptKey);
        DateTime? lastAttempt;
        if (lastAttemptStr != null) {
          try {
            lastAttempt = DateTime.parse(lastAttemptStr);
          } catch (_) {
            lastAttempt = null;
          }
        }
        
        // Don't update if:
        // 1. We already updated today after 05:00
        // 2. We attempted to update in the last hour (to avoid repeated failures)
        if (lastUpdate != null && lastUpdate.isAfter(todayFive)) {
          return false; // Already updated today
        }
        
        if (lastAttempt != null && now.difference(lastAttempt).inHours < 1) {
          return false; // Attempted too recently
        }
        
        // Only attempt update after 05:00 AM
        if (now.isBefore(todayFive)) {
          return false; // Too early in the day
        }
      }
      
      // Record attempt time
      await prefs.setString(_lastPrebuiltUpdateAttemptKey, now.toIso8601String());
      
      // Attempt to update prebuilt data from API
      print('🔄 Checking for daily KMB data update...');
      final result = await writePrebuiltAssetsToDocuments(timeout: const Duration(seconds: 60));
      
      if (result.ok) {
        // Update successful - record timestamp
        await prefs.setString(_lastPrebuiltUpdateKey, now.toIso8601String());
        print('✅ KMB prebuilt data updated successfully');
        
        // Also refresh route index cache
        _routeIndex = null;
        _routeIndexAt = null;
        
        return true;
      } else {
        print('⚠️ KMB prebuilt data update failed: ${result.error}');
        return false;
      }
    } catch (e) {
      print('❌ Error checking/updating KMB prebuilt data: $e');
      return false;
    }
  }

  /// Initialize and ensure prebuilt data is available.
  /// This should be called at app startup to ensure data is ready.
  /// It will:
  /// 1. Check if app documents prebuilt data exists, if not copy from bundled assets
  /// 2. Check if daily update is needed and perform it in background if needed
  static Future<void> initializePrebuiltData({bool checkUpdate = true}) async {
    try {
      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        // Fallback for platforms where getApplicationDocumentsDirectory fails
        return;
      }
      
      final outDir = Directory('${docDir.path}/prebuilt');
      final routeFile = File('${outDir.path}/kmb_route_stops.json');
      final stopsFile = File('${outDir.path}/kmb_stops.json');
      
      // If prebuilt data doesn't exist in app documents, copy from bundled assets
      if (!routeFile.existsSync() || !stopsFile.existsSync()) {
        print('📦 Copying bundled prebuilt data to app documents...');
        final copyResult = await copyBundledPrebuiltToDocuments();
        if (!copyResult.ok) {
          print('⚠️ Failed to copy bundled prebuilt data: ${copyResult.error}');
        }
      }
      
      // Check for daily update in background (non-blocking)
      if (checkUpdate) {
        // Run update check in background without blocking
        checkAndUpdatePrebuiltDataDaily().catchError((e) {
          print('Background update check failed: $e');
          return false;
        });
      }
    } catch (e) {
      print('Error initializing prebuilt data: $e');
    }
  }

  /// Get the last update timestamp for prebuilt data.
  /// Returns null if never updated.
  static Future<DateTime?> getLastPrebuiltUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_lastPrebuiltUpdateKey);
      if (lastUpdateStr != null) {
        return DateTime.parse(lastUpdateStr);
      }
    } catch (_) {}
    return null;
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
  
  // Check if data is wrapped in 'data' key or is a direct map
  final payload = decoded.containsKey('data') ? decoded['data'] : decoded;
  
  final Map<String, Map<String, dynamic>> map = {};
  if (payload is List) {
    // Array format: [{"stop": "id1", "name_en": "..."}, ...]
    for (final s in payload) {
      final id = s['stop']?.toString() ?? '';
      if (id.isEmpty) continue;
      map[id] = Map<String, dynamic>.from(s);
    }
  } else if (payload is Map) {
    // Map format: {"id1": {"name_en": "...", ...}, "id2": {...}}
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
// Supports two asset shapes:
// 1) legacy: { "<route>": [ {route-stop-entry}, ... ], ... }
// 2) optimized: { "<route>": { "O": { dest_en.., dest_tc.., stops: [...] }, "I": { ... } }, ... }
// The returned map is normalized to Map<route, List<entry>> where each entry contains
// at minimum: 'seq', 'stop', 'servicetype' (or 'service_type' normalized) and we also
// inject 'bound' and per-bound 'dest_en'/'dest_tc' when available so callers (UI) can
// easily show direction and destination metadata.
Map<String, List<Map<String, dynamic>>> _parseRouteStopsAsset(String raw) {
  final decoded = json.decode(raw) as Map<String, dynamic>;
  final Map<String, List<Map<String, dynamic>>> map = {};

  decoded.forEach((routeKey, value) {
    try {
      // Case A: legacy list-of-entries
      if (value is List) {
        final list = value.map((e) {
          final entry = _normalizeRouteStopEntry(Map<String, dynamic>.from(e as Map));
          // preserve bound if present (some legacy entries already include it)
          return entry;
        }).toList();
        map[routeKey] = List<Map<String, dynamic>>.from(list);
        return;
      }

      // Case B: optimized per-bound structure
      if (value is Map) {
        final routeObj = value as Map<String, dynamic>;
        final List<Map<String, dynamic>> combined = [];
        routeObj.forEach((boundKey, boundVal) {
          try {
            final boundObj = boundVal as Map<String, dynamic>;
            final destEn = (boundObj['dest_en'] ?? boundObj['desten'] ?? '')?.toString() ?? '';
            final destTc = (boundObj['dest_tc'] ?? boundObj['desttc'] ?? '')?.toString() ?? '';
            final stopsList = boundObj['stops'];
            if (stopsList is List) {
              for (final rawEntry in stopsList) {
                try {
                  final entry = _normalizeRouteStopEntry(Map<String, dynamic>.from(rawEntry as Map));
                  // inject bound and dest fields for convenience
                  entry['bound'] = boundKey;
                  if (destEn.isNotEmpty) entry['dest_en'] = destEn;
                  if (destTc.isNotEmpty) entry['dest_tc'] = destTc;
                  combined.add(entry);
                } catch (_) {}
              }
            }
          } catch (_) {}
        });
        map[routeKey] = combined;
        return;
      }

      // Unknown shape: try to coerce as list
      map[routeKey] = List<Map<String, dynamic>>.from((value as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      // If any coercion failed, ensure route exists with empty list
      map[routeKey] = map[routeKey] ?? <Map<String, dynamic>>[];
    }
  });

  return map;
}


