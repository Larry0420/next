import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UnifiedPinnedStorage {
  static const String _unifiedPinnedRoutesKey = 'unifiedPinnedRoutes';
  static const String _unifiedPinnedStopsKey = 'unifiedPinnedStops';

  static String _normCo(String value) => value.trim().toLowerCase();
  static String _normRoute(String value) => value.trim().toUpperCase();
  static String _normStopId(String value) => value.trim();
  static String _normSeq(String value) => value.toString().trim();

  static Future<List<Map<String, dynamic>>> getPinnedRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_unifiedPinnedRoutesKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<List<Map<String, dynamic>>> getPinnedStops() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedJson = prefs.getString(_unifiedPinnedStopsKey) ?? '[]';
    final List<dynamic> pinned = json.decode(pinnedJson);
    return pinned.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> pinRoute({
    required String company,
    required String route,
    required String label,
    String? bound,
    String? serviceType,
    String? initialRouteId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = await getPinnedRoutes();

    final co = _normCo(company);
    final r = _normRoute(route);
    final d = (bound ?? '').trim();
    final st = (serviceType ?? '1').trim();
    final rid = (initialRouteId ?? '').trim();
    pinned.removeWhere((item) {
      return _normCo(item['co']?.toString() ?? '') == co &&
          _normRoute(item['route']?.toString() ?? '') == r &&
          (item['direction']?.toString().trim() ?? '') == d &&
          (item['serviceType']?.toString().trim() ?? '1') == st &&
          (item['initialRouteId']?.toString().trim() ?? '') == rid;
    });

    pinned.add({
      'source': 'unified',
      'co': co,
      'route': r,
      'direction': bound,
      'serviceType': st,
      'label': label,
      'initialRouteId': initialRouteId,
      'pinnedAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_unifiedPinnedRoutesKey, json.encode(pinned));
  }

  static Future<void> unpinRoute({
    required String company,
    required String route,
    String? bound,
    String? serviceType,
    String? initialRouteId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = await getPinnedRoutes();

    final co = _normCo(company);
    final r = _normRoute(route);
    final d = (bound ?? '').trim();
    final st = (serviceType ?? '1').trim();
    final rid = (initialRouteId ?? '').trim();
    pinned.removeWhere((item) {
      return _normCo(item['co']?.toString() ?? '') == co &&
          _normRoute(item['route']?.toString() ?? '') == r &&
          (item['direction']?.toString().trim() ?? '') == d &&
          (item['serviceType']?.toString().trim() ?? '1') == st &&
          (item['initialRouteId']?.toString().trim() ?? '') == rid;
    });

    await prefs.setString(_unifiedPinnedRoutesKey, json.encode(pinned));
  }

  static Future<void> pinStop({
    required String company,
    required String route,
    required String stopId,
    required String seq,
    required String stopName,
    String? stopNameEn,
    String? stopNameTc,
    String? direction,
    String? serviceType,
    String? initialRouteId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = await getPinnedStops();

    final co = _normCo(company);
    final r = _normRoute(route);
    final sid = _normStopId(stopId);
    final q = _normSeq(seq);
    pinned.removeWhere((item) {
      return _normCo(item['co']?.toString() ?? '') == co &&
          _normRoute(item['route']?.toString() ?? '') == r &&
          _normStopId(item['stopId']?.toString() ?? '') == sid &&
          _normSeq(item['seq']?.toString() ?? '') == q;
    });

    pinned.add({
      'source': 'unified',
      'co': co,
      'route': r,
      'stopId': sid,
      'seq': q,
      'stopName': stopName,
      'stopNameEn': stopNameEn ?? stopName,
      'stopNameTc': stopNameTc ?? stopName,
      'direction': direction,
      'serviceType': serviceType ?? '1',
      'initialRouteId': initialRouteId,
      'pinnedAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_unifiedPinnedStopsKey, json.encode(pinned));
  }

  static Future<void> unpinStop({
    required String company,
    required String route,
    required String stopId,
    required String seq,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = await getPinnedStops();

    final co = _normCo(company);
    final r = _normRoute(route);
    final sid = _normStopId(stopId);
    final q = _normSeq(seq);
    pinned.removeWhere((item) {
      return _normCo(item['co']?.toString() ?? '') == co &&
          _normRoute(item['route']?.toString() ?? '') == r &&
          _normStopId(item['stopId']?.toString() ?? '') == sid &&
          _normSeq(item['seq']?.toString() ?? '') == q;
    });

    await prefs.setString(_unifiedPinnedStopsKey, json.encode(pinned));
  }
}
