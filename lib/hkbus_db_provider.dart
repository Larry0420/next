import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
      case 'mtr': return isEnglish ? 'MTR Bus' : '港鐵巴士';
      case 'lrtfeeder':
      case 'lrt_feeder':
      case 'lrt-feeder': return isEnglish ? 'LRT Feeder' : '輕鐵接駁';
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

  /// 初始化：先讀 Cache，若無或過期則下載
  Future<void> initDb({bool forceUpdate = false}) async {
    try {
      final file = await _getCacheFile();
      
      // 檢查 Cache 是否存在及是否過舊 (例如超過 12 小時)
      bool needsUpdate = forceUpdate;
      if (!file.existsSync()) {
        needsUpdate = true;
      } else {
        final lastModified = file.lastModifiedSync();
        if (DateTime.now().difference(lastModified).inHours > 12) {
          needsUpdate = true;
        }
      }

      String jsonString;
      if (needsUpdate) {
        debugPrint('Downloading routeFareList.min.json from GitHub Pages...');
        final response = await http.get(Uri.parse(dbUrl));
        if (response.statusCode == 200) {
          jsonString = response.body;
          // 寫入本地 Cache
          await file.writeAsString(jsonString);
        } else {
          // 下載失敗但有舊檔，讀取舊檔
          jsonString = await file.readAsString();
        }
      } else {
        debugPrint('Loading Bus DB from local cache...');
        jsonString = await file.readAsString();
      }

      final data = jsonDecode(jsonString);
      if (data is! Map) {
        throw Exception('Invalid hkbus DB root JSON type: ${data.runtimeType}');
      }

      final routeListRaw = data['routeList'];
      final stopListRaw = data['stopList'];
      final stopMapRaw = data['stopMap'];

      _routeList = routeListRaw is Map ? Map<String, dynamic>.from(routeListRaw) : <String, dynamic>{};
      _stopList = stopListRaw is Map ? Map<String, dynamic>.from(stopListRaw) : <String, dynamic>{};
      _stopMap = stopMapRaw is Map ? Map<String, dynamic>.from(stopMapRaw) : <String, dynamic>{};
      
      _isReady = true;
      notifyListeners();
      
    } catch (e) {
      debugPrint('Error loading hkbus DB: $e');
    }
  }

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
      
      // stops/bound 必須為 Map，否則後續用 String 索引會拋 "String is not a subtype of int of 'index'"
      final stopsRaw = data['stops'];
      final boundRaw = data['bound'];
      final stopsByCompany = stopsRaw is Map ? Map<String, dynamic>.from(stopsRaw) : <String, dynamic>{};
      final boundsByCompany = boundRaw is Map ? Map<String, dynamic>.from(boundRaw) : <String, dynamic>{};

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
    final stopsRaw = data['stops'];
    final boundRaw = data['bound'];
    final stopsByCompany = stopsRaw is Map ? Map<String, dynamic>.from(stopsRaw) : <String, dynamic>{};
    final boundsByCompany = boundRaw is Map ? Map<String, dynamic>.from(boundRaw) : <String, dynamic>{};
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
  UnifiedBusRoute? getRouteByNumber(String routeNumber, {String? direction, String? serviceType}) {
    final all = getAllRoutes();
    final matches = all.where((r) => r.routeNumber.toUpperCase() == routeNumber.toUpperCase());
    
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;
    
    // 有多個匹配時，根據方向和服務類型篩選
    for (final route in matches) {
      bool matchesDir = direction == null;
      bool matchesSvc = serviceType == null;
      
      if (direction != null && route.boundsByCompany.isNotEmpty) {
        final bound = route.boundsByCompany.values.first?.toString().toUpperCase();
        matchesDir = bound == direction.toUpperCase() ||
                    (direction.toUpperCase().startsWith('I') && bound == 'I') ||
                    (direction.toUpperCase().startsWith('O') && bound == 'O');
      }
      
      if (serviceType != null) {
        matchesSvc = route.serviceType == serviceType;
      }
      
      if (matchesDir && matchesSvc) {
        return route;
      }
    }
    
    // 返回第一個匹配
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
    Map<String, dynamic> stopsMap,
    String companyKey,
    String routeId,
  ) {
    if (stopsMap is List) {
      debugPrint('⚠️ _safeExtractStopList received List instead of Map for $routeId');
      return [];
    }
    final rawValue = stopsMap[companyKey];

    // 如果值為 null，返回空列表
    if (rawValue == null) {
      return [];
    }

    // 如果值是 String，嘗試解析為 JSON
    if (rawValue is String) {
      try {
        final parsed = jsonDecode(rawValue);
        if (parsed is List) {
          final result = <String>[];
          for (final item in parsed) {
            final strValue = item?.toString();
            if (strValue != null && strValue.isNotEmpty) {
              result.add(strValue);
            }
          }
          return result;
        }
      } catch (e) {
        debugPrint('❌ Failed to parse string stops for $companyKey in route $routeId: $e');
        return [];
      }
    }

    // 如果值是 List，提取所有字符串元素
    if (rawValue is List) {
      final result = <String>[];
      for (final item in rawValue) {
        final strValue = item?.toString();
        if (strValue != null && strValue.isNotEmpty) {
          result.add(strValue);
        }
      }
      return result;
    }

    // 不支持的類型
    debugPrint(
      '⚠️ Unexpected stops type for $companyKey in route $routeId: '
      '${rawValue.runtimeType}',
    );
    return [];
  }

  /// 獲取某條路線的「聯營 Stop Group」清單 (傳給 RouteStatusPage 用)
  /// 它會幫你把 KMB、CTB、GMB 和 NLB 的 StopId 對齊
  List<Map<String, dynamic>> buildStopGroupsForRoute(String routeId) {
    if (!_isReady || _routeList == null) return [];
    
    if (_routeList is! Map) return [];
    final routeData = (_routeList as Map)[routeId];
    if (routeData == null) return [];

    if (routeData is! Map) return [];
    final stopsRaw = routeData['stops'];
    // 必須是 Map：若為 List 會導致後續用 String 索引時拋出 "String is not a subtype of int of 'index'"
    if (stopsRaw is! Map<String, dynamic>) {
      debugPrint('❌ Invalid stops structure for route $routeId: expected Map, got ${stopsRaw.runtimeType}');
      return [];
    }
    final stopsMap = stopsRaw;
    debugPrint('buildStopGroupsForRoute($routeId): stopsMap type = ${stopsMap.runtimeType}');

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

      // 如果兩間公司只出現其中一間，試著去 stopMap 查跨公司對照
      if (kId != null && cId == null && stopMap.containsKey(kId)) {
         final mapEntry = stopMap[kId] as List<dynamic>?;
         if (mapEntry != null && mapEntry.isNotEmpty) {
           cId = mapEntry.first['ctb']?.toString();
         }
      } else if (cId != null && kId == null && stopMap.containsKey(cId)) {
         final mapEntry = stopMap[cId] as List<dynamic>?;
         if (mapEntry != null && mapEntry.isNotEmpty) {
           kId = mapEntry.first['kmb']?.toString();
         }
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
  
  /// 強制刷新數據
  Future<void> refresh() async {
    await initDb(forceUpdate: true);
  }
}
