import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hkbus_db_provider.dart';
import 'kmb/api/citybus.dart';
import 'kmb/api/kmb.dart';
import 'kmb/company_name.dart';
import 'main.dart' show LanguageProvider, DeveloperSettingsProvider;
import 'services/route_id_resolver.dart';
import 'services/unified_eta_service.dart';

/// 統一路線狀態頁面
/// 
/// 支持單一公司或多公司聯營路線
/// 可從 hkbus_db_provider (統一數據庫) 或各公司 API 獲取數據
class UnifiedRouteStatusPage extends StatefulWidget {
  final String route;
  final List<String> companies;
  final String? initialCompany;
  final String? bound;
  final String? serviceType;
  /// 從 dialer 導航時傳入 JSON 的 routeId（如 "1+1+ORIG+DEST"），可精確匹配路線，避免同號碼多方向歧義
  final String? initialRouteId;
  final String? autoExpandStopId;
  final String? autoExpandSeq;
  final bool useUnifiedDb;

  const UnifiedRouteStatusPage({
    super.key,
    required this.route,
    required this.companies,
    this.initialCompany,
    this.bound,
    this.serviceType,
    this.initialRouteId,
    this.autoExpandStopId,
    this.autoExpandSeq,
    this.useUnifiedDb = true,
  });

  @override
  State<UnifiedRouteStatusPage> createState() => _UnifiedRouteStatusPageState();
}

class _UnifiedRouteStatusPageState extends State<UnifiedRouteStatusPage> {
  static const String _mapViewPreferenceKey = 'unified_route_status_map_view_enabled';
  final DraggableScrollableController _draggableController = DraggableScrollableController();
  final ScrollController _scrollController = ScrollController();
  final MapController _mapController = MapController();

  // 狀態
  bool loading = false;
  String? error;
  Map<String, dynamic>? data;
  
  // 公司相關
  late String _selectedCompany;
  List<Map<String, dynamic>> _allStops = [];

  // 地圖和位置
  bool _showMapView = false;
  Position? _userPosition;
  bool _locationLoading = false;
  String? _highlightedStopId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _stopKeys = {};

  // ETA 相關（僅在展開時載入）
  final Map<String, List<UnifiedEta>> _etaByStopId = {};
  final Set<String> _etaLoadingByStopId = {};

  // ETA 服務實例
  final UnifiedEtaService _etaService = UnifiedEtaService();
  final RouteIdResolver _routeIdResolver = RouteIdResolver();

  // 路線上下文緩存（用於解析 route ID）
  RouteContext? _routeContext;
  ResolvedRouteIds? _resolvedRouteIds;

  @override
  void initState() {
    super.initState();
    // 確保是單一公司代碼（避免 "kmb+ctb" 這樣的組合值）
    _selectedCompany = (widget.initialCompany ?? widget.companies.first).split('+').first;
    _loadMapViewPreference();
    _initializeLocation();
    _initializeRouteContext();
    _fetchData();
  }

  /// 初始化路線上下文（解析各公司 route ID）
  Future<void> _initializeRouteContext() async {
    try {
      await _routeIdResolver.initialize();

      final hkbusDb = context.read<HkbusDbProvider>();
      final routeData = widget.initialRouteId != null
          ? hkbusDb.getRouteById(widget.initialRouteId!)
          : hkbusDb.getRouteByNumber(
              widget.route,
              direction: widget.bound,
              serviceType: widget.serviceType,
            );

      if (routeData != null) {
        _resolvedRouteIds = await _routeIdResolver.resolveRouteIds(
          hkbusRouteId: routeData.routeId,
          routeNumber: widget.route,
          companies: widget.companies,
        );

        // 構建 RouteContext
        _routeContext = RouteContext(
          routeNumber: widget.route,
          bound: _getBoundFromRouteData(routeData),
          serviceType: widget.serviceType ?? '1',
          nlbRouteId: _resolvedRouteIds?.nlbRouteId,
          gmbRouteId: _resolvedRouteIds?.gmbRouteId,
          gmbRegion: _resolvedRouteIds?.gmbRegion,
          gmbRouteSeq: 1, // 默認第一個方向
        );

        debugPrint('✅ Route context initialized: $_routeContext');
      }
    } catch (e) {
      debugPrint('❌ Error initializing route context: $e');
    }
  }

  /// 從路線數據獲取方向
  String? _getBoundFromRouteData(UnifiedBusRoute routeData) {
    if (routeData.boundsByCompany.isNotEmpty) {
      return routeData.boundsByCompany.values.first?.toString();
    }
    return widget.bound;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _draggableController.dispose();
    super.dispose();
  }

  Future<void> _loadMapViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _showMapView = prefs.getBool(_mapViewPreferenceKey) ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveMapViewPreference(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mapViewPreferenceKey, show);
  }

  Future<void> _initializeLocation() async {
    try {
      final status = await Permission.location.status;
      if (status.isGranted) {
        final last = await Geolocator.getLastKnownPosition();
        if (mounted && last != null) {
          setState(() => _userPosition = last);
        }
        
        final current = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 5),
          ),
        );
        if (mounted) {
          setState(() => _userPosition = current);
        }
      }
    } catch (_) {}
  }

  /// 獲取用戶位置並滾動到最近站點
  Future<void> _getUserLocationAndScrollToNearest() async {
    if (!mounted) return;
    
    setState(() => _locationLoading = true);
    
    try {
      // 獲取當前位置
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 5),
        ),
      );
      
      if (!mounted) return;
      setState(() => _userPosition = pos);
      
      if (_allStops.isEmpty) return;
      
      // 找到最近站點
      String? nearestStopId;
      double minDistance = double.infinity;
      
      for (final stop in _allStops) {
        // ✅ 確保 stop 係 Map 而唔係 String，防止 stop['lat'] 爆 type error
        if (stop is! Map<String, dynamic>) {
          debugPrint('⚠️ _allStops contains non-map: ${stop.runtimeType} = $stop');
          continue;
        }
        final lat = stop['lat']?.toString();
        final lng = stop['long']?.toString() ?? stop['lng']?.toString();
        final stopId = stop['stop']?.toString();
        
        if (lat == null || lng == null || stopId == null) continue;
        
        try {
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            double.parse(lat),
            double.parse(lng),
          );
          
          if (distance < minDistance) {
            minDistance = distance;
            nearestStopId = stopId;
          }
        } catch (_) {}
      }
      
      // 滾動到最近站點
      if (nearestStopId != null && _stopKeys.containsKey(nearestStopId)) {
        final key = _stopKeys[nearestStopId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.3, // 將站點放在視圖 30% 位置
          );
          
          // 高亮顯示
          setState(() {
            _highlightedStopId = nearestStopId;
          });
          
          _highlightTimer?.cancel();
          _highlightTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _highlightedStopId = null);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      if (mounted) {
        setState(() => _locationLoading = false);
      }
    }
  }

  /// 獲取路線數據
  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      if (widget.useUnifiedDb) {
        await _fetchFromUnifiedDb();
      } else {
        await _fetchFromCompanyApi();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  /// 從統一數據庫獲取
  Future<void> _fetchFromUnifiedDb() async {
    final hkbusDb = context.read<HkbusDbProvider>();
    
    if (!hkbusDb.isReady) {
      throw Exception('Unified database not ready');
    }

    // 優先用 initialRouteId（從 dialer 傳入）精確匹配，否則用路線號＋方向＋服務類型
    UnifiedBusRoute? routeData;
    if (widget.initialRouteId != null && widget.initialRouteId!.isNotEmpty) {
      routeData = hkbusDb.getRouteById(widget.initialRouteId!);
    }
    routeData ??= hkbusDb.getRouteByNumber(
      widget.route,
      direction: widget.bound,
      serviceType: widget.serviceType,
    );

    if (routeData == null) {
      // 如果在統一數據庫找不到，回退到 API
      debugPrint('Route not found in unified DB, falling back to API');
      await _fetchFromCompanyApi();
      return;
    }
    final route = routeData;

    // 獲取站點組（聯營路線會包含多家公司的站點）
    final rawGroups = hkbusDb.buildStopGroupsForRoute(route.routeId);

    // 防止 rawGroups 其實係 List<String> 或混雜 List/Map
    final stopGroups = rawGroups.whereType<Map<String, dynamic>>().toList();

    if (stopGroups.length != rawGroups.length) {
      debugPrint(
        '❌ stopGroups type mismatch: '
        '${rawGroups.map((e) => e.runtimeType).toSet()}',
      );
      debugPrint('sample=${rawGroups.take(5).toList()}');
    }

    List<Map<String, dynamic>> stops;

    // NLB 專營路線回退：當 stopGroups 為空且路線包含 NLB 時，從 stopsByCompany 建立站點
    if (stopGroups.isEmpty &&
        route.companies.any((c) => c.toLowerCase() == 'nlb')) {
      final nlbStopsRaw = route.stopsByCompany['nlb'];
      if (nlbStopsRaw != null) {
        List<String> nlbStops = [];
        if (nlbStopsRaw is String) {
          try {
            final parsed = jsonDecode(nlbStopsRaw);
            if (parsed is List) {
              nlbStops = parsed.map((e) => e.toString()).toList();
            }
          } catch (_) {}
        } else if (nlbStopsRaw is List) {
          nlbStops = nlbStopsRaw.map((e) => e.toString()).toList();
        }
        stops = nlbStops.asMap().entries.map((entry) {
          final stopId = entry.value;
          final coords = hkbusDb.getStopCoordinates(stopId);
          return {
            'seq': entry.key + 1,
            'stop': stopId,
            'name_tc': hkbusDb.getStopName(stopId, isEnglish: false),
            'name_en': hkbusDb.getStopName(stopId, isEnglish: true),
            'kmb_stop_id': null,
            'ctb_stop_id': null,
            'gmb_stop_id': null,
            'nlb_stop_id': stopId,
            'lat': coords?['lat'],
            'lng': coords?['lng'],
          };
        }).toList();
      } else {
        stops = [];
      }
    } else {
      // 轉換為統一格式，並添加站點座標
      stops = stopGroups.map((group) {
        final stopId = group['${_selectedCompany}_stop_id'] ??
            group['kmb_stop_id'] ??
            group['ctb_stop_id'] ??
            group['gmb_stop_id'] ??
            group['nlb_stop_id'];

        final rawSeq = group['seq'];
        final seq0 = rawSeq is int ? rawSeq : (int.tryParse(rawSeq?.toString() ?? '') ?? 0);

        // 獲取站點座標（使用當前選擇的公司或第一個可用的公司 ID）
        final coords = stopId != null
            ? hkbusDb.getStopCoordinates(stopId.toString())
            : null;

        return {
          'seq': seq0 + 1, // 從 0-based 轉為 1-based（防止 seq 是 String）
          'stop': stopId,
          'name_tc': group['name_tc'],
          'name_en': group['name_en'],
          'kmb_stop_id': group['kmb_stop_id'],
          'ctb_stop_id': group['ctb_stop_id'],
          'gmb_stop_id': group['gmb_stop_id'],
          'nlb_stop_id': group['nlb_stop_id'],
          'lat': coords?['lat'],
          'lng': coords?['lng'],
        };
      }).where((s) => s['stop'] != null).toList();
    }

    if (mounted) {
      setState(() {
        final normalizedStops = _normalizeStops(stops, company: _selectedCompany);
        _allStops = normalizedStops;
        data = {
          'route': widget.route,
          'stops': normalizedStops,
          'companies': route.companies,
          'orig_tc': route.origTc,
          'orig_en': route.origEn,
          'dest_tc': route.destTc,
          'dest_en': route.destEn,
        };
        loading = false;
      });
    }
  }

  /// 從公司 API 獲取
  Future<void> _fetchFromCompanyApi() async {
    final company = _selectedCompany.toLowerCase();
    
    try {
      switch (company) {
        case 'kmb':
          await _fetchKmbData();
          break;
        case 'ctb':
          await _fetchCtbData();
          break;
        case 'nlb':
          await _fetchNlbData();
          break;
        default:
          throw Exception('Unsupported company: $company');
      }
    } catch (e) {
      debugPrint('Error fetching from $company API: $e');
      rethrow;
    }
  }

  Future<void> _fetchKmbData() async {
    final r = widget.route.trim().toUpperCase();
    // 直接使用 API
    final result = await Kmb.fetchRouteStatus(r);
    await _processKmbData(result);
  }

  

  Future<void> _processKmbData(Map<String, dynamic> result) async {
    final rawEntries = result['data']?['stops'];
    // ✅ 改用 _normalizeStops，同時處理 List<Map> 和 List<String>
    final entries = _normalizeStops(rawEntries, company: 'kmb');

    if (entries.isEmpty) {
      debugPrint('KMB stops empty or invalid for ${widget.route}. raw type=${rawEntries.runtimeType}');
    }

    await _processStopEntries(entries, 'kmb');
  }

  Future<void> _processCtbData(Map<String, dynamic> result) async {
    final rawEntries = result['data']?['stops'];
    // ✅ 改用 _normalizeStops
    final entries = _normalizeStops(rawEntries, company: 'ctb');

    if (entries.isEmpty) {
      debugPrint('CTB stops empty or invalid for ${widget.route}. raw type=${rawEntries.runtimeType}');
    }

    await _processStopEntries(entries, 'ctb');
  }



  Future<void> _fetchCtbData() async {
    final r = widget.route.trim().toUpperCase();
    // 直接使用 API
    final result = await Citybus.fetchRouteStatus(r);
    await _processCtbData(result);
  }


  Future<void> _fetchNlbData() async {
    final hkbusDb = context.read<HkbusDbProvider>();
    
    // 从 HkbusDbProvider 获取路线数据
    final routeData = hkbusDb.getRouteByNumber(
      widget.route,
      direction: widget.bound,
      serviceType: widget.serviceType,
    );

    if (routeData == null) {
      throw Exception('Route ${widget.route} not found in unified DB');
    }

    // 获取 NLB 特定的站点列表
    final nlbStopsRaw = routeData.stopsByCompany['nlb'];
    if (nlbStopsRaw == null) {
      throw Exception('No NLB stops found for route ${widget.route}');
    }

    // 安全地提取站点列表（处理 String 或 List 类型）
    List<String> nlbStops = [];
    if (nlbStopsRaw is String) {
      try {
        final parsed = jsonDecode(nlbStopsRaw);
        if (parsed is List) {
          nlbStops = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (nlbStopsRaw is List) {
      nlbStops = nlbStopsRaw.map((e) => e.toString()).toList();
    }

    if (nlbStops.isEmpty) {
      throw Exception('No NLB stops found for route ${widget.route}');
    }

    // 构建站点条目
    final entries = nlbStops.asMap().entries.map((entry) {
      return {
        'seq': entry.key + 1, // 1-based sequence
        'stop': entry.value,
      };
    }).toList();

    await _processStopEntries(entries, 'nlb');
  }

  // ✅ 新增 normalizeStops helper - 保證任何來源的 stops 都是 List<Map<String, dynamic>>
  List<Map<String, dynamic>> _normalizeStops(
    dynamic stopsRaw, {
    String? company,
  }) {
    final hkbusDb = context.read<HkbusDbProvider>();
    final output = <Map<String, dynamic>>[];

    if (stopsRaw == null) return output;

    if (stopsRaw is List) {
      for (int i = 0; i < stopsRaw.length; i++) {
        final item = stopsRaw[i];

        // Case A: 已經係 Map
        if (item is Map) {
          output.add(Map<String, dynamic>.from(item));
          continue;
        }

        // Case B: 係 stopId String（Unified DB 的 stopsByCompany 格式）
        final stopId = item?.toString() ?? '';
        if (stopId.isEmpty) continue;

        final coords = hkbusDb.getStopCoordinates(stopId);
        output.add({
          'seq': i + 1,
          'stop': stopId,
          'name_tc': hkbusDb.getStopName(stopId, isEnglish: false),
          'name_en': hkbusDb.getStopName(stopId, isEnglish: true),
          'kmb_stop_id': company == 'kmb' ? stopId : null,
          'ctb_stop_id': company == 'ctb' ? stopId : null,
          'gmb_stop_id': company == 'gmb' ? stopId : null,
          'nlb_stop_id': company == 'nlb' ? stopId : null,
          'lat': coords?['lat'],
          'lng': coords?['lng'],
          'long': coords?['lng'],
        });
      }
    } else if (stopsRaw is String) {
      // Case C: JSON string（部分 API 可能這樣返回）
      try {
        return _normalizeStops(jsonDecode(stopsRaw), company: company);
      } catch (_) {}
    }

    return output;
  }


  Future<void> _processStopEntries(List<Map<String, dynamic>> entries, String company) async {
    if (!mounted) return;
    
    final hkbusDb = context.read<HkbusDbProvider>();
    
    // 過濾和排序
    entries = entries.where((e) => e.containsKey('seq')).toList();
    entries.sort((a, b) {
      final ai = int.tryParse(a['seq']?.toString() ?? '0') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '0') ?? 0;
      return ai.compareTo(bi);
    });

    // ✅ 明確宣告為 List<Map<String, dynamic>>，避免 Dart 推斷為 List<Object>
    final List<Map<String, dynamic>> enriched = entries.map((entry) {
      final stopId = entry['stop']?.toString();
      if (stopId == null) return entry;

      final nameTc = hkbusDb.getStopName(stopId, isEnglish: false);
      final nameEn = hkbusDb.getStopName(stopId, isEnglish: true);
      final coords = hkbusDb.getStopCoordinates(stopId);

      return <String, dynamic>{
        ...entry,
        'name_tc': entry['name_tc'] ?? nameTc,
        'name_en': entry['name_en'] ?? nameEn,
        'lat': entry['lat'] ?? coords?['lat'],
        'long': entry['long'] ?? coords?['lng'],
      };
    }).toList();

    // ✅ 確保 _allStops 唔會含有 String 元素
    assert(
      enriched.every((e) => e is Map<String, dynamic>),
      '_allStops contains non-map items',
    );

    if (mounted) {
      setState(() {
        _allStops = enriched;
        data = {
          'route': widget.route,
          'stops': enriched,
          'companies': widget.companies,
        };
        loading = false;
      });
    }

    final normalizedStops = _normalizeStops(enriched, company: company);

    if (mounted) {
      setState(() {
        _allStops = normalizedStops;
        data = {
          'route': widget.route,
          'stops': normalizedStops,
          'companies': widget.companies,
        };
        loading = false;
      });
    }

  }

  /// 獲取單一站點的 ETA（僅在展開時呼叫）
  ///
  /// 處理所有數據類型：
  /// - KMB: 16-char hex stop ID, service_type
  /// - CTB: 6-digit stop ID
  /// - NLB: String int stop ID + routeId
  /// - GMB: Integer stop ID + route_id + route_seq
  Future<void> _fetchEtaForSingleStop(Map<String, dynamic> stop) async {
    final stopId = stop['stop']?.toString();
    if (stopId == null || stopId.isEmpty) return;

    // 檢查內存緩存
    if (_etaByStopId.containsKey(stopId) && _etaByStopId[stopId]!.isNotEmpty) {
      debugPrint('📦 ETA memory cache hit for stop: $stopId');
      return;
    }

    // 確保路線上下文已初始化
    if (_routeContext == null) {
      debugPrint('⚠️ Route context not initialized, initializing now...');
      await _initializeRouteContext();
    }

    if (mounted) {
      setState(() => _etaLoadingByStopId.add(stopId));
    }

    try {
      List<UnifiedEta> etas = [];

      // 對於聯營路線，獲取所有公司的 ETA
      if (widget.companies.length > 1 && widget.useUnifiedDb) {
        etas = await _fetchJointOperationEtas(stop);
      } else {
        // 單一公司
        final companyStopId = stop['${_selectedCompany}_stop_id']?.toString() ?? stopId;
        etas = await _etaService.fetchEta(
          company: _selectedCompany,
          routeNumber: widget.route,
          stopId: companyStopId,
          routeContext: _routeContext ?? RouteContext(routeNumber: widget.route),
        );
      }

      if (mounted) {
        setState(() {
          _etaByStopId[stopId] = etas;
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching ETA for stop $stopId: $e');
    } finally {
      if (mounted) {
        setState(() => _etaLoadingByStopId.remove(stopId));
      }
    }
  }

  /// 獲取聯營路線的所有公司 ETA
  Future<List<UnifiedEta>> _fetchJointOperationEtas(Map<String, dynamic> stop) async {
    final etas = <UnifiedEta>[];
    final companyEtasMap = <String, List<UnifiedEta>>{};

    // 並行獲取所有公司的 ETA
    final futures = <Future<void>>[];

    for (final company in widget.companies) {
      final companyStopId = stop['${company}_stop_id']?.toString() ?? stop['stop']?.toString();
      if (companyStopId == null || companyStopId.isEmpty) {
        debugPrint('⚠️ No stop ID for company $company in joint operation');
        continue;
      }

      futures.add(
        _etaService
            .fetchEta(
          company: company,
          routeNumber: widget.route,
          stopId: companyStopId,
          routeContext: _routeContext ?? RouteContext(routeNumber: widget.route),
        )
            .then((companyEtas) {
          companyEtasMap[company] = companyEtas;
        }).catchError((e) {
          debugPrint('❌ Failed to fetch ETA for $company: $e');
          companyEtasMap[company] = [];
        }),
      );
    }

    await Future.wait(futures);

    // 合併所有公司的 ETA，添加公司標識
    for (final entry in companyEtasMap.entries) {
      final company = entry.key;
      final companyEtas = entry.value;

      // 為每個 ETA 添加公司信息
      final markedEtas = companyEtas.map((eta) {
        return UnifiedEta(
          company: company,
          eta: eta.eta,
          diffMinutes: eta.diffMinutes,
          sequence: eta.sequence,
          remarkTc: eta.remarkTc,
          remarkEn: eta.remarkEn,
          remarkSc: eta.remarkSc,
          isRealtime: eta.isRealtime,
          isWheelchairAccessible: eta.isWheelchairAccessible,
          routeVariant: eta.routeVariant,
        );
      }).toList();

      etas.addAll(markedEtas);
    }

    // 按時間排序
    etas.sort((a, b) => a.eta.compareTo(b.eta));

    return etas;
  }



  /// 切換運營公司
  void _onCompanyChanged(String company) {
    if (company == _selectedCompany) return;
    
    setState(() {
      _selectedCompany = company;
    });
    
    // 重新獲取數據
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final companyProv = context.watch<CompanyProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: isEnglish ? 'Back' : '返回',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lang.route} ${widget.route}'),
            if (widget.companies.length > 1)
              Text(
                widget.companies.map((c) => companyProv.getName(c, isEnglish)).join(' + '),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          // 公司選擇器（聯營路線）
          if (widget.companies.length > 1)
            PopupMenuButton<String>(
              initialValue: _selectedCompany,
              onSelected: _onCompanyChanged,
              itemBuilder: (context) => widget.companies.map((co) {
                return PopupMenuItem(
                  value: co,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: companyProv.getBadgeBorderColor(co, context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(companyProv.getName(co, isEnglish)),
                    ],
                  ),
                );
              }).toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(companyProv.getName(_selectedCompany, isEnglish)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          
          // 定位按鈕 - 滾動到最近站點
          IconButton(
            icon: _locationLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_userPosition != null ? Icons.near_me : Icons.near_me_disabled),
            tooltip: isEnglish ? 'Scroll to nearest stop' : '滾動至最近站點',
            onPressed: _locationLoading || _allStops.isEmpty
                ? null
                : () => _getUserLocationAndScrollToNearest(),
          ),
          
          // 地圖切換
          IconButton(
            icon: Icon(_showMapView ? Icons.list : Icons.map),
            tooltip: _showMapView
                ? (isEnglish ? 'Show list' : '顯示列表')
                : (isEnglish ? 'Show map' : '顯示地圖'),
            onPressed: () {
              setState(() => _showMapView = !_showMapView);
              _saveMapViewPreference(_showMapView);
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: $error'))
              : _buildContent(context, isEnglish),
    );
  }

  Widget _buildContent(BuildContext context, bool isEnglish) {
    final devSettings = context.watch<DeveloperSettingsProvider>();
    
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _showMapView
              ? _buildSplitView(devSettings)
              : _buildListView(devSettings, isEnglish),
        ),
        if (devSettings.useFloatingRouteToggles)
          _buildFloatingBar(),
      ],
    );
  }

  Widget _buildSplitView(DeveloperSettingsProvider devSettings) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isLandscape) {
      return Row(
        children: [
          Expanded(
            flex: isMobile ? 2 : 1,
            child: _buildMapView(),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: isMobile ? 3 : 1,
            child: _buildListView(devSettings, context.read<LanguageProvider>().isEnglish),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          Expanded(
            flex: isMobile ? 2 : 1,
            child: _buildMapView(),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: isMobile ? 3 : 1,
            child: _buildListView(devSettings, context.read<LanguageProvider>().isEnglish),
          ),
        ],
      );
    }
  }

  Widget _buildListView(DeveloperSettingsProvider devSettings, bool isEnglish) {
    // ✅ 直接用 _normalizeStops，完全消除 List<dynamic> 和 runtime cast
    final List<Map<String, dynamic>> stops = _normalizeStops(
      data?['stops'],
      company: _selectedCompany,
    );

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (!devSettings.useFloatingRouteToggles)
          SliverToBoxAdapter(child: _buildHeader(isEnglish)),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final stop = stops[index]; // ✅ 不再需要 as Map cast
              return _buildStopCard(stop, index, isEnglish);
            },
            childCount: stops.length,
          ),
        ),

        SliverPadding(
          padding: EdgeInsets.only(
            bottom: devSettings.useFloatingRouteToggles ? 200 : 20,
          ),
        ),
      ],
    );
  }


  Widget _buildHeader(bool isEnglish) {
    final orig = isEnglish
        ? (data?['orig_en'] ?? data?['orig_tc'] ?? '')
        : (data?['orig_tc'] ?? data?['orig_en'] ?? '');
    final dest = isEnglish
        ? (data?['dest_en'] ?? data?['dest_tc'] ?? '')
        : (data?['dest_tc'] ?? data?['dest_en'] ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.departure_board, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$orig → $dest',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            // 顯示所有運營公司標籤
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: widget.companies.map((co) {
                final companyProv = context.read<CompanyProvider>();
                return _buildCompanyBadge(co, companyProv);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyBadge(String company, CompanyProvider companyProv) {
    final isSelected = company == _selectedCompany;
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onCompanyChanged(company),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? companyProv.getBadgeBgColor(company, context)
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: isSelected
                  ? companyProv.getBadgeBorderColor(company, context)
                  : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: companyProv.getBadgeBorderColor(company, context),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                companyProv.getName(company, context.read<LanguageProvider>().isEnglish),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? companyProv.getBadgeTextColor(company, context)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopCard(Map<String, dynamic> stop, int index, bool isEnglish) {
    final stopId = stop['stop']?.toString() ?? '';
    final seq = stop['seq']?.toString() ?? '${index + 1}';
    final name = isEnglish
        ? (stop['name_en'] ?? stop['name_tc'] ?? stopId)
        : (stop['name_tc'] ?? stop['name_en'] ?? stopId);
    final etas = _etaByStopId[stopId] ?? [];
    final etaLoading = _etaLoadingByStopId.contains(stopId);

    // 檢查是否為附近站點
    final lat = stop['lat']?.toString();
    final lng = stop['long']?.toString() ?? stop['lng']?.toString();
    final isNearby = _userPosition != null && lat != null && lng != null
        ? _isNearbyStop(lat, lng)
        : false;

    // 檢查是否應自動展開
    final shouldAutoExpand = (widget.autoExpandSeq != null && seq == widget.autoExpandSeq) ||
        (widget.autoExpandStopId != null && stopId == widget.autoExpandStopId);

    // 自動展開時，需在首次建構後觸發 ETA 載入（onExpansionChanged 可能不會在 initiallyExpanded 時觸發）
    if (shouldAutoExpand && !_etaByStopId.containsKey(stopId) && !_etaLoadingByStopId.contains(stopId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchEtaForSingleStop(stop);
      });
    }

    return Card(
      key: _stopKeys.putIfAbsent(stopId, () => GlobalKey()),
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: isNearby ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isNearby
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        initiallyExpanded: shouldAutoExpand,
        onExpansionChanged: (isExpanded) {
          if (isExpanded && !_etaByStopId.containsKey(stopId) && !_etaLoadingByStopId.contains(stopId)) {
            _fetchEtaForSingleStop(stop);
          }
        },
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isNearby
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              seq,
              style: TextStyle(
                color: isNearby
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: isNearby ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isNearby)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isEnglish ? 'Nearby' : '附近',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: etaLoading
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(isEnglish ? 'Loading...' : '載入中...', style: const TextStyle(fontSize: 12)),
              )
            : etas.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_formatEtaList(etas)),
                  )
                : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (etaLoading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else if (etas.isNotEmpty)
              const Icon(Icons.access_time, size: 16),
            if (lat != null && lng != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.map, size: 20),
                tooltip: isEnglish ? 'Show on map' : '在地圖上顯示',
                onPressed: () => _jumpToMapLocation(
                  double.parse(lat),
                  double.parse(lng),
                  stopId: stopId,
                ),
              ),
            ],
          ],
        ),
        children: [
          // 展開後顯示詳細信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                // 載入中
                if (etaLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(isEnglish ? 'Loading ETA...' : '載入到站時間...', style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  )
                // 顯示所有公司的 ETA
                else if (widget.companies.length > 1) ...[
                  Text(
                    isEnglish ? 'All Operators:' : '所有營運商：',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.companies.map((co) {
                    // 從已載入的 ETAs 中過濾出該公司的 ETA
                    final allEtas = _etaByStopId[stopId] ?? <UnifiedEta>[];
                    final coEtas = allEtas.where((eta) => eta.company.toLowerCase() == co.toLowerCase()).toList();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: context.read<CompanyProvider>().getBadgeBorderColor(co, context),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.read<CompanyProvider>().getName(co, isEnglish),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              coEtas.isNotEmpty ? _formatEtaList(coEtas) : '--',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                // 站點 ID 信息
                const SizedBox(height: 8),
                Text(
                  '${isEnglish ? 'Stop ID' : '站點 ID'}: $stopId',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 檢查站點是否在附近（約 500 米內）
  bool _isNearbyStop(String lat, String lng) {
    if (_userPosition == null) return false;
    try {
      final stopLat = double.parse(lat);
      final stopLng = double.parse(lng);
      final distance = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        stopLat,
        stopLng,
      );
      return distance < 500; // 500 米內視為附近
    } catch (_) {
      return false;
    }
  }

  /// 跳轉到地圖位置
  void _jumpToMapLocation(double latitude, double longitude, {String? stopId}) {
    // 設置高亮站點
    if (stopId != null) {
      setState(() {
        _highlightedStopId = stopId;
      });
      
      // 3 秒後清除高亮
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _highlightedStopId = null;
          });
        }
      });
    }
    
    if (!_showMapView) {
      // 如果地圖未顯示，啟用地图视图
      setState(() {
        _showMapView = true;
      });
      _saveMapViewPreference(true);
      // 等待地图构建后移动位置
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _mapController.move(LatLng(latitude, longitude), 17.0);
          }
        });
      });
    } else {
      // 地图已显示，直接移动
      _mapController.move(LatLng(latitude, longitude), 17.0);
    }
  }

  /// 格式化 ETA 显示，包含相对时间和绝对时间
  /// 示例："5分鐘 (19:56)", "即將到達 (19:56)", "已離開"
  String _formatEtaList(List<UnifiedEta> etas) {
    if (etas.isEmpty) return '';

    final lang = context.read<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    // 只顯示前 2 個 ETA
    final firstTwo = etas.take(2).toList();
    return firstTwo.map((eta) => eta.formatDisplay(isEnglish)).join(' · ');
  }

  Widget _buildMapView() {
    // TODO: 實現地圖視圖
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Text('Map View')),
    );
  }

  Widget _buildFloatingBar() {
    final theme = Theme.of(context);
    final lang = context.read<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final companyProv = context.read<CompanyProvider>();

    return DraggableScrollableSheet(
      controller: _draggableController,
      initialChildSize: 0.18,
      minChildSize: 0.1,
      maxChildSize: 0.5,
      snap: true,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: FakeGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 20),
            settings: LiquidGlassSettings(
              blur: 10,
              thickness: 20,
              glassColor: theme.colorScheme.surface.withValues(alpha: 0.3),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // 拖動指示器
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                // 公司選擇器
                Text(
                  isEnglish ? 'Operators' : '營運商',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: widget.companies.map((co) {
                      final isSel = co == _selectedCompany;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSel,
                          label: Text(
                            companyProv.getName(co, isEnglish),
                          ),
                          onSelected: (_) => _onCompanyChanged(co),
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          selectedColor: companyProv.getBadgeBgColor(co, context),
                          checkmarkColor: companyProv.getBadgeTextColor(co, context),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
