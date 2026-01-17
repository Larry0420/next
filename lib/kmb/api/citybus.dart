import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
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

  static Map<String, Map>? _routeIndex;
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

  static List<Map> _expectDataList(Map obj) {
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

  static Future<Map<String, Map>> buildRouteIndex({
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
          _routeIndex = Map<String, Map>.from(idx);
          _routeIndexAt = DateTime.now();
          return _routeIndex!;
        }
      }
    } catch (_) {}

    final routes = await fetchRoutes(companyId: companyId, ttl: Duration.zero);

    final out = <String, Map>{};
    for (final r in routes) {
      final route = (r['route'] ?? '').toString().toUpperCase();
      if (route.isEmpty) continue;

      final origEn = (r['orig_en'] ?? '').toString();
      final origTc = (r['orig_tc'] ?? '').toString();
      final origSc = (r['orig_sc'] ?? '').toString();
      final destEn = (r['dest_en'] ?? '').toString();
      final destTc = (r['dest_tc'] ?? '').toString();
      final destSc = (r['dest_sc'] ?? '').toString();

      out[route] = {
        'route': route,
        'orig_en': origEn,
        'orig_tc': origTc,
        'orig_sc': origSc,
        'dest_en': destEn,
        'dest_tc': destTc,
        'dest_sc': destSc,
        'data_timestamp': (r['data_timestamp'] ?? '').toString(),
        'co': _normalizeCompanyIdForEta(companyId),
        'search_text': [
          route,
          origEn,
          origTc,
          origSc,
          destEn,
          destTc,
          destSc,
        ].join(' ').toLowerCase(),
      };
    }

    _routeIndex = out;
    _routeIndexAt = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, json.encode(out));
    } catch (_) {}

    return out;
  }

  static Future<List<Map>> searchRoutes(
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
    }).toList();

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

    try {
      final doc = await getApplicationDocumentsDirectory();
      final prebuiltFile = File('${doc.path}/prebuilt/citybus_stops.json');
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
      final raw = await rootBundle.loadString('assets/prebuilt/citybus_stops.json');
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

  static Future<List<Map>> fetchRouteStops(
    String route,
    String direction, {
    String companyId = 'ctb',
  }) async {
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
    String companyId = 'CTB',
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

  static Future pinRoute(String route, String label, {String companyId = 'CTB'}) async {
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

  static Future unpinRoute(String route, {String companyId = 'CTB'}) async {
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);

    final r = route.trim().toUpperCase();
    final s = stopId.trim();
    final co = companyId != null ? _normalizeCompanyIdForEta(companyId) : 'CTB';

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

  static Future unpinStop(String route, String stopId, String seq, {String companyId = 'CTB'}) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_pinnedStopsKey) ?? '[]';
    final List pinned = json.decode(pinnedJson);

    final r = route.trim().toUpperCase();
    final s = stopId.trim();
    final co = _normalizeCompanyIdForEta(companyId);

    pinned.removeWhere((item) => (item is Map) && item['route'] == r && item['stopId'] == s && item['seq'] == seq && item['co'] == co);
    await prefs.setString(_pinnedStopsKey, json.encode(pinned));
  }

  static Future addToHistory(String route, String label, {String companyId = 'CTB'}) async {
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
