import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Citybus {
  final Map dictionary;

  Citybus(this.dictionary);

  String? lookup(String key) => dictionary[key];

  void set(String key, String value) => dictionary[key] = value;

  void remove(String key) => dictionary.remove(key);

  List keys() => dictionary.keys.toList();

  List values() => dictionary.values.toList();

  static const String _base = 'https://rt.data.gov.hk/v2/transport/citybus';

  static const Duration _defaultRoutesTtl = Duration(hours: 24);
  static const Duration _defaultStopsTtl = Duration(hours: 24);

  static const String _routesCachePrefKeyPrefix = 'citybus_routes_cache_json_';
  static const String _stopsCachePrefKey = 'citybus_stops_cache_json';
  static const String _stopsCacheAtPrefKey = 'citybus_stops_cache_at';

  static const String _routeIndexPrefKeyPrefix = 'citybus_route_index_json_';

  static const String _pinnedRoutesKey = 'pinnedCitybusRoutes';
  static const String _pinnedStopsKey = 'pinnedCitybusStops';
  static const String _routeHistoryKey = 'citybusRouteHistory';

  static List<Map>? _routesCache;
  static DateTime? _routesCacheAt;

  static Map<String, Map>? _stopsCache;
  static DateTime? _stopsCacheAt;

  static Map<String, Map<String, dynamic>>? _routeIndex;
  static DateTime? _routeIndexAt;

  static Uri _u(String path) => Uri.parse('$_base/$path');

  static Future<Map> _getJson(Uri url, {Duration timeout = const Duration(seconds: 20)}) async {
    final resp = await http.get(url).timeout(timeout);
    if (resp.statusCode != 200) {
      final snippet = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
      throw Exception('HTTP ${resp.statusCode}: $snippet');
    }
    try {
      final decoded = json.decode(resp.body);
      if (decoded is Map) return decoded;
      throw Exception('Unexpected JSON root type: ${decoded.runtimeType}');
    } on FormatException {
      throw Exception('Invalid JSON from $url');
    }
  }

  static List<Map<dynamic, dynamic>> _expectDataList(Map obj) {
    final data = obj['data'];
    if (data is List) {
      return data.map((e) => Map.from(e as Map)).toList();
    }
    throw Exception('Unexpected payload type for data: ${data.runtimeType}');
  }

  static Map<String, Map> _listToIdMap(List<Map> list, String idKey) {
    final out = <String, Map>{};
    for (final e in list) {
      final id = (e[idKey] ?? '').toString();
      if (id.isEmpty) continue;
      out[id] = Map.from(e);
    }
    return out;
  }

  static String _normalizeCompanyIdForPath(String companyId) => companyId.trim().toLowerCase();

  static String _normalizeCompanyIdForEta(String companyId) => companyId.trim().toUpperCase();

  static String _normalizeDir(String direction) {
    final d = direction.trim().toLowerCase();
    if (d == 'i' || d == 'in' || d == 'inbound') return 'inbound';
    if (d == 'o' || d == 'out' || d == 'outbound') return 'outbound';
    return d;
  }

  static Future<List<Map>> fetchRoutes({
    String companyId = 'ctb',
    Duration ttl = _defaultRoutesTtl,
  }) async {
    if (_routesCache != null && _routesCacheAt != null) {
      if (DateTime.now().difference(_routesCacheAt!) < ttl) return _routesCache!;
    }

    final prefsKey = '$_routesCachePrefKeyPrefix${_normalizeCompanyIdForPath(companyId)}';

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(prefsKey);
      if (cachedJson != null) {
        final decoded = json.decode(cachedJson);
        if (decoded is List) {
          final list = decoded.map((e) => Map.from(e as Map)).toList();
          _routesCache = List<Map>.from(list);
          _routesCacheAt = DateTime.now();
          return _routesCache!;
        }
      }
    } catch (_) {}

    final url = _u('route/${_normalizeCompanyIdForPath(companyId)}');
    final obj = await _getJson(url);
    final routes = _expectDataList(obj);

    _routesCache = routes;
    _routesCacheAt = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, json.encode(routes));
    } catch (_) {}

    return routes;
  }

  static Future<Map<String, Map<String, dynamic>>> buildRouteIndex({
    String companyId = 'ctb',
    Duration ttl = _defaultRoutesTtl,
  }) async {
    if (_routeIndex != null && _routeIndexAt != null) {
      if (DateTime.now().difference(_routeIndexAt!) < ttl) return _routeIndex!;
    }

    final prefsKey = '$_routeIndexPrefKeyPrefix${_normalizeCompanyIdForPath(companyId)}';

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(prefsKey);
      if (cachedJson != null) {
        final decoded = json.decode(cachedJson);
        if (decoded is Map) {
          final idx = decoded.map((k, v) => MapEntry(k.toString(), Map.from(v as Map)));
          _routeIndex = Map<String, Map<String, dynamic>>.from(idx);
          _routeIndexAt = DateTime.now();
          return _routeIndex!;
        }
      }
    } catch (_) {}

    final routes = await fetchRoutes(companyId: companyId, ttl: Duration.zero);

    final out = <String, Map<String, dynamic>>{};
    // ✅ 修正：改用 buildRouteToStopsMap，這會讀取 ctb_route_stops.json
    final routeStopsMap = await buildRouteToStopsMap(companyId: companyId);


    for (final entry in routeStopsMap.entries) {
      final route = entry.key;
      final stops = entry.value;

      // 將停站按方向 (bound) 分組
      final Map<String, List<Map<String, dynamic>>> byBound = {};
      for (final stop in stops) {
        final b = stop['bound']?.toString() ?? stop['dir']?.toString() ?? '';
        if (b.isNotEmpty) {
          byBound.putIfAbsent(b, () => []).add(stop);
        }
      }

      // 為每個方向建立獨立的索引條目
      for (final boundEntry in byBound.entries) {
        final bound = boundEntry.key; // "I" 或 "O"
        final boundStops = boundEntry.value;
        if (boundStops.isEmpty) continue;

        final first = boundStops.first;
        final serviceType = first['servicetype']?.toString() ?? '1';
        
        // 取得起訖點資訊 (從 JSON 欄位中提取)
        final origEn = first['orig_en']?.toString() ?? '';
        final origTc = first['orig_tc']?.toString() ?? '';
        final destEn = first['dest_en']?.toString() ?? '';
        final destTc = first['dest_tc']?.toString() ?? '';

        final uniqueKey = '$route$bound$serviceType'; // ✅ 包含 bound，969I1 與 969O1 會分開
        
        out[uniqueKey] = {
          'route': route,
          'bound': bound,
          'servicetype': serviceType,
          'orig_en': origEn,
          'orig_tc': origTc,
          'dest_en': destEn,
          'dest_tc': destTc,
          'companyid': companyId,
          'search_text': '$route $origEn $origTc $destEn $destTc'.toLowerCase(), // ✅ 確保與 searchRoutes 匹配
        };
      }
    }

    _routeIndex = out;
    _routeIndexAt = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, json.encode(out));
    } catch (_) {}

    return out;
  }

  static Future<List<Map<String, dynamic>>> searchRoutes(
    String query, {
    String companyId = 'ctb',
    int? maxResults,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final idx = await buildRouteIndex(companyId: companyId);
    final matches = idx.values.where((e) {
      final t = (e['search_text'] ?? '').toString();
      return t.contains(q);
    }) .map((e) => Map<String, dynamic>.from(e))
    .toList();

    matches.sort((a, b) {
      final ra = (a['route'] ?? '').toString().toLowerCase();
      final rb = (b['route'] ?? '').toString().toLowerCase();
      if (ra == q && rb != q) return -1;
      if (rb == q && ra != q) return 1;
      if (ra.startsWith(q) && !rb.startsWith(q)) return -1;
      if (rb.startsWith(q) && !ra.startsWith(q)) return 1;
      return 0;
    });

    return maxResults != null ? matches.take(maxResults).toList() : matches;
  }

  static Future<List<Map>> fetchStopsAll({Duration ttl = _defaultStopsTtl}) async {
    final map = await buildStopMap(ttl: ttl);
    return map.values.map((e) => Map.from(e)).toList();
  }

  static Future<Map<String, Map>> buildStopMap({Duration ttl = _defaultStopsTtl}) async {
    if (_stopsCache != null && _stopsCacheAt != null) {
      if (DateTime.now().difference(_stopsCacheAt!) < ttl) return _stopsCache!;
    }

    // Try bundled asset first (packaged with app, most reliable)
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/ctb_stops.json');
      if (raw.isNotEmpty) {
        final parsed = await compute(_parseStopsAsset, raw);
        if (parsed.isNotEmpty) {
          _stopsCache = parsed;
          _stopsCacheAt = DateTime.now();
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_stopsCachePrefKey, json.encode(parsed));
            await prefs.setString(_stopsCacheAtPrefKey, _stopsCacheAt!.toIso8601String());
          } catch (_) {}
          return parsed;
        }
      }
    } catch (_) {}

    // Fallback to app documents prebuilt (written by Regenerate prebuilt data)
    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/ctb_stops.json');
      if (prebuiltFile.existsSync()) {
        final raw = await prebuiltFile.readAsString();
        if (raw.isNotEmpty) {
          final parsed = await compute(_parseStopsAsset, raw);
          if (parsed.isNotEmpty) {
            _stopsCache = parsed;
            _stopsCacheAt = DateTime.now();
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_stopsCachePrefKey, json.encode(parsed));
              await prefs.setString(_stopsCacheAtPrefKey, _stopsCacheAt!.toIso8601String());
            } catch (_) {}
            return parsed;
          }
        }
      }
    } catch (_) {}

    try {
      final obj = await _getJson(_u('stop'));
      final list = _expectDataList(obj);

      final valid = <Map>[];
      for (final s in list) {
        final lat = s['lat'];
        final lng = s['long'];
        if (lat == null || lng == null) continue;
        final latOk = double.tryParse(lat.toString()) != null;
        final lngOk = double.tryParse(lng.toString()) != null;
        if (!latOk || !lngOk) continue;
        valid.add(s);
      }

      final map = _listToIdMap(valid.cast<Map>(), 'stop');
      _stopsCache = map;
      _stopsCacheAt = DateTime.now();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_stopsCachePrefKey, json.encode(map));
        await prefs.setString(_stopsCacheAtPrefKey, _stopsCacheAt!.toIso8601String());
      } catch (_) {}

      return map;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedJson = prefs.getString(_stopsCachePrefKey);
        if (cachedJson != null) {
          final decoded = json.decode(cachedJson);
          if (decoded is Map) {
            final restored = decoded.map((k, v) => MapEntry(k.toString(), Map.from(v as Map)));
            _stopsCache = Map<String, Map>.from(restored);
            _stopsCacheAt = DateTime.now();
            return _stopsCache!;
          }
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Future<Map?> getStopById(String stopId) async {
    final map = await buildStopMap();
    return map[stopId.trim()];
  }

  static Future<List<Map<dynamic, dynamic>>> fetchRouteStops(
    String route,
    String direction, 
    {String companyId = 'ctb'}
  ) async {
    final r = route.trim().toUpperCase();
    final dir = _normalizeDir(direction);
    if (r.isEmpty) throw ArgumentError('route is empty');
    if (dir.isEmpty) throw ArgumentError('direction is empty');

    final url = _u('route-stop/${_normalizeCompanyIdForPath(companyId)}/${Uri.encodeComponent(r)}/${Uri.encodeComponent(dir)}');
    final obj = await _getJson(url);
    return _expectDataList(obj);
  }

  static Future<Map<String, List<Map>>> fetchRouteStopsBothDirections(
    String route, {
    String companyId = 'ctb',
  }) async {
    final r = route.trim().toUpperCase();
    final out = <String, List<Map>>{};
    for (final dir in const ['outbound', 'inbound']) {
      try {
        out[dir] = await fetchRouteStops(r, dir, companyId: companyId);
      } catch (_) {
        out[dir] = <Map>[];
      }
    }
    return out;
  }

  static Future<List<Map>> fetchEta(
    String stopId,
    String route, {
    String companyId = 'ctb',
  }) async {
    final s = stopId.trim();
    final r = route.trim().toUpperCase();
    final co = _normalizeCompanyIdForEta(companyId);

    if (s.isEmpty) throw ArgumentError('stopId is empty');
    if (r.isEmpty) throw ArgumentError('route is empty');

    final url = _u('eta/$co/${Uri.encodeComponent(s)}/${Uri.encodeComponent(r)}');
    final obj = await _getJson(url, timeout: const Duration(seconds: 15));
    return _expectDataList(obj);
  }

  static Future pinRoute(String route, String label, {String companyId = 'ctb'}) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);

    final r = route.trim().toUpperCase();
    final co = _normalizeCompanyIdForEta(companyId);

    pinned.removeWhere((item) => (item is Map) && item['route'] == r && item['co'] == co);

    pinned.add({
      'route': r,
      'co': co,
      'label': label,
      'pinnedAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  static Future<List<Map>> getPinnedRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map.from(e as Map)).toList();
  }

  static Future unpinRoute(String route, {String companyId = 'ctb'}) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedRoutesKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);

    final r = route.trim().toUpperCase();
    final co = _normalizeCompanyIdForEta(companyId);

    pinned.removeWhere((item) => (item is Map) && item['route'] == r && item['co'] == co);
    await prefs.setString(_pinnedRoutesKey, json.encode(pinned));
  }

  static Future pinStop({
    required String route,
    required String stopId,
    required String seq,
    required String stopName,
    String? stopNameEn,
    String? stopNameTc,
    String? latitude,
    String? longitude,
    String? direction,
    String? companyId,
    String? destTc,
    String? destEn,
    String? serviceType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);

    final r = route.trim().toUpperCase();
    final s = stopId.trim();
    final co = companyId != null ? _normalizeCompanyIdForEta(companyId) : 'ctb';

    pinned.removeWhere((item) => (item is Map) && item['route'] == r && item['stopId'] == s && item['seq'] == seq && item['co'] == co);

    pinned.add({
      'route': r,
      'stopId': s,
      'seq': seq,
      'co': co,
      'stopName': stopName,
      'stopNameEn': stopNameEn ?? stopName,
      'stopNameTc': stopNameTc ?? stopName,
      'latitude': latitude,
      'longitude': longitude,
      'direction': direction,
      'destEn': destEn,        // ✅ ADD THIS
      'destTc': destTc,        // ✅ ADD THIS
      'serviceType': serviceType, // ✅ ADD THIS (optional, but good to have)
      'pinnedAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }

  static Future<List<Map>> getPinnedStops() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map.from(e as Map)).toList();
  }

  static Future unpinStop(String route, String stopId, String seq, {String companyId = 'ctb'}) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);

    final r = route.trim().toUpperCase();
    final s = stopId.trim();
    final co = _normalizeCompanyIdForEta(companyId).toLowerCase();

    // ✅ DEBUG: Print what we're trying to remove
    debugPrint('🔍 Trying to unpin: route=$r, stopId=$s, seq=$seq, co=$co');
    
    // ✅ DEBUG: Print all pinned stops
    for (var item in pinned) {
      if (item is Map) {
        debugPrint('📌 Pinned: route=${item['route']}, stopId=${item['stopId']}, seq=${item['seq']}, co=${item['co']}');
      }
    }

    final initialLength = pinned.length;
    pinned.removeWhere((item) => 
      (item is Map) && 
      item['route'] == r && 
      item['stopId'] == s && 
      item['seq'].toString() == seq.toString() &&  // ✅ FIX: Compare as strings
      item['co'] == co
    );
    
    final removed = initialLength - pinned.length;
    debugPrint('✅ Removed $removed stops');

    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }


  static Future addToHistory(String route, String label, {String companyId = 'ctb'}) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List history = json.decode(historyJson);

    final r = route.trim().toUpperCase();
    final co = _normalizeCompanyIdForEta(companyId);

    history.removeWhere((item) => (item is Map) && item['route'] == r && item['co'] == co);

    history.insert(0, {
      'route': r,
      'co': co,
      'label': label,
      'accessedAt': DateTime.now().toIso8601String(),
    });

    if (history.length > 50) {
      history.removeRange(50, history.length);
    }

    await prefs.setString(_routeHistoryKey, json.encode(history));
  }

  static Future<List<Map>> getRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_routeHistoryKey) ?? '[]';
    final List history = json.decode(historyJson);
    return history.map((e) => Map.from(e as Map)).toList();
  }

  static Future clearRouteHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeHistoryKey, '[]');
  }

  /// 🆕 Fetch route status: returns combined route info with all stops
  static Future<Map<String, dynamic>> fetchRouteStatus(String route, {String companyId = 'ctb'}) async {
    final r = route.trim().toUpperCase();
    if (r.isEmpty) throw ArgumentError('route is empty');

    try {
      // Try to fetch both directions in parallel
      final bothDirs = await fetchRouteStopsBothDirections(r, companyId: companyId);
      
      // Flatten into single list with direction metadata
      final allStops = <Map<String, dynamic>>[];
      for (final entry in bothDirs.entries) {
        final dir = entry.key; // 'outbound' or 'inbound'
        final stops = entry.value;
        for (final stop in stops) {
          final enriched = Map<String, dynamic>.from(stop);
          enriched['direction'] = dir;
          allStops.add(enriched);
        }
      }

      return {
        'data': {
          'route': r,
          'stops': allStops,
          'co': _normalizeCompanyIdForEta(companyId),
          'timestamp': DateTime.now().toIso8601String(),
        }
      };
    } catch (e) {
      throw Exception('Failed to fetch route status for $r: $e');
    }
  }

  /// 🆕 Build route→stops mapping from cached/live data
  /// Returns Map<route, List<stops>> for quick lookup
  static Future<Map<String, List<Map<String, dynamic>>>> buildRouteToStopsMap({
    String companyId = 'ctb',
    Duration ttl = _defaultRoutesTtl,
  }) async {
    try {
      // First try bundled asset (packaged with app, most reliable)
      try {
        final raw = await rootBundle.loadString('assets/prebuilt/ctb_route_stops.json');
        if (raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final result = <String, List<Map<String, dynamic>>>{};
            
            for (final entry in decoded.entries) {
              final routeKey = entry.key.toString();
              final value = entry.value;

              // Case A: legacy list-of-entries format
              if (value is List) {
                result[routeKey] = value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                continue;
              }

              // Case B: optimized per-bound structure { "I": { orig_en, orig_tc, dest_en, dest_tc, stops: [...] }, "O": {...} }
              if (value is Map) {
                final routeObj = value as Map;
                final List<Map<String, dynamic>> combined = [];
                
                routeObj.forEach((boundKey, boundVal) {
                  try {
                    final boundObj = boundVal as Map;
                    
                    // ✅ 修正：同時提取起點和終點
                    final origEn = (boundObj['orig_en'] ?? boundObj['origen'] ?? '')?.toString() ?? '';
                    final origTc = (boundObj['orig_tc'] ?? boundObj['origtc'] ?? '')?.toString() ?? '';
                    final destEn = (boundObj['dest_en'] ?? boundObj['desten'] ?? '')?.toString() ?? '';
                    final destTc = (boundObj['dest_tc'] ?? boundObj['desttc'] ?? '')?.toString() ?? '';
                    
                    final stopsList = boundObj['stops'];
                    
                    if (stopsList is List) {
                      for (final rawEntry in stopsList) {
                        try {
                          final entry = Map<String, dynamic>.from(rawEntry as Map);
                          
                          // Inject bound
                          entry['bound'] = boundKey; // 'I' or 'O'
                          
                          // Also preserve original 'dir' field if present
                          if (entry.containsKey('dir')) {
                            final dirValue = entry['dir']?.toString().trim().toUpperCase() ?? '';
                            if (dirValue == 'I' || dirValue == 'O') {
                              entry['bound'] = dirValue;
                            }
                          }
                          
                          entry['direction'] = boundKey == 'I' ? 'inbound' : 'outbound';
                          
                          // ✅ 注入起點和終點（關鍵修正）
                          if (origEn.isNotEmpty) entry['origen'] = origEn;
                          if (origTc.isNotEmpty) entry['origtc'] = origTc;
                          if (destEn.isNotEmpty) entry['desten'] = destEn;
                          if (destTc.isNotEmpty) entry['desttc'] = destTc;
                          
                          // 也保留舊欄位名以相容性
                          if (origEn.isNotEmpty) entry['orig_en'] = origEn;
                          if (origTc.isNotEmpty) entry['orig_tc'] = origTc;
                          if (destEn.isNotEmpty) entry['dest_en'] = destEn;
                          if (destTc.isNotEmpty) entry['dest_tc'] = destTc;
                          
                          combined.add(entry);
                        } catch (_) {}
                      }
                    }
                  } catch (_) {}
                });
                
                if (combined.isNotEmpty) {
                  result[routeKey] = combined;
                }
              }
            }
            
            if (result.isNotEmpty) {
              return result;
            }
          }
        }
      } catch (_) {}

      // Fallback to app documents prebuilt (same logic with orig injection)
      try {
        final doc = await getApplicationDocumentsDirectory();
        final prebuiltFile = File('${doc.path}/prebuilt/ctb_route_stops.json');
        if (prebuiltFile.existsSync()) {
          final raw = await prebuiltFile.readAsString();
          if (raw.isNotEmpty) {
            final decoded = json.decode(raw);
            if (decoded is Map) {
              final result = <String, List<Map<String, dynamic>>>{};
              
              for (final entry in decoded.entries) {
                final routeKey = entry.key.toString();
                final value = entry.value;

                if (value is List) {
                  result[routeKey] = value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                  continue;
                }

                if (value is Map) {
                  final routeObj = value as Map;
                  final List<Map<String, dynamic>> combined = [];
                  
                  routeObj.forEach((boundKey, boundVal) {
                    try {
                      final boundObj = boundVal as Map;
                      
                      // ✅ 提取起點和終點
                      final origEn = (boundObj['orig_en'] ?? boundObj['origen'] ?? '')?.toString() ?? '';
                      final origTc = (boundObj['orig_tc'] ?? boundObj['origtc'] ?? '')?.toString() ?? '';
                      final destEn = (boundObj['dest_en'] ?? boundObj['desten'] ?? '')?.toString() ?? '';
                      final destTc = (boundObj['dest_tc'] ?? boundObj['desttc'] ?? '')?.toString() ?? '';
                      
                      final stopsList = boundObj['stops'];
                      
                      if (stopsList is List) {
                        for (final rawEntry in stopsList) {
                          try {
                            final entry = Map<String, dynamic>.from(rawEntry as Map);
                            entry['bound'] = boundKey;
                            
                            if (entry.containsKey('dir')) {
                              final dirValue = entry['dir']?.toString().trim().toUpperCase() ?? '';
                              if (dirValue == 'I' || dirValue == 'O') {
                                entry['bound'] = dirValue;
                              }
                            }
                            
                            entry['direction'] = boundKey == 'I' ? 'inbound' : 'outbound';
                            
                            // ✅ 注入起訖點
                            if (origEn.isNotEmpty) entry['origen'] = origEn;
                            if (origTc.isNotEmpty) entry['origtc'] = origTc;
                            if (destEn.isNotEmpty) entry['desten'] = destEn;
                            if (destTc.isNotEmpty) entry['desttc'] = destTc;
                            
                            combined.add(entry);
                          } catch (_) {}
                        }
                      }
                    } catch (_) {}
                  });
                  
                  if (combined.isNotEmpty) {
                    result[routeKey] = combined;
                  }
                }
              }
              
              if (result.isNotEmpty) {
                return result;
              }
            }
          }
        }
      } catch (_) {}

      // Fallback to building from live route list (existing code remains unchanged)
      final routes = await fetchRoutes(companyId: companyId, ttl: Duration.zero);
      final out = <String, List<Map<String, dynamic>>>{};
      
      for (final route in routes) {
        final routeNum = (route['route'] ?? '').toString().toUpperCase();
        if (routeNum.isEmpty) continue;
        
        try {
          final bothDirs = await fetchRouteStopsBothDirections(routeNum, companyId: companyId);
          final allStops = <Map<String, dynamic>>[];
          
          for (final entry in bothDirs.entries) {
            final dir = entry.key;
            final stops = entry.value;
            
            for (final stop in stops) {
              final enriched = Map<String, dynamic>.from(stop);
              enriched['direction'] = dir;
              allStops.add(enriched);
            }
          }
          
          out[routeNum] = allStops;
        } catch (_) {
          out[routeNum] = [];
        }
      }
      
      return out;
    } catch (e) {
      throw Exception('Failed to build route→stops map: $e');
    }
  }

  /// 🆕 Fetch ETA for a specific route's service type (route-level ETA)
  /// ⚠️ **PERFORMANCE WARNING**: This function is SLOW for Citybus!
  ///
  /// Unlike KMB which has a dedicated route-level ETA endpoint,
  /// Citybus API requires fetching ETA for EACH stop individually.
  /// For a route with 40 stops, this makes 40 separate API calls!
  ///
  /// Expected time: 40 stops × ~200ms = ~8 seconds
  ///
  /// **Recommendation**: Use [fetchStopEta] for individual stops instead,
  /// or implement caching/rate limiting to prevent UI freezing.
  /// 🆕 Fetch ETA for a specific route's service type (route-level ETA)
  /// ⚠️ **PERFORMANCE WARNING**: This function is SLOW for Citybus!
  static Future<List<Map<String, dynamic>>> fetchRouteEta(
    String route, {
    String? direction,
    String companyId = 'ctb',
  }) async {
    final r = route.trim().toUpperCase();
    if (r.isEmpty) throw ArgumentError('route is empty');

    try {
      final routeMap = await buildRouteToStopsMap(companyId: companyId);
      final stops = routeMap[r] ?? [];
      if (stops.isEmpty) return [];

      String? boundChar;
      if (direction != null) {
        final dirUpper = direction.trim().toUpperCase();
        if (dirUpper.isNotEmpty) {
          final firstChar = dirUpper[0];
          if (firstChar == 'I' || firstChar == 'O') boundChar = firstChar;
        }
      }

      final filteredStops = boundChar != null
          ? stops.where((stop) {
              final stopBound = stop['bound'] ?? stop['dir'] ?? stop['direction'];
              if (stopBound == null) return false;
              final stopBoundStr = stopBound.toString().trim().toUpperCase();
              if (stopBoundStr.isEmpty) return false;
              return stopBoundStr[0] == boundChar;
            }).toList()
          : stops;

      if (filteredStops.isEmpty) return [];

      final allEtas = <Map<String, dynamic>>[];
      
      const int batchSize = 5;  // ← 減少批次大小
      
      for (var i = 0; i < filteredStops.length; i += batchSize) {
        final end = (i + batchSize < filteredStops.length)
            ? i + batchSize
            : filteredStops.length;
        final batchStops = filteredStops.sublist(i, end);

        final batchFutures = <Future<List<Map>>>[];
        for (final stop in batchStops) {
          final stopId = (stop['stop'] ?? '').toString();
          if (stopId.isNotEmpty) {
            batchFutures.add(
              fetchEta(stopId, r, companyId: companyId)
                .timeout(
                  const Duration(seconds: 20),  // ← 增加超時時間
                  onTimeout: () {
                    debugPrint('⚠️ Timeout fetching ETA for stop $stopId on route $r');
                    return [];
                  },
                )
                .catchError((e) {
                  debugPrint('⚠️ Error fetching ETA for stop $stopId on route $r: $e');
                  return [];
                }),
            );
          } else {
            batchFutures.add(Future.value([]));
          }
        }

        try {
          final results = await Future.wait(batchFutures, eagerError: false);
          
          for (int j = 0; j < results.length; j++) {
            final etaList = results[j];
            final stop = batchStops[j];
            
            final stopBound = stop['bound'] ?? stop['dir'] ?? stop['direction'];
            final boundValue = stopBound?.toString().trim().toUpperCase();
            final boundCharValue = (boundValue != null && boundValue.isNotEmpty)
                ? boundValue[0]
                : boundChar;

            for (final eta in etaList) {
              final enrichedEta = Map<String, dynamic>.from(eta);
              
              if (!enrichedEta.containsKey('bound') && boundCharValue != null) {
                enrichedEta['bound'] = boundCharValue;
              }
              
              if (!enrichedEta.containsKey('seq')) {
                final stopSeq = (stop['seq']?.toString() ?? '');
                if (stopSeq.isNotEmpty) enrichedEta['seq'] = stopSeq;
              }
              
              allEtas.add(enrichedEta);
            }
          }
        } catch (e) {
          debugPrint('⚠️ Batch error for route $r: $e');
        }

        if (end < filteredStops.length) {
          await Future.delayed(const Duration(milliseconds: 100));  // ← 增加批次間隔
        }
      }

      return allEtas;
    } catch (e) {
      throw Exception('Failed to fetch route ETA: $e');
    }
  }

  /// 🆕 Discover route variants (directions + service types) from cached data
  /// Discover route variants (directions & service types) from cached data
  static Future<Map<String, List<String>>> discoverRouteVariants(String route) async {
    final r = route.trim().toUpperCase();
    if (r.isEmpty) return {'directions': <String>[], 'serviceTypes': <String>[]};
    
    try {
      // Fetch route stops for both directions
      final bothDirs = await fetchRouteStopsBothDirections(r);
      final directions = <String>{};  // Set for uniqueness
      final serviceTypes = <String>{};  // Set for uniqueness
      
      for (final entry in bothDirs.entries) {
        final dir = entry.key;  // "outbound" or "inbound"
        final stops = entry.value;
        
        // ✅ 修正：如果該方向有停站，就添加對應的 bound
        if (stops.isNotEmpty) {
          // Convert direction name to bound character
          if (dir == 'outbound') {
            directions.add('O');
          } else if (dir == 'inbound') {
            directions.add('I');
          }
        }
        
        // Extract unique service_type values from stops
        for (final stop in stops) {
          // Try multiple possible field names for service type
          final st = stop['service_type']?.toString() ?? 
                    stop['servicetype']?.toString() ?? 
                    stop['serviceType']?.toString() ?? '1';
          if (st.isNotEmpty && st != '1') {
            serviceTypes.add(st);
          }
        }
      }
      
      debugPrint('📍 Discovered variants for $r: Directions=$directions, ServiceTypes=$serviceTypes');
      
      return {
        'directions': directions.toList()..sort(),
        'serviceTypes': serviceTypes.toList()..sort(),
      };
    } catch (e) {
      debugPrint('⚠️ Failed to discover route variants for $r: $e');
      return {'directions': <String>[], 'serviceTypes': <String>[]};
    }
  }

  /// 🆕 Fetch detailed route metadata (origin, destination, etc.)
  static Future<Map<String, dynamic>> fetchRouteWithParams(
    String route,
    String direction, {
    String companyId = 'ctb',
  }) async {
    final r = route.trim().toUpperCase();
    final dir = _normalizeDir(direction);

    if (r.isEmpty) throw ArgumentError('route is empty');
    if (dir.isEmpty) throw ArgumentError('direction is empty');

    try {
      // Fetch route stops for specific direction
      final stops = await fetchRouteStops(r, dir, companyId: companyId);

      // Find the first stop with complete metadata
      Map<String, dynamic>? routeData;
      for (final stop in stops) {
        if ((stop['bound'] ?? '').toString().isNotEmpty &&
            (stop['orig_en'] ?? '').toString().isNotEmpty) {
          routeData = Map<String, dynamic>.from(stop);
          //routeData['service_type'] = serviceType;
          break;
        }
      }

      // If not found in stops, create from route metadata
      if (routeData == null) {
        final routes = await fetchRoutes(companyId: companyId);
        for (final r_data in routes) {
          if ((r_data['route'] ?? '').toString().toUpperCase() == r) {
            routeData = Map<String, dynamic>.from(r_data);
            //routeData['service_type'] = serviceType;
            routeData['bound'] = dir[0].toUpperCase(); // 'O' or 'I'
            break;
          }
        }
      }

      return {
        'data': routeData ?? {
          'route': r,
          'bound': dir[0].toUpperCase(),
          //'service_type': serviceType,
        }
      };
    } catch (e) {
      throw Exception('Failed to fetch route details: $e');
    }
  }

  /// 🆕 Fetch combined route status (stops + ETAs merged)
  static Future<Map<String, dynamic>> fetchCombinedRouteStatus(
    String route,
    {String? serviceType, String companyId = 'ctb'}  // ← Add serviceType
  ) async {
    final r = route.trim().toUpperCase();
    if (r.isEmpty) throw ArgumentError('route is empty');

    try {
      // Fetch route status (all stops)
      final routeStatus = await fetchRouteStatus(r, companyId: companyId);
      final stops = (routeStatus['data']['stops'] as List?) ?? [];
      
      final svc = serviceType ?? '1';
      // Fetch route-level ETA
      final etas = await fetchRouteEta(r, companyId: companyId);

      // Merge: attach ETA list to each stop
      final mergedStops = <Map<String, dynamic>>[];
      for (final stop in stops) {
        final enriched = Map<String, dynamic>.from(stop as Map);
        final stopId = enriched['stop']?.toString() ?? '';

        // Find ETAs for this stop
        final stopEtas = etas
            .where((e) => (e['stop'] ?? '').toString() == stopId)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        enriched['etas'] = stopEtas;
        mergedStops.add(enriched);
      }

      return {
        'data': {
          'route': r,
          'stops': mergedStops,
          'routeEta': etas,
          'co': _normalizeCompanyIdForEta(companyId),
          'timestamp': DateTime.now().toIso8601String(),
        }
      };
    } catch (e) {
      throw Exception('Failed to fetch combined route status: $e');
    }
  }

  // In-memory cache for stop -> routes mapping
  static Map<String, List<String>>? _stopToRoutesCache;
  static DateTime? _stopToRoutesCacheAt;

  /// Build and cache a map of stopId -> list of routes that serve the stop.
  /// TTL default 24 hours.
  /// Uses ctb_stop_routes.json if available for faster loading.
  static Future<Map<String, List<String>>> buildStopToRoutesMap({
    String companyId = 'ctb',
    Duration ttl = _defaultRoutesTtl,
  }) async {
    if (_stopToRoutesCache != null && _stopToRoutesCacheAt != null) {
      if (DateTime.now().difference(_stopToRoutesCacheAt!) < ttl) {
        return _stopToRoutesCache!;
      }
    }

    // Try bundled asset first (packaged with app, most reliable)
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/ctb_stop_routes.json');
      if (raw.isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is List) {
          final result = <String, List<String>>{};
          for (final item in decoded) {
            if (item is Map) {
              final stopId = (item['stop'] ?? '').toString();
              final routes = item['routes'];
              if (stopId.isNotEmpty && routes is List) {
                result[stopId] = routes.map((r) => r.toString()).toList();
              }
            }
          }
          if (result.isNotEmpty) {
            _stopToRoutesCache = result;
            _stopToRoutesCacheAt = DateTime.now();
            return result;
          }
        }
      }
    } catch (_) {}

    // Fallback to app documents prebuilt
    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/ctb_stop_routes.json');
      if (prebuiltFile.existsSync()) {
        final raw = await prebuiltFile.readAsString();
        if (raw.isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is List) {
            final result = <String, List<String>>{};
            for (final item in decoded) {
              if (item is Map) {
                final stopId = (item['stop'] ?? '').toString();
                final routes = item['routes'];
                if (stopId.isNotEmpty && routes is List) {
                  result[stopId] = routes.map((r) => r.toString()).toList();
                }
              }
            }
            if (result.isNotEmpty) {
              _stopToRoutesCache = result;
              _stopToRoutesCacheAt = DateTime.now();
              return result;
            }
          }
        }
      }
    } catch (_) {}

    // Fallback: build from route->stops map (slower but works)
    final routeMap = await buildRouteToStopsMap(companyId: companyId);
    final Map<String, List<String>> out = {};
    routeMap.forEach((route, entries) {
      for (final e in entries) {
        final sid = (e['stop'] ?? '').toString();
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

  /// 🆕 Fetch ETA for a specific stop (alias for fetchEta with optional route)
  static Future<List<Map<String, dynamic>>> fetchStopEta(
    String stopId, {
    String? route,
    String companyId = 'ctb',
  }) async {
    final s = stopId.trim();
    if (s.isEmpty) throw ArgumentError('stopId is empty');

    try {
      // If route provided, use it directly (faster)
      if (route != null && route.isNotEmpty) {
        final r = route.trim().toUpperCase();
        return (await fetchEta(s, r, companyId: companyId))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // Otherwise, use optimized stop->routes map
      final routesForStop = await getRoutesForStop(s);

      if (routesForStop.isEmpty) return [];

      // Fetch ETA from first route (usually enough)
      return (await fetchEta(s, routesForStop.first, companyId: companyId))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch stop ETA: $e');
    }
  }

  /// 🆕 Get setting: use Route API (fresh) vs cached data
  static Future<bool> getUseRouteApiSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('citybus_use_route_api') ?? false; // Default: use cached
    } catch (_) {
      return false;
    }
  }

  /// 🆕 Set preference: use Route API or cached data
  static Future<void> setUseRouteApiSetting(bool useApi) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('citybus_use_route_api', useApi);
    } catch (_) {}
  }

  static Future<bool> requestStoragePermission() async {
    if (await Permission.storage.isGranted) return true;
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  static Future<SaveResult> saveRequestJsonToFile(String filename, dynamic jsonObj) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory('${dir.path}/citybus_saved_requests');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final f = File('${outDir.path}/$filename.json');
      await f.writeAsString(json.encode(jsonObj));
      return SaveResult(path: f.path);
    } catch (e) {
      return SaveResult(error: e.toString());
    }
  }

  static Future<dynamic> loadRequestJsonFromFile(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/citybus_saved_requests/$filename.json');
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> listSavedRequestFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/citybus_saved_requests');
    if (!outDir.existsSync()) return [];
    final files = outDir.listSync().whereType<File>().toList();
    return files.map((f) => f.uri.pathSegments.last).toList();
  }

  static Future<bool> deleteSavedRequestFile(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/citybus_saved_requests/$filename');
      if (!f.existsSync()) return false;
      await f.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<PrebuildResult> writePrebuiltStopsToDocuments({Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final obj = await _getJson(_u('stop'), timeout: timeout);
      final list = _expectDataList(obj);
      final map = _listToIdMap(list, 'stop');

      Directory docDir;
      try {
        docDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docDir = Directory.systemTemp.createTempSync('citybus_app_docs');
      }

      final outDir = Directory('${docDir.path}/prebuilt');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final outFile = File('${outDir.path}/citybus_stops.json');
      await _writeAtomicFile(outFile, utf8.encode(json.encode(map)));

      _stopsCache = null;
      _stopsCacheAt = null;

      return PrebuildResult(ok: true);
    } catch (e) {
      return PrebuildResult(ok: false, error: e.toString());
    }
  }

  static Future<void> _writeAtomicFile(File outFile, List<int> bytes) async {
    final tmp = File('${outFile.path}.tmp');
    if (tmp.existsSync()) await tmp.delete();
    await tmp.create(recursive: true);
    await tmp.writeAsBytes(bytes, flush: true);
    if (outFile.existsSync()) await outFile.delete();
    await tmp.rename(outFile.path);
  }
}

class SaveResult {
  final String? path;
  final String? error;

  SaveResult({this.path, this.error});

  bool get ok => path != null && (error == null || error!.isEmpty);

  @override
  String toString() => ok ? 'Success: $path' : 'Error: $error';
}

class PrebuildResult {
  final bool ok;
  final String? error;

  PrebuildResult({required this.ok, this.error});

  @override
  String toString() => ok ? 'Success' : 'Error: $error';
}

Map<String, Map> _parseStopsAsset(String raw) {
  final decoded = json.decode(raw);
  if (decoded is Map) {
    final payload = decoded.containsKey('data') ? decoded['data'] : decoded;
    if (payload is List) {
      final out = <String, Map>{};
      for (final s in payload) {
        final m = Map.from(s as Map);
        final id = (m['stop'] ?? '').toString();
        if (id.isEmpty) continue;
        out[id] = m;
      }
      return out;
    }
    if (payload is Map) {
      return payload.map((k, v) => MapEntry(k.toString(), Map.from(v as Map)));
    }
    return <String, Map>{};
  }
  return <String, Map>{};
}

final Map citybusDictionary = {};
final Citybus citybus = Citybus(citybusDictionary);
