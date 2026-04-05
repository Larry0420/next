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
import '../kmb/api/mtr_bus.dart';

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

  /// 格式化顯示（相對時間 + 絕對時間 + remark）
  String formatDisplay(bool isEnglish, {String? remark}) {
    final abs = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
    final mins = relativeMinutes;

    String timeText;
    if (mins < 1 && mins >= 0) {
      timeText = isEnglish ? 'Due ($abs)' : '即將到達 ($abs)';
    } else if (mins < 0) {
      timeText = isEnglish ? 'Departed' : '已離開';
    } else if (mins < 60) {
      timeText = isEnglish ? '$mins min ($abs)' : '$mins分鐘 ($abs)';
    } else {
      final h = mins ~/ 60;
      final m = mins % 60;
      timeText = isEnglish
          ? '${h}h${m > 0 ? ' ${m}m' : ''} ($abs)'
          : '$h小時${m > 0 ? '$m分' : ''} ($abs)';
    }

    // 如果有 remark，使用點號分隔符追加
    if (remark != null && remark.isNotEmpty) {
      return '$timeText · $remark';
    }

    return timeText;
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
  final String? bound;       // 'I' or 'O' for KMB/CTB
  final String? serviceType; // for KMB
  final String? nlbRouteId;  // NLB specific
  final int? gmbRouteId;     // GMB specific
  final String? gmbRegion;   // GMB region (HKI/KLN/NT)
  final int? gmbRouteSeq;    // GMB route direction (1 or 2)
  final int? gmbStopSeq;     // GMB stop sequence within the route (1-based)

  RouteContext({
    required this.routeNumber,
    this.bound,
    this.serviceType = '1',
    this.nlbRouteId,
    this.gmbRouteId,
    this.gmbRegion,
    this.gmbRouteSeq = 1,
    this.gmbStopSeq,         // nullable — only set per-stop during ETA fetch
  });

  /// 建立一個只改部分欄位的副本，方便 per-stop ETA context override
  RouteContext copyWith({
    String? routeNumber,
    String? bound,
    String? serviceType,
    String? nlbRouteId,
    int? gmbRouteId,
    String? gmbRegion,
    int? gmbRouteSeq,
    int? gmbStopSeq,
  }) {
    return RouteContext(
      routeNumber: routeNumber ?? this.routeNumber,
      bound: bound ?? this.bound,
      serviceType: serviceType ?? this.serviceType,
      nlbRouteId: nlbRouteId ?? this.nlbRouteId,
      gmbRouteId: gmbRouteId ?? this.gmbRouteId,
      gmbRegion: gmbRegion ?? this.gmbRegion,
      gmbRouteSeq: gmbRouteSeq ?? this.gmbRouteSeq,
      gmbStopSeq: gmbStopSeq ?? this.gmbStopSeq,
    );
  }

  @override
  String toString() {
    return 'RouteContext(route: $routeNumber, bound: $bound, svc: $serviceType, '
        'nlb: $nlbRouteId, gmb: $gmbRouteId/$gmbRegion seq=$gmbRouteSeq stopSeq=$gmbStopSeq)';
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
        case 'lrtfeeder':
          etas = await _fetchMtrBusEta(stopId, routeNumber, routeContext);
          break;
        case 'mtr':
          throw Exception('MTR heavy rail not yet supported');
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
    final gmbStopSeq = context.gmbStopSeq; // per-stop seq，可能為 null

    if (gmbRouteId == null) {
      throw Exception('GMB routeId not provided in context');
    }

    final stopIdInt = int.tryParse(stopId);
    if (stopIdInt == null) {
      throw Exception('Invalid GMB stopId: $stopId (must be integer)');
    }

    List<Map<String, dynamic>> rawEtas = [];

    // ── 策略 1：有 stopSeq → 用最精準的 route-stop/seq endpoint ──
    if (gmbStopSeq != null && gmbStopSeq > 0) {
      try {
        final result = await GMB.fetchRouteStopEta(
          gmbRouteId,
          gmbRouteSeq,
          gmbStopSeq,
        );
        if (result['enabled'] == true && result['eta'] is List) {
          rawEtas = List<Map<String, dynamic>>.from(result['eta']);
        }
        debugPrint(
            '✅ GMB ETA via stopSeq: route=$gmbRouteId seq=$gmbRouteSeq stopSeq=$gmbStopSeq → ${rawEtas.length} ETAs');
      } catch (e) {
        debugPrint('⚠️ GMB ETA stopSeq fetch failed, falling back: $e');
        rawEtas = []; // 清空確保 fallback 接手
      }
    }

    // ── 策略 2：無 stopSeq 或策略 1 失敗 → 用 route+stopId endpoint ──
    if (rawEtas.isEmpty) {
      try {
        final results =
            await GMB.fetchRouteStopEtaByStopId(gmbRouteId, stopIdInt);

        for (final item in results) {
          if (item['enabled'] == true && item['eta'] is List) {
            rawEtas.addAll(
              List<Map<String, dynamic>>.from(item['eta']),
            );
          }
        }
        debugPrint(
            '✅ GMB ETA via stopId: route=$gmbRouteId stopId=$stopIdInt → ${rawEtas.length} ETAs');
      } catch (e) {
        debugPrint('⚠️ GMB ETA route+stopId fetch failed, trying stop-only: $e');
      }
    }

    // ── 策略 3：最後 fallback → fetchStopEta 過濾當前路線 ──
    if (rawEtas.isEmpty) {
      try {
        final stopEtas = await GMB.fetchStopEta(stopIdInt);
        for (final item in stopEtas) {
          final itemRouteId = item['route_id'] is int
              ? item['route_id'] as int
              : int.tryParse(item['route_id']?.toString() ?? '');

          if (itemRouteId == gmbRouteId &&
              item['enabled'] == true &&
              item['eta'] is List) {
            rawEtas.addAll(
              List<Map<String, dynamic>>.from(item['eta']),
            );
          }
        }
        debugPrint(
            '✅ GMB ETA via stopOnly: stopId=$stopIdInt filtered to route=$gmbRouteId → ${rawEtas.length} ETAs');
      } catch (e) {
        debugPrint('❌ GMB ETA all strategies failed: $e');
      }
    }

    // ── Dedup by eta_seq（策略 2 可能有多個 occurrence 造成重複）──
    final seenSeqs = <int>{};
    final uniqueEtas = <Map<String, dynamic>>[];
    for (final eta in rawEtas) {
      final seq = eta['eta_seq'] is int
          ? eta['eta_seq'] as int
          : int.tryParse(eta['eta_seq']?.toString() ?? '0') ?? 0;
      if (seenSeqs.add(seq)) {
        uniqueEtas.add(eta);
      }
    }
    uniqueEtas.sort((a, b) {
      final seqA = a['eta_seq'] is int
          ? a['eta_seq'] as int
          : int.tryParse(a['eta_seq']?.toString() ?? '0') ?? 0;
      final seqB = b['eta_seq'] is int
          ? b['eta_seq'] as int
          : int.tryParse(b['eta_seq']?.toString() ?? '0') ?? 0;
      return seqA.compareTo(seqB);
    });

    // ── 解析成 UnifiedEta ──
    return uniqueEtas.map((eta) {
      // diff 是 int（分鐘），GMB API spec 確認係 int 型態
      final diff = eta['diff'] is int
          ? eta['diff'] as int
          : int.tryParse(eta['diff']?.toString() ?? '');

      final timestamp = eta['timestamp']?.toString();
      DateTime etaTime;

      if (timestamp != null && timestamp.isNotEmpty) {
        etaTime = _parseTimestamp(timestamp) ?? DateTime.now().add(
          Duration(minutes: diff ?? 0),
        );
      } else if (diff != null) {
        etaTime = DateTime.now().add(Duration(minutes: diff));
      } else {
        return null; // 無法解析時間的 ETA 直接丟棄
      }

      final seq = eta['eta_seq'] is int
          ? eta['eta_seq'] as int
          : int.tryParse(eta['eta_seq']?.toString() ?? '0') ?? 0;

      return UnifiedEta(
        company: 'gmb',
        eta: etaTime,
        diffMinutes: diff,
        sequence: seq,
        remarkTc: eta['remarks_tc']?.toString(),
        remarkEn: eta['remarks_en']?.toString(),
        remarkSc: eta['remarks_sc']?.toString(),
        // diff != null 代表實時；diff == null 但有 timestamp 則為排班時間
        isRealtime: diff != null,
      );
    }).whereType<UnifiedEta>().toList();
  }

  /// MTR Bus ETA 獲取
  ///
  /// API: POST https://rt.data.gov.hk/v1/transport/mtr/bus/getSchedule
  /// Stop ID: {route}-{direction}{sequence} (e.g., "K12-D010")
  /// 
  /// Note: MTR Bus API returns all stops for a route in one response
  /// We need to find the specific stop and extract its ETA data
  Future<List<UnifiedEta>> _fetchMtrBusEta(
    String stopId,
    String routeNumber,
    RouteContext context,
  ) async {
    // Determine language from context or default to Chinese
    final isEnglish = routeNumber.startsWith('en') || false;
    final language = isEnglish ? 'en' : 'zh';

    // Fetch schedule for the route
    final schedule = await MtrBus.fetchSchedule(routeNumber, language);
    
    // Extract all stops from the schedule
    final allStops = MtrBus.extractStops(schedule);
    
    // Find the matching stop
    final matchingStop = allStops.firstWhere(
      (stop) => stop['busStopId']?.toString() == stopId,
      orElse: () => <String, dynamic>{},
    );
    
    if (matchingStop.isEmpty) {
      debugPrint('⚠️ MTR Bus stop not found: $stopId');
      return [];
    }
    
    // Extract bus data for this stop
    final buses = matchingStop['bus'];
    if (buses is! List) {
      return [];
    }
    
    // Get stop sequence
    final stopSeq = MtrBus.getStopSequence(stopId);
    
    // Convert to UnifiedEta with proper validation
    final validEtas = <UnifiedEta>[];
    
    for (final bus in buses.cast<Map<String, dynamic>>()) {
      // Parse arrival and departure times
      final arrivalSeconds = int.tryParse(bus['arrivalTimeInSecond']?.toString() ?? '');
      final departureSeconds = int.tryParse(bus['departureTimeInSecond']?.toString() ?? '');
      
      // Determine valid time to use
      int? validSeconds;
      
      // Prefer arrival time if valid (allow 0 for "Arriving / Departed" per MTR API spec)
      if (arrivalSeconds != null && arrivalSeconds >= 0) {
        validSeconds = arrivalSeconds;  // ✅ 修改：允許 0（Arriving / Departed）
      } 
      // Fallback to departure time if valid
      //else if (departureSeconds != null && departureSeconds > 0) {
      //  validSeconds = departureSeconds;
      //}
      
      // Skip this bus if no valid time found
      if (validSeconds == null) {
        debugPrint('⚠️ MTR Bus: Skipping bus ${bus['busId']} - no valid ETA time');
        continue;
      }
      
      // Calculate ETA time
      final etaTime = DateTime.now().add(Duration(seconds: validSeconds));
      
      // Note: arrivalTimeInSecond = 0 means "Arriving / Departed" per MTR API spec
      // These buses should be included as they represent real-time arrivals
      // No future-only check for "Arriving / Departed" cases
      
      // Check if scheduled (isScheduled = "1" means it's scheduled, not real-time GPS)
      final isScheduled = bus['isScheduled']?.toString() == '1';
      
      // Extract remarks
      final busRemark = bus['busRemark']?.toString();
      
      // Use stop sequence for ordering (not busId!)
      // ⚠️ Fix: busId is vehicle number (e.g., 804, 807, 819), not time order
      final sequence = stopSeq;  // ✅ 修正：使用站點序號而非巴士編號
      
      validEtas.add(UnifiedEta(
        company: 'lrtfeeder',
        eta: etaTime,
        sequence: sequence,
        remarkTc: busRemark,
        remarkEn: busRemark,
        remarkSc: busRemark,
        isRealtime: !isScheduled, // !scheduled = GPS real-time
      ));
    }

    // lrtfeeder 的 sequence 是 busId（車輛 ID），不是時間順序
    // 需要按 eta 時間排序才能得到正確的班次順序
    validEtas.sort((a, b) => a.eta.compareTo(b.eta));

    debugPrint('✅ MTR Bus: Found ${validEtas.length} valid ETAs for stop $stopId');
    return validEtas;
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
