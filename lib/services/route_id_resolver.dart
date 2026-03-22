// route_id_resolver.dart
// Route ID 解析器 - 將 hkbus_db 的 route ID 映射到各公司 API 所需的格式
//
// hkbus_db routeId 格式: "101+1+KENNEDY TOWN+KWUN TONG"
// - 部分 0: route number (如 "101")
// - 部分 1: service type (如 "1")
// - 部分 2: origin (如 "KENNEDY TOWN")
// - 部分 3: destination (如 "KWUN TONG")
//
// 各公司 API 需要的格式：
// - KMB: route number (如 "101")
// - CTB: route number (如 "969")
// - NLB: routeId string (如 "2")
// - GMB: route_id int (如 2000410), route_code string (如 "69")

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../kmb/api/gmb.dart';

/// 解析後的路線 ID 信息
class ResolvedRouteIds {
  final String routeNumber;
  final String? serviceType;
  final String? origin;
  final String? destination;

  // KMB
  final String? kmbRouteId; // 直接使用 route number

  // CTB
  final String? ctbRouteId; // 直接使用 route number

  // NLB
  final String? nlbRouteId; // 需要從預構建數據查找

  // GMB
  final int? gmbRouteId; // 需要從預構建數據查找
  final String? gmbRouteCode; // 如 "69"
  final String? gmbRegion; // HKI/KLN/NT

  ResolvedRouteIds({
    required this.routeNumber,
    this.serviceType,
    this.origin,
    this.destination,
    this.kmbRouteId,
    this.ctbRouteId,
    this.nlbRouteId,
    this.gmbRouteId,
    this.gmbRouteCode,
    this.gmbRegion,
  });

  @override
  String toString() {
    return 'ResolvedRouteIds(route: $routeNumber, nlb: $nlbRouteId, gmb: $gmbRouteId)';
  }
}

/// 站點索引條目
class StopIndexEntry {
  final String stopId;
  final String? nlbStopId;
  final String? gmbStopId;
  final String? kmbStopId;
  final String? ctbStopId;

  StopIndexEntry({
    required this.stopId,
    this.nlbStopId,
    this.gmbStopId,
    this.kmbStopId,
    this.ctbStopId,
  });
}

/// Route ID 解析器
class RouteIdResolver {
  // 單例模式
  static final RouteIdResolver _instance = RouteIdResolver._internal();
  factory RouteIdResolver() => _instance;
  RouteIdResolver._internal();

  // 預構建數據緩存
  Map<String, dynamic>? _nlbRouteStopsCache;
  Map<String, dynamic>? _gmbRouteStopsCache;
  Map<String, dynamic>? _gmbRouteIndexCache; // route_code -> route_id mapping
  bool _isLoading = false;

  // ===========================================================================
  // 公共 API
  // ===========================================================================

  /// 初始化解析器（加載預構建數據）
  Future<void> initialize() async {
    if (_isLoading) return;
    if (_nlbRouteStopsCache != null && _gmbRouteStopsCache != null) return;

    _isLoading = true;
    try {
      await Future.wait([
        _loadNlbRouteStops(),
        _loadGmbRouteStops(),
      ]);
    } finally {
      _isLoading = false;
    }
  }

  /// 從 hkbus_db routeId 解析各公司的 route ID
  ///
  /// 參數：
  /// - hkbusRouteId: 如 "101+1+KENNEDY TOWN+KWUN TONG"
  /// - routeNumber: 路線號碼（如 "101"）
  /// - companies: 運營公司列表（如 ["kmb", "ctb"]）
  Future<ResolvedRouteIds> resolveRouteIds({
    required String hkbusRouteId,
    required String routeNumber,
    required List<String> companies,
  }) async {
    await initialize();

    // 解析 hkbusRouteId
    final parts = hkbusRouteId.split('+');
    final serviceType = parts.length > 1 ? parts[1] : '1';
    final origin = parts.length > 2 ? parts[2] : null;
    final destination = parts.length > 3 ? parts[3] : null;

    // 解析各公司 ID
    String? nlbRouteId;
    int? gmbRouteId;
    String? gmbRouteCode;
    String? gmbRegion;

    if (companies.any((c) => c.toLowerCase() == 'nlb')) {
      nlbRouteId = await _resolveNlbRouteId(routeNumber);
    }

    if (companies.any((c) => c.toLowerCase() == 'gmb' || c.toLowerCase() == 'greenminibus')) {
      final gmbInfo = await _resolveGmbRouteId(routeNumber);
      gmbRouteId = gmbInfo?['route_id'] as int?;
      gmbRouteCode = gmbInfo?['route_code'] as String?;
      gmbRegion = gmbInfo?['region'] as String?;
    }

    return ResolvedRouteIds(
      routeNumber: routeNumber,
      serviceType: serviceType,
      origin: origin,
      destination: destination,
      kmbRouteId: routeNumber, // KMB 直接使用路線號碼
      ctbRouteId: routeNumber, // CTB 直接使用路線號碼
      nlbRouteId: nlbRouteId,
      gmbRouteId: gmbRouteId,
      gmbRouteCode: gmbRouteCode,
      gmbRegion: gmbRegion,
    );
  }

  /// 從 route number 解析 NLB routeId
  Future<String?> resolveNlbRouteId(String routeNumber) async {
    await initialize();
    return _resolveNlbRouteId(routeNumber);
  }

  /// 從 route number 解析 GMB routeId
  Future<Map<String, dynamic>?> resolveGmbRouteId(String routeNumber) async {
    await initialize();
    final result = await _resolveGmbRouteId(routeNumber);
    return result;
  }

  /// 獲取 NLB 路線的所有變體
  Future<List<Map<String, dynamic>>> getNlbRouteVariants(String routeNumber) async {
    await initialize();

    if (_nlbRouteStopsCache == null) return [];

    final routeData = _nlbRouteStopsCache![routeNumber];
    if (routeData == null) return [];

    if (routeData is Map) {
      return routeData.entries.map((e) {
        return {
          'routeId': e.key,
          ...e.value as Map<String, dynamic>,
        };
      }).toList();
    }

    return [];
  }

  /// 獲取 GMB 路線的所有變體
  Future<List<Map<String, dynamic>>> getGmbRouteVariants(String routeNumber) async {
    await initialize();

    if (_gmbRouteStopsCache == null) return [];

    final normalizedRoute = routeNumber.toUpperCase().trim();
    final variants = <Map<String, dynamic>>[];

    // 查找匹配的 routeCode
    if (_gmbRouteStopsCache!.containsKey(normalizedRoute)) {
      final routeData = _gmbRouteStopsCache![normalizedRoute];
      if (routeData is Map && routeData.containsKey('variants')) {
        final variantList = routeData['variants'];
        if (variantList is List) {
          for (final variant in variantList) {
            if (variant is Map) {
              variants.add({
                'route_id': variant['routeId'],
                'route_code': normalizedRoute,
                'region': variant['region'],
                'route_seq': variant['routeSeq'],
                'orig_tc': variant['orig_tc'],
                'orig_en': variant['orig_en'],
                'dest_tc': variant['dest_tc'],
                'dest_en': variant['dest_en'],
                'stops': variant['stops'],
              });
            }
          }
        }
      }
    }

    debugPrint('🔍 getGmbRouteVariants($routeNumber): found ${variants.length} variants');
    return variants;
  }

  /// 查找站點的跨公司映射
  ///
  /// 輸入一家公司的 stopId，查找其他公司的對應 stopId
  Future<Map<String, String?>> resolveCrossCompanyStopIds(
    String company,
    String stopId,
  ) async {
    final result = <String, String?>{
      'kmb': null,
      'ctb': null,
      'nlb': null,
      'gmb': null,
    };

    result[company.toLowerCase()] = stopId;

    // TODO: 從 stopMap 數據查找跨公司映射
    // 這需要訪問 hkbus_db_provider 的 stopMap 數據

    return result;
  }

  // ===========================================================================
  // 私有方法 - 數據加載
  // ===========================================================================

  /// 加載 NLB route-stops 預構建數據
  Future<void> _loadNlbRouteStops() async {
    if (_nlbRouteStopsCache != null) return;

    // 1. 嘗試從 App Documents 加載
    try {
      final doc = await getApplicationDocumentsDirectory();
      final file = File('${doc.path}/prebuilt/nlb_route_stops.json');
      if (file.existsSync()) {
        final raw = await file.readAsString();
        _nlbRouteStopsCache = json.decode(raw) as Map<String, dynamic>;
        debugPrint('📦 NLB route-stops loaded from documents');
        return;
      }
    } catch (e) {
      debugPrint('Error loading NLB route-stops from documents: $e');
    }

    // 2. 嘗試從 bundled assets 加載
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/nlb_route_stops.json');
      _nlbRouteStopsCache = json.decode(raw) as Map<String, dynamic>;
      debugPrint('📦 NLB route-stops loaded from assets');
      return;
    } catch (e) {
      debugPrint('Error loading NLB route-stops from assets: $e');
    }

    // 3. 初始化為空
    _nlbRouteStopsCache = {};
  }

  /// 加載 GMB route-stops 預構建數據
  Future<void> _loadGmbRouteStops() async {
    if (_gmbRouteStopsCache != null) return;

    // 1. 嘗試從 App Documents 加載
    try {
      final doc = await getApplicationDocumentsDirectory();
      final file = File('${doc.path}/prebuilt/gmb_route_stops.json');
      if (file.existsSync()) {
        final raw = await file.readAsString();
        _gmbRouteStopsCache = json.decode(raw) as Map<String, dynamic>;
        debugPrint('📦 GMB route-stops loaded from documents');
        return;
      }
    } catch (e) {
      debugPrint('Error loading GMB route-stops from documents: $e');
    }

    // 2. 嘗試從 bundled assets 加載
    try {
      final raw = await rootBundle.loadString('assets/prebuilt/gmb_route_stops.json');
      _gmbRouteStopsCache = json.decode(raw) as Map<String, dynamic>;
      debugPrint('📦 GMB route-stops loaded from assets');
      return;
    } catch (e) {
      debugPrint('Error loading GMB route-stops from assets: $e');
    }

    // 3. 初始化為空
    _gmbRouteStopsCache = {};
  }

  // ===========================================================================
  // 私有方法 - ID 解析
  // ===========================================================================

  /// 解析 NLB routeId
  ///
  /// 從 NLB route-stops 數據中查找 route number 對應的 routeId
  Future<String?> _resolveNlbRouteId(String routeNumber) async {
    if (_nlbRouteStopsCache == null) return null;

    final routeData = _nlbRouteStopsCache![routeNumber];
    if (routeData == null) {
      debugPrint('⚠️ NLB route not found: $routeNumber');
      return null;
    }

    // NLB routeData 格式: { "routeId": { "orig_en": ..., "stops": [...] }, ... }
    if (routeData is Map) {
      // 返回第一個變體的 routeId（通常只有一個）
      final firstKey = routeData.keys.firstOrNull?.toString();
      if (firstKey != null) {
        debugPrint('✅ NLB routeId resolved: $routeNumber -> $firstKey');
        return firstKey;
      }
    }

    return null;
  }

  /// 解析 GMB routeId
  ///
  /// 從 GMB route-stops 數據中查找 route number 對應的 route_id
  Future<Map<String, dynamic>?> _resolveGmbRouteId(String routeNumber) async {
    // 策略 1：從 prebuilt cache 查找（最快）
    if (_gmbRouteIndexCache == null) {
      await _buildGmbRouteIndex();
    }

    final normalizedRoute = routeNumber.toUpperCase().trim();
    final entry = _gmbRouteIndexCache?[normalizedRoute];

    if (entry != null) {
      debugPrint('✅ GMB routeId resolved from cache: $routeNumber -> ${entry['route_id']}');
      return {
        'route_id': entry['route_id'],
        'route_code': entry['route_code'],
        'region': entry['region'],
      };
    }

    // 策略 2：prebuilt 找不到時，嘗試用 GMB API live 查詢
    debugPrint('⚠️ GMB route not in prebuilt cache, trying live API: $routeNumber');
    try {
      for (final region in ['HKI', 'KLN', 'NT']) {
        try {
          final routes = await GMB.fetchRouteInfo(region, routeNumber);
          if (routes.isNotEmpty) {
            final first = routes.first;
            final routeId = first['route_id'] is int
                ? first['route_id'] as int
                : int.tryParse(first['route_id']?.toString() ?? '');

            if (routeId != null) {
              debugPrint('✅ GMB routeId resolved via live API: $routeNumber -> $routeId ($region)');
              // 寫入 index cache 備用
              _gmbRouteIndexCache ??= {};
              _gmbRouteIndexCache![normalizedRoute] = {
                'route_id': routeId,
                'route_code': routeNumber,
                'region': region,
              };
              return {
                'route_id': routeId,
                'route_code': routeNumber,
                'region': region,
              };
            }
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('❌ GMB live API resolve failed: $e');
    }

    debugPrint('❌ GMB route not found anywhere: $routeNumber');
    return null;
  }

  /// 構建 GMB 路線索引
  ///
  /// 將 route_code 映射到 route_id
  Future<void> _buildGmbRouteIndex() async {
    if (_gmbRouteStopsCache == null) return;

    _gmbRouteIndexCache = {};

    for (final regionEntry in _gmbRouteStopsCache!.entries) {
      final region = regionEntry.key; // HKI, KLN, NT
      final routes = regionEntry.value;

      if (routes is! Map) continue;

      for (final routeEntry in routes.entries) {
        final routeCode = routeEntry.key.toString().toUpperCase(); // "69"
        final routeData = routeEntry.value;

        if (routeData is! Map) continue;

        final routeId = routeData['route_id'];
        if (routeId == null) continue;

        // 存儲索引信息
        _gmbRouteIndexCache![routeCode] = {
          'route_id': routeId is int ? routeId : int.tryParse(routeId.toString()),
          'route_code': routeCode,
          'region': region,
          'data': routeData,
        };
      }
    }

    debugPrint('📊 GMB route index built: ${_gmbRouteIndexCache!.length} routes');
  }

  // ===========================================================================
  // 工具方法
  // ===========================================================================

  /// 清除所有緩存
  void clearCache() {
    _nlbRouteStopsCache = null;
    _gmbRouteStopsCache = null;
    _gmbRouteIndexCache = null;
    debugPrint('🗑️ RouteIdResolver cache cleared');
  }

  /// 獲取緩存統計
  Map<String, dynamic> getCacheStats() {
    return {
      'nlb_routes_loaded': _nlbRouteStopsCache?.length ?? 0,
      'gmb_routes_loaded': _gmbRouteStopsCache?.length ?? 0,
      'gmb_index_built': _gmbRouteIndexCache?.length ?? 0,
    };
  }
}

/// 便捷函數：解析 route IDs
Future<ResolvedRouteIds> resolveRouteIds({
  required String hkbusRouteId,
  required String routeNumber,
  required List<String> companies,
}) async {
  return RouteIdResolver().resolveRouteIds(
    hkbusRouteId: hkbusRouteId,
    routeNumber: routeNumber,
    companies: companies,
  );
}
