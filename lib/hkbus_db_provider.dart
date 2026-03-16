// hkbus_db_provider.dart 頂部
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart'  // 只在 non-web 有效
    if (dart.library.html) 'package:hk_transport/stubs/path_provider_stub.dart';


class UnifiedBusRoute {
  final String routeId;      // JSON 裡的 Key (例如 "101+1+KENNEDY TOWN+KWUN TONG")
  final String routeNumber;  // "101"
  final List<String> companies; // ["kmb", "ctb"]
  final String origTc;
  final String origEn;       // 新增：英文起點
  final String destTc;
  final String destEn;       // 新增：英文終點
  final String? serviceType; // 新增：服務類型
  final Map<String, dynamic> stopsByCompany; // {"kmb": ["stop1",...], "ctb": ["stop2",...]}
  final Map<String, dynamic> boundsByCompany; // {"kmb": "I", "ctb": "I"}

  UnifiedBusRoute({
    required this.routeId,
    required this.routeNumber,
    required this.companies,
    required this.origTc,
    this.origEn = '',
    required this.destTc,
    this.destEn = '',
    this.serviceType,
    required this.stopsByCompany,
    required this.boundsByCompany,
  });

  /// 獲取主要公司（用於決定導航到哪個頁面）
  String get primaryCompany => companies.isNotEmpty ? companies.first.toLowerCase() : 'kmb';
  
  /// 是否為聯營路線
  bool get isJointOperation => companies.length > 1;
  
  /// 獲取顯示用的公司名稱
  String getDisplayCompany(bool isEnglish) {
    if (companies.isEmpty) return isEnglish ? 'Unknown' : '未知';
    final names = companies.map((co) {
      return _getCompanyDisplayName(co, isEnglish);
    }).toList();
    return names.join(' + ');
  }
  
  /// 獲取單個公司的顯示名稱
  String _getCompanyDisplayName(String co, bool isEnglish) {
    final lower = co.toLowerCase().trim();
    switch (lower) {
      // 巴士服務
      case 'kmb': return isEnglish ? 'KMB' : '九巴';
      case 'ctb': return isEnglish ? 'CTB' : '城巴';
      case 'lwb': return isEnglish ? 'LWB' : '龍運';
      case 'nlb': return isEnglish ? 'NLB' : '嶼巴';
      case 'mtr': return isEnglish ? 'MTR' : '港鐵';
      case 'lrtfeeder':
      case 'lrt_feeder':
      case 'lrt-feeder': return isEnglish ? 'LRT Feeder' : '港鐵接駁';
      case 'gmb':
      case 'greenminibus': return isEnglish ? 'GMB' : '專線小巴';
      // 鐵路服務
      case 'lightrail':
      case 'light_rail':
      case 'lrt': return isEnglish ? 'Light Rail' : '輕鐵';
      // 渡輪服務
      case 'sunferry':
      case 'sun ferry': return isEnglish ? 'Sun Ferry' : '新渡輪';
      case 'fortuneferry':
      case 'fortune ferry': return isEnglish ? 'Fortune Ferry' : '富裕小輪';
      case 'hkkf': return isEnglish ? 'HKKF' : '港九小輪';
      // 預設
      default: return co.toUpperCase();
    }
  }
  
  /// 獲取公司的主題色
  Color getCompanyColor(String co) {
    final lower = co.toLowerCase().trim();
    switch (lower) {
      case 'kmb': return Colors.red;
      case 'ctb': return Colors.amber;
      case 'lwb': return Colors.orange;
      case 'nlb': return Colors.lightGreen;
      case 'mtr': return Colors.purple;
      case 'lrtfeeder':
      case 'lrt_feeder':
      case 'lrt-feeder': return Colors.teal;
      case 'lightrail':
      case 'light_rail':
      case 'lrt': return Colors.cyan;
      case 'gmb':
      case 'greenminibus': return Colors.green;
      case 'sunferry':
      case 'sun ferry': return Colors.blue;
      case 'fortuneferry':
      case 'fortune ferry': return Colors.indigo;
      case 'hkkf': return Colors.deepPurple;
      default: return Colors.grey;
    }
  }
}

class HkbusDbProvider extends ChangeNotifier {
  static const String dbUrl = 'https://hkbus.github.io/hk-bus-crawling/routeFareList.min.json';
  
  Map<String, dynamic>? _routeList;
  Map<String, dynamic>? _stopList;
  Map<String, dynamic>? _stopMap;

  bool _isReady = false;
  bool get isReady => _isReady;

  /// 安全地从字段中提取字符串（处理字段可能是 Map 或 String 的情况）
  String? _extractStringFromField(dynamic field, String key) {
    if (field == null) return null;

    if (field is Map) {
      return field[key]?.toString();
    }

    if (field is String) {
      return field;
    }

    return null;
  }

  /// 將 stops 數據標準化為 Map<String, dynamic> 格式
  /// 處理 stops 可能是 List、Map 或 String 的情況
  Map<String, dynamic> _normalizeStopsMap(
    dynamic stopsRaw,
    List coList,
    String routeId,
  ) {
    final primary = coList.isNotEmpty
        ? coList.first.toString().toLowerCase().trim()
        : 'kmb';

    if (stopsRaw == null) return {};

    if (stopsRaw is Map) {
      return Map<String, dynamic>.from(stopsRaw);
    }

    if (stopsRaw is List) {
      return {primary: List.from(stopsRaw)};
    }

    if (stopsRaw is String) {
      try {
        final decoded = jsonDecode(stopsRaw);
        return _normalizeStopsMap(decoded, coList, routeId);
      } catch (e) {
        debugPrint('❌ Failed to parse stops string for $routeId: $e');
        return {};
      }
    }

    debugPrint('⚠️ Unexpected stops type for $routeId: ${stopsRaw.runtimeType}');
    return {};
  }

  Map<String, dynamic> _normalizeBoundsMap(
    dynamic boundRaw,
    List coList,
    String routeId,
  ) {
    final primary = coList.isNotEmpty
        ? coList.first.toString().toLowerCase().trim()
        : 'kmb';

    if (boundRaw == null) return {};

    if (boundRaw is Map) {
      return Map<String, dynamic>.from(boundRaw);
    }

    if (boundRaw is String) {
      return {primary: boundRaw};
    }

    if (boundRaw is List) {
      return {primary: boundRaw.isNotEmpty ? boundRaw.first.toString() : ''};
    }

    debugPrint('⚠️ Unexpected bound type for $routeId: ${boundRaw.runtimeType}');
    return {};
  }




  /// 初始化：先讀 Cache，若無或過期則下載
  Future<void> initDb({bool forceUpdate = false}) async {
    try {
      String? jsonString;

      if (kIsWeb) {
        jsonString = await _loadFromPrefs(forceUpdate);
      } else {
        jsonString = await _loadFromFile(forceUpdate);
      }

      if (jsonString == null || jsonString.isEmpty) {
        throw Exception('Failed to load hkbus DB: empty content');
      }

      final data = jsonDecode(jsonString);
      if (data is! Map) throw Exception('Invalid hkbus DB root JSON type');

      _routeList = data['routeList'] is Map ? Map.from(data['routeList']) : {};
      _stopList  = data['stopList']  is Map ? Map.from(data['stopList'])  : {};
      _stopMap   = data['stopMap']   is Map ? Map.from(data['stopMap'])   : {};

      _isReady = true;
      notifyListeners();
      debugPrint('✅ hkbus DB loaded: ${_routeList!.length} routes, ${_stopList!.length} stops');

    } catch (e) {
      debugPrint('❌ Error loading hkbus DB: $e');
    }
  }

/// Web：用 SharedPreferences 做 cache
Future<String?> _loadFromPrefs(bool forceUpdate) async {
  final prefs = await SharedPreferences.getInstance();
  const key   = 'hkbus_db_json';
  const keyAt = 'hkbus_db_cached_at';

  if (!forceUpdate) {
    final cachedAt = prefs.getString(keyAt);
    final cached   = prefs.getString(key);
    if (cached != null && cachedAt != null) {
      final age = DateTime.now().difference(DateTime.parse(cachedAt));
      if (age.inHours < 12) {
        debugPrint('💾 hkbus DB from SharedPreferences (${age.inMinutes}min old)');
        return cached;
      }
    }
  }

  debugPrint('🌐 Downloading hkbus DB (web)...');
  try {
    final res = await http.get(Uri.parse(dbUrl));
    if (res.statusCode == 200) {
      await prefs.setString(key, res.body);
      await prefs.setString(keyAt, DateTime.now().toIso8601String());
      return res.body;
    }
  } catch (e) {
    debugPrint('❌ Download failed: $e');
  }
  // 下載失敗，用舊 cache
  return prefs.getString(key);
}

  /// Mobile/Desktop：用 File 做 cache
  Future<String?> _loadFromFile(bool forceUpdate) async {
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/routeFareList.min.json');

    bool needsUpdate = forceUpdate || !file.existsSync();
    if (!needsUpdate) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age.inHours > 12) needsUpdate = true;
    }

    if (needsUpdate) {
      debugPrint('📥 Downloading hkbus DB (native)...');
      try {
        final res = await http.get(Uri.parse(dbUrl));
        if (res.statusCode == 200) {
          await file.writeAsString(res.body);
          debugPrint('✅ hkbus DB saved to cache');
          return res.body;
        }
      } catch (e) {
        debugPrint('❌ Download failed: $e');
      }
      // 下載失敗，讀舊檔（如果有）
      if (file.existsSync()) return file.readAsString();
      return null;
    }

    debugPrint('📂 hkbus DB from file cache');
    return file.readAsString();
  }

  Future<void> refresh() async => initDb(forceUpdate: true);
    


  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/routeFareList.min.json');
  }

  // ==========================================
  // 解析 Helper (給 Dialer / Search / Nearby 用)
  // ==========================================

  /// 取得所有路線清單 (Dialer 列表使用)
  List<UnifiedBusRoute> getAllRoutes() {
    if (!_isReady || _routeList == null) return [];

    List<UnifiedBusRoute> list = [];
    _routeList!.forEach((routeId, data) {
      final coList = List<String>.from(data['co'] ?? []);
      
      // 解析 service type（通常在 routeId 中，格式如 "101+1+ORIG+DEST"）
      String? serviceType;
      final idParts = routeId.toString().split('+');
      if (idParts.length >= 2) {
        serviceType = idParts[1];
      }
      
      // 使用 normalize 方法處理 stops/bound，支持 List/Map/String 多種格式
      final stopsByCompany = _normalizeStopsMap(data['stops'], coList, routeId.toString());
      final boundsByCompany = _normalizeBoundsMap(data['bound'], coList, routeId.toString());

      list.add(UnifiedBusRoute(
        routeId: routeId,
        routeNumber: data['route']?.toString() ?? '',
        companies: coList,
        origTc: _extractStringFromField(data['orig'], 'zh') ?? '',
        origEn: _extractStringFromField(data['orig'], 'en') ?? '',
        destTc: _extractStringFromField(data['dest'], 'zh') ?? '',
        destEn: _extractStringFromField(data['dest'], 'en') ?? '',
        serviceType: serviceType,
        stopsByCompany: stopsByCompany,
        boundsByCompany: boundsByCompany,
      ));
    });
    return list;
  }

  /// 根據輸入的字串搜尋路線 (給 Dialer 用)
  /// 支持路線號碼、起點、終點的中英文搜索
  List<UnifiedBusRoute> searchRoutes(String keyword) {
    final all = getAllRoutes();
    if (keyword.isEmpty) return all;
    
    final kw = keyword.toUpperCase().trim();
    
    // 分數匹配系統
    final scored = <MapEntry<UnifiedBusRoute, int>>[];
    
    for (final route in all) {
      int score = 0;
      final routeNum = route.routeNumber.toUpperCase();
      
      // 路線號碼匹配（最高優先級）
      if (routeNum == kw) {
        score += 100; // 完全匹配
      } else if (routeNum.startsWith(kw)) {
        score += 50;  // 開頭匹配
      } else if (routeNum.contains(kw)) {
        score += 20;  // 包含匹配
      }
      
      // 起點終點匹配（中英文）
      final origTc = route.origTc.toUpperCase();
      final origEn = route.origEn.toUpperCase();
      final destTc = route.destTc.toUpperCase();
      final destEn = route.destEn.toUpperCase();
      
      if (origTc.contains(kw) || origEn.contains(kw) || 
          destTc.contains(kw) || destEn.contains(kw)) {
        score += 10;
      }
      
      // 只有有分數的才加入結果
      if (score > 0) {
        scored.add(MapEntry(route, score));
      }
    }
    
    // 按分數排序（高分在前）
    scored.sort((a, b) => b.value.compareTo(a.value));
    
    return scored.map((e) => e.key).toList();
  }
  
  /// 根據 routeId（JSON 的 key，如 "1+1+CHUK YUEN ESTATE+STAR FERRY"）獲取單一路線
  /// 從 dialer 導航時傳入可精確匹配，避免同號碼多方向的歧義
  UnifiedBusRoute? getRouteById(String routeId) {
    if (!_isReady || _routeList == null || _routeList is! Map) return null;
    final data = (_routeList as Map)[routeId];
    if (data == null || data is! Map) return null;
    final coList = List<String>.from(data['co'] ?? []);
    String? serviceType;
    final idParts = routeId.toString().split('+');
    if (idParts.length >= 2) serviceType = idParts[1];
    // 使用 normalize 方法處理 stops/bound，支持 List/Map/String 多種格式
    final stopsByCompany = _normalizeStopsMap(data['stops'], coList, routeId);
    final boundsByCompany = _normalizeBoundsMap(data['bound'], coList, routeId);
    return UnifiedBusRoute(
      routeId: routeId,
      routeNumber: data['route']?.toString() ?? '',
      companies: coList,
      origTc: _extractStringFromField(data['orig'], 'zh') ?? '',
      origEn: _extractStringFromField(data['orig'], 'en') ?? '',
      destTc: _extractStringFromField(data['dest'], 'zh') ?? '',
      destEn: _extractStringFromField(data['dest'], 'en') ?? '',
      serviceType: serviceType,
      stopsByCompany: stopsByCompany,
      boundsByCompany: boundsByCompany,
    );
  }

  /// 根據路線號碼和方向獲取特定路線
  UnifiedBusRoute? getRouteByNumber(String routeNumber, {
    String? direction, 
    String? serviceType,
    String? company,          // ← 新增參數
  }) {
    final all = getAllRoutes();
    final matches = all.where((r) => r.routeNumber.toUpperCase() == routeNumber.toUpperCase());
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;

    for (final route in matches) {
      bool matchesDir = direction == null;
      bool matchesSvc = serviceType == null;
      bool matchesCo = company == null;    // ← 新增

      // ✅ 新增：company 過濾
      if (company != null) {
        matchesCo = route.companies.any(
          (c) => c.toString().toLowerCase() == company.toLowerCase()
        );
      }

      if (direction != null && route.boundsByCompany.isNotEmpty) {
        final bound = route.boundsByCompany.values.first?.toString().toUpperCase();
        matchesDir = bound == direction.toUpperCase();
      }
      if (serviceType != null) {
        matchesSvc = route.serviceType == serviceType;
      }

      if (matchesDir && matchesSvc && matchesCo) return route;   // ← 加 matchesCo
    }
    return matches.first;
  }


  /// 透過 StopId 查站點名稱
  String getStopName(String stopId, {bool isEnglish = false}) {
    if (!_isReady || _stopList == null) return 'Unknown Stop';
    if (_stopList is! Map) return 'Unknown Stop';

    final stop = (_stopList as Map)[stopId];
    if (stop == null) return 'Unknown Stop';

    if (stop is! Map) return 'Unknown Stop';
    
    // name 字段可能是 Map 或 String
    final nameField = stop['name'];
    
    if (nameField == null) return 'Unknown Stop';
    
    // 如果 name 是 Map，提取对应的语言版本
    if (nameField is Map) {
      return isEnglish 
        ? (nameField['en']?.toString() ?? '') 
        : (nameField['zh']?.toString() ?? '');
    }
    
    // 如果 name 是 String，直接返回
    if (nameField is String) {
      return nameField;
    }
    
    // 其他情况返回空字符串
    return '';
  }

  /// 獲取站點座標（緯度和經度）
  /// 返回 Map {'lat': double, 'lng': double} 或 null
  Map<String, double>? getStopCoordinates(String stopId) {
    if (!_isReady || _stopList == null) return null;
    if (_stopList is! Map) return null;

    final stop = (_stopList as Map)[stopId];
    if (stop == null) return null;
    if (stop is! Map) return null;
    
    // 嘗試不同的座標欄位格式
    dynamic lat, lng;
    
    // 尝试从 location Map 获取
    final locationField = stop['location'];
    if (locationField is Map) {
      lat = locationField['lat'];
      lng = locationField['lng'];
    }
    
    // 如果没有，尝试从直接的 lat/lng/long 字段获取
    lat ??= stop['lat'];
    lng ??= stop['long'] ?? stop['lng'];
    
    if (lat == null || lng == null) return null;
    
    try {
      return {
        'lat': double.parse(lat.toString()),
        'lng': double.parse(lng.toString()),
      };
    } catch (_) {
      return null;
    }
  }

  /// 安全地從 stopsMap 中提取站點列表
  /// 防止數據類型錯誤導致的崩潰（stopsMap 必須為 Map，不可為 List，否則 String 索引會拋錯）
  List<String> _safeExtractStopList(
    dynamic stopsMap, // 改為 dynamic，避免預設係 Map 但實質傳入 String
    String companyKey,
    String routeId,
  ) {
    // 1. 確保傳入嘅 stopsMap 真係一個 Map
    if (stopsMap is! Map) {
      debugPrint('⚠️ _safeExtractStopList: stopsMap is not a Map for $routeId. Type: ${stopsMap.runtimeType}');
      return [];
    }

    // 2. 取出該公司嘅資料
    final rawValue = stopsMap[companyKey];

    if (rawValue == null) return [];

    // 3. 如果係 List，直接轉
    if (rawValue is List) {
      return rawValue.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    }

    // 4. 如果係 String，可能係 JSON string，試下 parse
    if (rawValue is String) {
      try {
        final parsed = jsonDecode(rawValue);
        if (parsed is List) {
          return parsed.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
        }
      } catch (e) {
        debugPrint('❌ Failed to parse string stops for $companyKey in route $routeId: $e');
      }
    }

    return [];
  }


  /// 獲取某條路線的「聯營 Stop Group」清單 (傳給 RouteStatusPage 用)
  /// 它會幫你把 KMB、CTB、GMB 和 NLB 的 StopId 對齊
  List<Map<String, dynamic>> buildStopGroupsForRoute(String routeId) {
    if (!_isReady || _routeList == null) return [];
    
    if (_routeList is! Map) return [];
    final routeData = (_routeList as Map)[routeId];
    if (routeData == null || routeData is! Map) return [];

    // 使用 normalize 方法處理 stops，支持 List/Map/String 多種格式
    final coList = List.from(routeData['co'] ?? []);
    final stopsMap = _normalizeStopsMap(routeData['stops'], coList, routeId.toString());

    if (stopsMap.isEmpty) {
      debugPrint('⚠️ No stops found for route $routeId after normalize');
      return [];
    }
    debugPrint('buildStopGroupsForRoute($routeId): stopsMap type = ${stopsMap.runtimeType}, keys=${stopsMap.keys}');

    // 獲取各公司的站點列表（使用安全的類型轉換）
    List<String> kmbStops = _safeExtractStopList(stopsMap, 'kmb', routeId);
    List<String> ctbStops = _safeExtractStopList(stopsMap, 'ctb', routeId);
    List<String> gmbStops = _safeExtractStopList(stopsMap, 'gmb', routeId);
    List<String> nlbStops = _safeExtractStopList(stopsMap, 'nlb', routeId);

    // 驗證至少有一個公司有站點數據
    if (kmbStops.isEmpty && ctbStops.isEmpty && gmbStops.isEmpty && nlbStops.isEmpty) {
      debugPrint('⚠️ No stops found for route $routeId');
      return [];
    }

    // ✅ Extract fares (index-aligned with stops, same as JSON structure)
    final rawFares = routeData['fares'];
    final List<String> fares = rawFares is List
        ? rawFares.map((e) => e?.toString() ?? '').toList()
        : [];
    final rawFaresHoliday = routeData['faresHoliday'];
    final List<String>? faresHoliday = rawFaresHoliday is List
        ? rawFaresHoliday.map((e) => e?.toString() ?? '').toList()
        : null;


    // 以長度最長的陣列為基準跑迴圈
    int maxLength = [kmbStops.length, ctbStops.length, gmbStops.length, nlbStops.length]
        .reduce((a, b) => a > b ? a : b);
    
    final stopMap = _stopMap ?? {};
    List<Map<String, dynamic>> stopGroups = [];
    
    for (int i = 0; i < maxLength; i++) {
      String? kId = i < kmbStops.length ? kmbStops[i] : null;
      String? cId = i < ctbStops.length ? ctbStops[i] : null;
      String? gId = i < gmbStops.length ? gmbStops[i] : null;
      String? nId = i < nlbStops.length ? nlbStops[i] : null;
      
      // ✅ AFTER – iterate [operator, stopId] pairs correctly
      // Helper: resolve all operator IDs from a stopMap entry
      Map<String, String> _resolveFromStopMap(dynamic key, Map stopMap) {
        final result = <String, String>{};
        final pairs = stopMap[key];
        if (pairs is! List) return result;
        for (final pair in pairs) {
          if (pair is List && pair.length >= 2) {
            final op  = pair[0]?.toString()?.toLowerCase();
            final sid = pair[1]?.toString();
            if (op != null && sid != null && sid.isNotEmpty) result[op] = sid;
          }
        }
        return result;
      }

      // Inside the buildStopGroupsForRoute loop, replace the cross-reference block:
      if (kId != null && stopMap.containsKey(kId)) {
        final resolved = _resolveFromStopMap(kId, stopMap);
        cId ??= resolved['ctb'];
        gId ??= resolved['gmb'];
        nId ??= resolved['nlb'];
      } else if (cId != null && stopMap.containsKey(cId)) {
        final resolved = _resolveFromStopMap(cId, stopMap);
        kId ??= resolved['kmb'];
        gId ??= resolved['gmb'];
        nId ??= resolved['nlb'];
      } else if (gId != null && stopMap.containsKey(gId)) {
        final resolved = _resolveFromStopMap(gId, stopMap);
        kId ??= resolved['kmb'];
        cId ??= resolved['ctb'];
        nId ??= resolved['nlb'];
      }

      // 選擇用於顯示站點名稱的 ID（優先順序：KMB > CTB > GMB > NLB）
      String displayId = kId ?? cId ?? gId ?? nId ?? '';
      
      stopGroups.add({
        'seq': i,
        'kmb_stop_id': kId,
        'ctb_stop_id': cId,
        'gmb_stop_id': gId,
        'nlb_stop_id': nId,
        'name_tc': getStopName(displayId, isEnglish: false),
        'name_en': getStopName(displayId, isEnglish: true),
        'fare':         i < fares.length ? fares[i] : null,         // ✅
        'fare_holiday': (faresHoliday != null && i < faresHoliday.length)
                            ? faresHoliday[i] : null,
      });
    }

    return stopGroups;
  }
  
  // ==========================================
  // Dialer 數據適配器
  // ==========================================
  
  /// 將 UnifiedBusRoute 轉換為 kmb_dialer 需要的格式
  /// 這是一個適配器方法，統一數據格式
  Map<String, dynamic> convertToDialerFormat(UnifiedBusRoute route) {
    // 獲取第一個公司的 bound
    String bound = 'O';
    if (route.boundsByCompany.isNotEmpty) {
      bound = route.boundsByCompany.values.first?.toString() ?? 'O';
    }
    
    // 構建搜索文本（用於快速匹配）
    final searchText = [
      route.routeNumber,
      route.origEn,
      route.origTc,
      route.destEn,
      route.destTc,
    ].where((s) => s.isNotEmpty).join(' ').toLowerCase();
    
    return {
      'route': route.routeNumber,
      'companyid': route.primaryCompany,
      'companies': route.companies,
      'companyname': route.getDisplayCompany(false),
      'orig_en': route.origEn,
      'orig_tc': route.origTc,
      'dest_en': route.destEn,
      'dest_tc': route.destTc,
      'bound': bound,
      'direction': bound == 'I' ? 'inbound' : 'outbound',
      'service_type': route.serviceType ?? '1',
      'isJointOperation': route.isJointOperation,
      'routeId': route.routeId,
      'search_text': searchText,
      // 原始數據保留
      'stopsByCompany': route.stopsByCompany,
      'boundsByCompany': route.boundsByCompany,
    };
  }
  
  /// 獲取所有路線的 Dialer 格式數據
  List<Map<String, dynamic>> getAllRoutesForDialer() {
    final routes = getAllRoutes();
    return routes.map((r) => convertToDialerFormat(r)).toList();
  }
  
  /// 搜索路線並返回 Dialer 格式
  List<Map<String, dynamic>> searchRoutesForDialer(String keyword) {
    final routes = searchRoutes(keyword);
    return routes.map((r) => convertToDialerFormat(r)).toList();
  }
  

}
