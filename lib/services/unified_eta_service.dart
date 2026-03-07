// unified_eta_service.dart
// 統一 ETA 服務 - 處理所有公司 (KMB/CTB/NLB/GMB) 的到站時間獲取
//
// 處理的數據類型：
// - Route: 不同公司的 route ID 格式（KMB=route number, CTB=route number, NLB=routeId string, GMB=route_id int）
// - Route-Stops: 不同端點和參數格式
// - Stops: 不同 stop ID 格式（KMB=16-char hex, CTB=6-digit, NLB=string int, GMB=int）
// - Stop-Routes: 獲取站點服務的所有路線
// - ETA: 不同響應格式統一轉換

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kmb/api/kmb.dart';
import '../kmb/api/citybus.dart';
import '../kmb/api/nlb.dart';
import '../kmb/api/gmb.dart';

/// 統一 ETA 數據模型
/// 所有公司的 ETA 數據都會被轉換為此格式
class UnifiedEta {
  final String company;
  final DateTime eta;
  final int? diffMinutes; // 相對分鐘數（GMB 直接提供，其他計算）
  final int sequence;
  final String? remarkTc;
  final String? remarkEn;
  final String? remarkSc;
  final bool isRealtime; // 是否 GPS 實時數據
  final bool isWheelchairAccessible; // 輪椅可達（僅 NLB 提供）
  final String? routeVariant; // 路線變體描述（僅 NLB 提供）

  UnifiedEta({
    required this.company,
    required this.eta,
    this.diffMinutes,
    required this.sequence,
    this.remarkTc,
    this.remarkEn,
    this.remarkSc,
    this.isRealtime = true,
    this.isWheelchairAccessible = false,
    this.routeVariant,
  });

  /// 獲取相對分鐘數（如果沒有預設值，則計算）
  int get relativeMinutes {
    if (diffMinutes != null) return diffMinutes!;
    final diff = eta.difference(DateTime.now());
    return diff.inMinutes;
  }

  /// 格式化顯示（相對時間 + 絕對時間）
  String formatDisplay(bool isEnglish) {
    final abs = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
    final mins = relativeMinutes;

    if (mins < 1 && mins >= 0) {
      return isEnglish ? 'Due ($abs)' : '即將到達 ($abs)';
    } else if (mins < 0) {
      return isEnglish ? 'Departed' : '已離開';
    } else if (mins < 60) {
      return isEnglish ? '$mins min ($abs)' : '$mins分鐘 ($abs)';
    } else {
      final h = mins ~/ 60;
      final m = mins % 60;
      return isEnglish
          ? '${h}h${m > 0 ? ' ${m}m' : ''} ($abs)'
          : '$h小時${m > 0 ? '$m分' : ''} ($abs)';
    }
  }

  @override
  String toString() {
    return 'UnifiedEta(company: $company, eta: $eta, seq: $sequence, mins: $relativeMinutes)';
  }
}

/// ETA 緩存條目
class _EtaCacheEntry {
  final List<UnifiedEta> etas;
  final DateTime cachedAt;
  final Duration ttl;

  _EtaCacheEntry(this.etas, this.cachedAt, this.ttl);

  bool get isValid => DateTime.now().difference(cachedAt) < ttl;
}

/// 路線上下文信息
/// 用於傳遞路線的完整上下文，包括各公司特定的 ID
class RouteContext {
  final String routeNumber;
  final String? bound; // 'I' or 'O' for KMB/CTB
  final String? serviceType; // for KMB
  final String? nlbRouteId; // NLB specific
  final int? gmbRouteId; // GMB specific
  final String? gmbRegion; // GMB region (HKI/KLN/NT)
  final int? gmbRouteSeq; // GMB route sequence (1 or 2)

  RouteContext({
    required this.routeNumber,
    this.bound,
    this.serviceType = '1',
    this.nlbRouteId,
    this.gmbRouteId,
    this.gmbRegion,
    this.gmbRouteSeq = 1,
  });

  @override
  String toString() {
    return 'RouteContext(route: $routeNumber, bound: $bound, svc: $serviceType, nlb: $nlbRouteId, gmb: $gmbRouteId)';
  }
}

/// 統一 ETA 服務
class UnifiedEtaService {
  // 單例模式
  static final UnifiedEtaService _instance = UnifiedEtaService._internal();
  factory UnifiedEtaService() => _instance;
  UnifiedEtaService._internal();

  // 內存緩存
  final Map<String, _EtaCacheEntry> _etaCache = {};

  // 默認緩存時間（1 分鐘，ETA 數據變化較快）
  static const Duration _defaultCacheTtl = Duration(minutes: 1);
  // SharedPreferences 緩存鍵前綴
  static const String _cacheKeyPrefix = 'unified_eta_cache_';

  // ===========================================================================
  // 公共 API
  // ===========================================================================

  /// 獲取單一站點的 ETA（統一接口）
  ///
  /// 參數：
  /// - company: 公司代碼 ('kmb', 'ctb', 'nlb', 'gmb')
  /// - routeNumber: 路線號碼（如 "101"）
  /// - stopId: 站點 ID（各公司格式不同）
  /// - routeContext: 路線上下文（包含各公司特定的 route ID）
  /// - useCache: 是否使用緩存
  /// - ttl: 緩存過期時間
  Future<List<UnifiedEta>> fetchEta({
    required String company,
    required String routeNumber,
    required String stopId,
    required RouteContext routeContext,
    bool useCache = true,
    Duration ttl = _defaultCacheTtl,
  }) async {
    final cacheKey = _buildCacheKey(company, routeNumber, stopId);

    // 檢查內存緩存
    if (useCache && _isCacheValid(cacheKey)) {
      debugPrint('📦 ETA cache hit: $cacheKey');
      return _etaCache[cacheKey]!.etas;
    }

    // 檢查 SharedPreferences 緩存
    if (useCache) {
      final cached = await _loadFromPrefs(cacheKey, ttl);
      if (cached != null) {
        debugPrint('💾 ETA prefs cache hit: $cacheKey');
        _etaCache[cacheKey] = _EtaCacheEntry(cached, DateTime.now(), ttl);
        return cached;
      }
    }

    // 獲取新數據
    List<UnifiedEta> etas;
    final lowerCompany = company.toLowerCase();

    try {
      switch (lowerCompany) {
        case 'kmb':
          etas = await _fetchKmbEta(stopId, routeNumber, routeContext);
          break;
        case 'ctb':
          etas = await _fetchCtbEta(stopId, routeNumber, routeContext);
          break;
        case 'nlb':
          etas = await _fetchNlbEta(stopId, routeContext);
          break;
        case 'gmb':
        case 'greenminibus':
          etas = await _fetchGmbEta(stopId, routeContext);
          break;
        default:
          throw Exception('Unsupported company: $company');
      }
    } catch (e) {
      debugPrint('❌ Error fetching ETA for $company: $e');
      // 如果有舊緩存，即使過期也返回（降級方案）
      if (_etaCache.containsKey(cacheKey)) {
        debugPrint('⚠️ Returning stale cache for $cacheKey');
        return _etaCache[cacheKey]!.etas;
      }
      rethrow;
    }

    // 更新緩存
    _etaCache[cacheKey] = _EtaCacheEntry(etas, DateTime.now(), ttl);
    await _saveToPrefs(cacheKey, etas);

    return etas;
  }

  /// 批量獲取聯營路線 ETA
  ///
  /// 對於聯營路線（如 KMB+CTB），同時獲取所有公司的 ETA
  Future<Map<String, List<UnifiedEta>>> fetchJointOperationEtas({
    required List<String> companies,
    required String routeNumber,
    required Map<String, String> companyStopIds, // { 'kmb': 'AA100', 'ctb': '002737' }
    required RouteContext routeContext,
    bool useCache = true,
  }) async {
    final results = <String, List<UnifiedEta>>{};

    // 並行獲取所有公司的 ETA
    final futures = <Future<void>>[];
    for (final company in companies) {
      final stopId = companyStopIds[company.toLowerCase()];
      if (stopId == null || stopId.isEmpty) {
        debugPrint('⚠️ No stop ID for company $company');
        continue;
      }

      futures.add(
        fetchEta(
          company: company,
          routeNumber: routeNumber,
          stopId: stopId,
          routeContext: routeContext,
          useCache: useCache,
        ).then((etas) {
          results[company.toLowerCase()] = etas;
        }).catchError((e) {
          debugPrint('❌ Failed to fetch ETA for $company: $e');
          results[company.toLowerCase()] = [];
        }),
      );
    }

    await Future.wait(futures);
    return results;
  }

  /// 清除指定站點的緩存
  void clearCache(String company, String routeNumber, String stopId) {
    final cacheKey = _buildCacheKey(company, routeNumber, stopId);
    _etaCache.remove(cacheKey);
    _removeFromPrefs(cacheKey);
  }

  /// 清除所有緩存
  void clearAllCache() {
    _etaCache.clear();
    _clearAllPrefs();
  }

  // ===========================================================================
  // 公司特定的 ETA 獲取方法
  // ===========================================================================

  /// KMB ETA 獲取
  ///
  /// API: /eta/{stop_id}/{route}/{service_type}
  /// Stop ID: 16-char hex (如 "A3ADFCDF8487ADB9")
  Future<List<UnifiedEta>> _fetchKmbEta(
    String stopId,
    String routeNumber,
    RouteContext context,
  ) async {
    final serviceType = context.serviceType ?? '1';

    final rawEtas = await Kmb.fetchStopRouteEta(
      stopId.toUpperCase(),
      routeNumber.toUpperCase(),
      serviceType,
    );

    return rawEtas.map((eta) {
      final etaTime = _parseTimestamp(eta['eta']?.toString());
      final diff = _calculateDiffMinutes(etaTime);

      return UnifiedEta(
        company: 'kmb',
        eta: etaTime ?? DateTime.now(),
        diffMinutes: diff,
        sequence: int.tryParse(eta['eta_seq']?.toString() ?? '0') ?? 0,
        remarkTc: eta['rmk_tc']?.toString(),
        remarkEn: eta['rmk_en']?.toString(),
        remarkSc: eta['rmk_sc']?.toString(),
        isRealtime: true,
      );
    }).toList();
  }

  /// CTB ETA 獲取
  ///
  /// API: /eta/{company_id}/{stop_id}/{route}
  /// Stop ID: 6-digit zero-padded (如 "002737")
  Future<List<UnifiedEta>> _fetchCtbEta(
    String stopId,
    String routeNumber,
    RouteContext context,
  ) async {
    final rawEtas = await Citybus.fetchEta(
      stopId.padLeft(6, '0'),
      routeNumber.toUpperCase(),
      companyId: 'ctb',
    );

    return rawEtas.map((eta) {
      final etaTime = _parseTimestamp(eta['eta']?.toString());
      final diff = _calculateDiffMinutes(etaTime);

      return UnifiedEta(
        company: 'ctb',
        eta: etaTime ?? DateTime.now(),
        diffMinutes: diff,
        sequence: int.tryParse(eta['eta_seq']?.toString() ?? '0') ?? 0,
        remarkTc: eta['rmk_tc']?.toString(),
        remarkEn: eta['rmk_en']?.toString(),
        remarkSc: eta['rmk_sc']?.toString(),
        isRealtime: true,
      );
    }).toList();
  }

  /// NLB ETA 獲取
  ///
  /// API: stop.php?action=estimatedArrivals&routeId={routeId}&stopId={stopId}
  /// Stop ID: String integer (如 "117")
  /// Route ID: String integer (如 "2")
  Future<List<UnifiedEta>> _fetchNlbEta(
    String stopId,
    RouteContext context,
  ) async {
    final nlbRouteId = context.nlbRouteId;
    if (nlbRouteId == null || nlbRouteId.isEmpty) {
      throw Exception('NLB routeId not provided in context');
    }

    final rawEtas = await Nlb.fetchEstimatedArrivals(
      routeId: nlbRouteId,
      stopId: stopId,
      language: 'zh', // 優先返回中文
    );

    return rawEtas.asMap().entries.map((entry) {
      final eta = entry.value;
      final etaTime = _parseNlbTimestamp(eta['estimatedArrivalTime']?.toString());
      final noGps = int.tryParse(eta['noGPS']?.toString() ?? '0') ?? 0;
      final wheelChair = int.tryParse(eta['wheelChair']?.toString() ?? '0') ?? 0;

      return UnifiedEta(
        company: 'nlb',
        eta: etaTime ?? DateTime.now(),
        sequence: entry.key + 1, // NLB 沒有 eta_seq，用索引+1
        remarkEn: eta['routeVariantName']?.toString(),
        isRealtime: noGps == 1, // noGPS=1 表示有 GPS
        isWheelchairAccessible: wheelChair == 1,
        routeVariant: eta['routeVariantName']?.toString(),
      );
    }).toList();
  }

  /// GMB ETA 獲取
  ///
  /// API: /eta/route-stop/{route_id}/{route_seq}/{stop_seq} 或 /eta/route-stop/{route_id}/{stop_id}
  /// Stop ID: Integer (如 20003337)
  /// Route ID: Integer (如 2000410)
  Future<List<UnifiedEta>> _fetchGmbEta(
    String stopId,
    RouteContext context,
  ) async {
    final gmbRouteId = context.gmbRouteId;
    final gmbRouteSeq = context.gmbRouteSeq ?? 1;

    if (gmbRouteId == null) {
      throw Exception('GMB routeId not provided in context');
    }

    final stopIdInt = int.tryParse(stopId);
    if (stopIdInt == null) {
      throw Exception('Invalid GMB stopId: $stopId (must be integer)');
    }

    List<Map<String, dynamic>> rawEtas = [];

    // 嘗試使用 routeSeq + stopSeq 獲取
    try {
      // 需要知道 stopSeq，從 stopId 查找
      final result = await GMB.fetchRouteStopEtaByStopId(gmbRouteId, stopIdInt);
      for (final item in result) {
        if (item['enabled'] == true && item['eta'] is List) {
          rawEtas.addAll(List<Map<String, dynamic>>.from(item['eta']));
        }
      }
    } catch (e) {
      debugPrint('GMB ETA fetch failed: $e');
      // 嘗試備用方法：獲取站點的所有 ETA
      try {
        final stopEtas = await GMB.fetchStopEta(stopIdInt);
        // 過濾當前路線
        for (final item in stopEtas) {
          if (item['route_id'] == gmbRouteId && item['enabled'] == true) {
            if (item['eta'] is List) {
              rawEtas.addAll(List<Map<String, dynamic>>.from(item['eta']));
            }
          }
        }
      } catch (e2) {
        debugPrint('GMB ETA fallback fetch also failed: $e2');
      }
    }

    // 排序並去重（按 eta_seq）
    final seenSeqs = <int>{};
    final uniqueEtas = <Map<String, dynamic>>[];
    for (final eta in rawEtas) {
      final seq = int.tryParse(eta['eta_seq']?.toString() ?? '0') ?? 0;
      if (!seenSeqs.contains(seq)) {
        seenSeqs.add(seq);
        uniqueEtas.add(eta);
      }
    }
    uniqueEtas.sort((a, b) {
      final seqA = int.tryParse(a['eta_seq']?.toString() ?? '0') ?? 0;
      final seqB = int.tryParse(b['eta_seq']?.toString() ?? '0') ?? 0;
      return seqA.compareTo(seqB);
    });

    return uniqueEtas.map((eta) {
      final timestamp = eta['timestamp']?.toString();
      final diff = int.tryParse(eta['diff']?.toString() ?? '');
      DateTime? etaTime;

      if (timestamp != null) {
        etaTime = _parseTimestamp(timestamp);
      } else if (diff != null) {
        etaTime = DateTime.now().add(Duration(minutes: diff));
      }

      return UnifiedEta(
        company: 'gmb',
        eta: etaTime ?? DateTime.now(),
        diffMinutes: diff,
        sequence: int.tryParse(eta['eta_seq']?.toString() ?? '0') ?? 0,
        remarkTc: eta['remarks_tc']?.toString(),
        remarkEn: eta['remarks_en']?.toString(),
        remarkSc: eta['remarks_sc']?.toString(),
        isRealtime: diff != null, // 有 diff 表示實時數據
      );
    }).toList();
  }

  // ===========================================================================
  // 輔助方法
  // ===========================================================================

  /// 構建緩存鍵
  String _buildCacheKey(String company, String routeNumber, String stopId) {
    return '${company}_${routeNumber}_$stopId'.toLowerCase();
  }

  /// 檢查緩存是否有效
  bool _isCacheValid(String cacheKey) {
    if (!_etaCache.containsKey(cacheKey)) return false;
    return _etaCache[cacheKey]!.isValid;
  }

  /// 從 SharedPreferences 加載緩存
  Future<List<UnifiedEta>?> _loadFromPrefs(String cacheKey, Duration ttl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_cacheKeyPrefix$cacheKey';
      final cachedJson = prefs.getString(key);
      final cachedAtStr = prefs.getString('${key}_at');

      if (cachedJson == null || cachedAtStr == null) return null;

      final cachedAt = DateTime.parse(cachedAtStr);
      if (DateTime.now().difference(cachedAt) >= ttl) return null;

      final decoded = json.decode(cachedJson) as List;
      return decoded.map((e) => _etaFromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading ETA from prefs: $e');
      return null;
    }
  }

  /// 保存到 SharedPreferences
  Future<void> _saveToPrefs(String cacheKey, List<UnifiedEta> etas) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_cacheKeyPrefix$cacheKey';
      final encoded = json.encode(etas.map((e) => _etaToJson(e)).toList());
      await prefs.setString(key, encoded);
      await prefs.setString('${key}_at', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error saving ETA to prefs: $e');
    }
  }

  /// 從 SharedPreferences 移除緩存
  Future<void> _removeFromPrefs(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_cacheKeyPrefix$cacheKey';
      await prefs.remove(key);
      await prefs.remove('${key}_at');
    } catch (_) {}
  }

  /// 清除所有 SharedPreferences 緩存
  Future<void> _clearAllPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cacheKeyPrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  /// ETA 轉 JSON（用於緩存）
  Map<String, dynamic> _etaToJson(UnifiedEta eta) {
    return {
      'company': eta.company,
      'eta': eta.eta.toIso8601String(),
      'diffMinutes': eta.diffMinutes,
      'sequence': eta.sequence,
      'remarkTc': eta.remarkTc,
      'remarkEn': eta.remarkEn,
      'remarkSc': eta.remarkSc,
      'isRealtime': eta.isRealtime,
      'isWheelchairAccessible': eta.isWheelchairAccessible,
      'routeVariant': eta.routeVariant,
    };
  }

  /// JSON 轉 ETA（從緩存）
  UnifiedEta _etaFromJson(Map<String, dynamic> json) {
    return UnifiedEta(
      company: json['company']?.toString() ?? 'unknown',
      eta: DateTime.parse(json['eta']!.toString()),
      diffMinutes: json['diffMinutes'] as int?,
      sequence: json['sequence'] as int? ?? 0,
      remarkTc: json['remarkTc']?.toString(),
      remarkEn: json['remarkEn']?.toString(),
      remarkSc: json['remarkSc']?.toString(),
      isRealtime: json['isRealtime'] as bool? ?? true,
      isWheelchairAccessible: json['isWheelchairAccessible'] as bool? ?? false,
      routeVariant: json['routeVariant']?.toString(),
    );
  }

  /// 解析 ISO 8601 時間戳
  DateTime? _parseTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return null;
    try {
      return DateTime.parse(timestamp).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// 解析 NLB 時間戳（格式: "2018-01-01 08:05:00"）
  DateTime? _parseNlbTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return null;
    try {
      // NLB 使用本地時間，需要添加時區信息
      return DateTime.parse('${timestamp.replaceAll(' ', 'T')}+08:00').toLocal();
    } catch (_) {
      return null;
    }
  }

  /// 計算相對分鐘數
  int? _calculateDiffMinutes(DateTime? etaTime) {
    if (etaTime == null) return null;
    final diff = etaTime.difference(DateTime.now());
    return diff.inMinutes;
  }
}

/// 便捷函數：獲取 ETA（簡化調用）
Future<List<UnifiedEta>> fetchUnifiedEta({
  required String company,
  required String routeNumber,
  required String stopId,
  required RouteContext routeContext,
  bool useCache = true,
}) async {
  return UnifiedEtaService().fetchEta(
    company: company,
    routeNumber: routeNumber,
    stopId: stopId,
    routeContext: routeContext,
    useCache: useCache,
  );
}
