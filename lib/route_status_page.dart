import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:lrt_next_train/toTitleCase.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hkbus_db_provider.dart';
import 'kmb/api/citybus.dart';
import 'kmb/api/kmb.dart';
import 'kmb/company_name.dart';
import 'main.dart' show LanguageProvider, DeveloperSettingsProvider, MotionConstants;
import 'optionalMarquee.dart';
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
  static const String _NearByPreferenceKey = 'unified_route_status_nearby_enabled';
  final DraggableScrollableController _draggableController = DraggableScrollableController();
  final ScrollController _scrollController = ScrollController();
  final MapController _mapController = MapController();

  // 狀態
  bool loading = false;
  String? error;
  Map<String, dynamic>? data;
  bool get isEnglish => context.read<LanguageProvider>().isEnglish;
  LanguageProvider get lang => context.read<LanguageProvider>();
  
  // 公司相關
  late String _selectedCompany;
  List<Map<String, dynamic>> _allStops = [];
  
  // 路線變體相關
  List<Map<String, dynamic>> _routeVariants = [];

  // 地圖和位置
  bool _showMapView = false;
  bool _toggleNearBy = false;
  Position? _userPosition;
  bool _locationLoading = false;
  String? _highlightedStopId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _stopKeys = {};

  // Nearby logic（hkbus style）
  String? _nearestStopId;       // 唯一最近站點 ID（排序取第一）
  double? _nearestDistanceM;    // 最近站點距離（metres），用於 badge 顯示
  static const double _nearbyBadgeRange = 150.0; // 200m 內才顯示 Nearby badge

  // ETA 相關（僅在展開時載入）
  final Map<String, Map<String, dynamic>> _expandedStopsById = {};
  final Set<String> _etaRefreshingByStopId = <String>{};

  Timer? _etaRefreshTimer;
  bool _etaRefreshInFlight = false;

  static const Duration _etaRefreshInterval = Duration(seconds: 20);

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
    _selectedCompany = (widget.initialCompany ?? widget.companies.first).toLowerCase().split('+').first;  // ✅ fixed: ensure lowercase
    _loadPreferences(); // Combined preference loader
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
              company: _selectedCompany,
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

  /// 從統一數據庫加載路線變體
  Future<void> _loadRouteVariants() async {
    if (!widget.useUnifiedDb) return;
    
    debugPrint('🔍 _loadRouteVariants: route=${widget.route}, company=$_selectedCompany');
    
    // 对于 GMB，使用 RouteIdResolver 获取所有变体（包括不同 region）
    if (_selectedCompany.toLowerCase() == 'gmb') {
      await _loadGmbVariantsWithRegion();
      return;
    }
    
    // 对于其他公司，使用现有逻辑
    final hkbusDb = context.read<HkbusDbProvider>();
    final allRoutes = hkbusDb.getAllRoutes();
    
    // 根据路线号和公司过滤
    final matches = allRoutes.where((r) => 
      r.routeNumber.toUpperCase() == widget.route.toUpperCase() &&
      r.companies.any((c) => c.toLowerCase() == _selectedCompany.toLowerCase())
    ).toList();
    
    debugPrint('🔍 Found ${matches.length} route matches');
    
    // 收集所有路线变体
    final variants = <Map<String, dynamic>>[];
    for (final route in matches) {
      // 获取该路线的所有方向
      for (final company in route.companies) {
        final bound = route.boundsByCompany[company.toLowerCase()]?.toString().toUpperCase();
        if (bound != null) {
          final variant = {
            'routeId': route.routeId,
            'bound': bound,
            'serviceType': route.serviceType ?? '1',
            'orig_tc': route.origTc,
            'orig_en': route.origEn,
            'dest_tc': route.destTc,
            'dest_en': route.destEn,
            'company': company.toLowerCase(),
          };
          
          debugPrint('  📍 Found variant: ${route.routeId}, bound=$bound, serviceType=${route.serviceType}');
          variants.add(variant);
        }
      }
    }
    
    // 去重（按 routeId）
    final uniqueVariants = <String, Map<String, dynamic>>{};
    for (final v in variants) {
      uniqueVariants[v['routeId']] = v;
    }
    
    if (mounted) {
      setState(() {
        _routeVariants = uniqueVariants.values.toList();
        debugPrint('✅ Total unique variants: ${_routeVariants.length}');
      });
    }
  }

  /// 加载 GMB 变体并附加 region 信息
  Future<void> _loadGmbVariantsWithRegion() async {
    try {
      final routeIdResolver = RouteIdResolver();
      await routeIdResolver.initialize();
      
      final gmbVariants = await routeIdResolver.getGmbRouteVariants(widget.route);
      
      debugPrint('🔍 GMB variants for ${widget.route}: ${gmbVariants.length}');
      
      final variants = <Map<String, dynamic>>[];
      final hkbusDb = context.read<HkbusDbProvider>();
      
      // 为每个 GMB 变体创建变体卡片数据
      for (final gmbVariant in gmbVariants) {
        final gmbRouteId = gmbVariant['route_id'];
        final gmbRegion = gmbVariant['region'];
        final origEn = gmbVariant['orig_en'];
        final destEn = gmbVariant['dest_en'];
        
        // 尝试从 hkbus_db 中查找匹配的路线，确定 serviceType
        String serviceType = '1';
        String hkbusRouteId = '${widget.route}+1+$origEn+$destEn';
        
        // 检查 serviceType 1 是否存在
        if (hkbusDb.getRouteById(hkbusRouteId) == null) {
          // 尝试 serviceType 2
          final hkbusRouteId2 = '${widget.route}+2+$origEn+$destEn';
          if (hkbusDb.getRouteById(hkbusRouteId2) != null) {
            serviceType = '2';
            hkbusRouteId = hkbusRouteId2;
          } else {
            // 尝试 serviceType 3
            final hkbusRouteId3 = '${widget.route}+3+$origEn+$destEn';
            if (hkbusDb.getRouteById(hkbusRouteId3) != null) {
              serviceType = '3';
              hkbusRouteId = hkbusRouteId3;
            } else {
              // 尝试 serviceType 4
              final hkbusRouteId4 = '${widget.route}+4+$origEn+$destEn';
              if (hkbusDb.getRouteById(hkbusRouteId4) != null) {
                serviceType = '4';
                hkbusRouteId = hkbusRouteId4;
              }
            }
          }
        }
        
        // GMB 不使用 bound 概念，使用默认值
        final bound = 'O';
        
        final variant = {
          'routeId': hkbusRouteId, // 使用 hkbus_db 格式的 routeId（英文）
          'gmbRouteId': gmbRouteId, // 保留 GMB API 的 routeId
          'bound': bound,
          'serviceType': serviceType,
          'orig_tc': gmbVariant['orig_tc'],
          'orig_en': origEn,
          'dest_tc': gmbVariant['dest_tc'],
          'dest_en': destEn,
          'company': 'gmb',
          'gmbRegion': gmbRegion,
        };
        
        debugPrint('  📍 Added GMB variant: $gmbRouteId, region=$gmbRegion, bound=$bound, serviceType=$serviceType');
        variants.add(variant);
      }
      
      if (mounted) {
        setState(() {
          _routeVariants = variants;
          debugPrint('✅ Total GMB variants: ${_routeVariants.length}');
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading GMB variants: $e');
    }
  }

  @override
  void dispose() {
    _etaRefreshTimer?.cancel();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _draggableController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _showMapView = prefs.getBool(_mapViewPreferenceKey) ?? false;
          // Load the Nearby toggle state
          _toggleNearBy = prefs.getBool(_NearByPreferenceKey) ?? false;
        });
        
        // If it was ON, trigger the search once
        if (_toggleNearBy) {
          _getUserLocationAndScrollToNearest(true);
        }
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

  /// 獲取用戶位置，更新最近站點，並滾動到該站點
  /// 參考 hkbus/hk-independent-bus-eta RouteEtaPage.tsx 邏輯：
  /// 排序找距離最小者，而非固定閾值，Nearby badge 另外設 200m 範圍
  Future<void> _getUserLocationAndScrollToNearest(bool jump) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_NearByPreferenceKey, jump);

    // 1. Handle the "Toggle Off" state immediately
    if (!jump) {
      setState(() {
        _nearestStopId = null;     // Clear the nearby indicator
        _nearestDistanceM = null;
        _highlightedStopId = null; // Remove highlighting
        _locationLoading = false;
      });
      return; // Stop here; don't fetch GPS or scroll
    }

    if (!mounted) return;
    setState(() => _locationLoading = true);

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 5),
        ),
      );
      
      if (!mounted) return;
      setState(() => _userPosition = pos);
      
      if (_allStops.isEmpty) return;

      final ranked = _allStops
          .where((s) =>
              s is Map &&
              s['lat'] != null &&
              (s['long'] ?? s['lng']) != null &&
              s['stop'] != null)
          .map((s) {
            final lat = double.tryParse(s['lat'].toString());
            final lng = double.tryParse((s['long'] ?? s['lng']).toString());
            if (lat == null || lng == null) return null;
            final dist = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, lat, lng,
            );
            return (stopId: s['stop'].toString(), distance: dist);
          })
          .whereType<({String stopId, double distance})>()
          .toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));

      if (ranked.isEmpty) return;

      final nearest = ranked.first;

      setState(() {
        _nearestStopId = nearest.stopId;
        _nearestDistanceM = nearest.distance;
        _highlightedStopId = nearest.stopId;
      });

      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightedStopId = null);
      });

      // Only scroll if the toggle is still active
      await _scrollToStop(nearest.stopId);

    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  /// 預先填充 _stopKeys（在 _allStops 更新後呼叫，避免 lazy build 造成 key 缺失）
  void _preFillStopKeys() {
    for (final s in _allStops) {
      final stopId = s['stop']?.toString();
      if (stopId != null && stopId.isNotEmpty) {
        _stopKeys.putIfAbsent(stopId, () => GlobalKey());
      }
    }
  }

  /// 滾動到指定站點：先嘗試 ensureVisible，失敗則 index estimat fallback
  Future<void> _scrollToStop(String stopId) async {
    // 嘗試直接 ensureVisible
    final key = _stopKeys[stopId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Easing.emphasizedDecelerate,
        alignment: 0.2,
      );
      return;
    }

    // Fallback：用 index 估算位置（SliverList lazy build 時 key 可能未存在）
    final idx = _allStops.indexWhere(
        (s) => s['stop']?.toString() == stopId);
    if (idx >= 0 && _scrollController.hasClients) {
      await _scrollController.animateTo(
        idx * 80.0, // 估算每個 card 高度約 80dp
        duration: const Duration(milliseconds: 400),
        curve: Easing.emphasizedDecelerate,
      );
      // 等 widget build 後補做精確 ensureVisible
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final key2 = _stopKeys[stopId];
        if (key2?.currentContext != null) {
          await Scrollable.ensureVisible(
            key2!.currentContext!,
            alignment: 0.2,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
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
      // ✅ fixed: wait for DB ready instead of throwing immediately
      void listener() {
        if (hkbusDb.isReady) {
          hkbusDb.removeListener(listener);
          if (mounted) _fetchFromUnifiedDb();
        }
      }
      hkbusDb.addListener(listener);
      return;
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
      company: _selectedCompany,
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
    final stopGroups = rawGroups.whereType<Map>().toList();

    if (stopGroups.length != rawGroups.length) {
      debugPrint(
        '❌ stopGroups type mismatch: '
        '${rawGroups.map((e) => e.runtimeType).toSet()}',
      );
      debugPrint('sample=${rawGroups.take(5).toList()}');
    }

    List<Map<String, dynamic>> stops = [];

    if (stopGroups.isEmpty) {
      // 通用 fallback：當 stopGroups 為空時，從 route.stopsByCompany 直接構建站點
      // 這處理單一公司路線（如 KMB、CTB、LWB）的 stops 是 List 而非 Map 的情況
      final coKey = _selectedCompany.toLowerCase();
      final rawStops = route.stopsByCompany[coKey] ??
          route.stopsByCompany[route.primaryCompany] ??
          (route.stopsByCompany.isNotEmpty ? route.stopsByCompany.values.first : null);

      stops = _normalizeStops(rawStops, company: coKey);
    } else {
      // 轉換為統一格式，並添加站點座標
      stops = stopGroups.map((group) {
        final _co = _selectedCompany.toLowerCase();  // ✅ fixed: ensure lowercase key
        final stopId = group['${_co}_stop_id'] ??
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
          'gmb_stop_seq': group['gmb_stop_seq'] ?? (seq0 + 1), // ← 新增
          'nlb_stop_id': group['nlb_stop_id'],
          'lat': coords?['lat'],
          'lng': coords?['lng'],
          'long': coords?['lng'],     // ✅ fixed: _buildStopCard reads 'long' first
          'fare': group['fare'],
          'fare_holiday': group['fare_holiday'],
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
      await _loadRouteVariants(); // 加載路線變體（方向和服務類型）
      _preFillStopKeys(); // ✅ 新增
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
        case 'gmb':
          await _fetchGmbData();   // ← 新增
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
    final hkbusDb = context.read<HkbusDbProvider>();

    // 🔍 DEBUG: Trace fetch path
    debugPrint('🔍 _fetchKmbData: using unified DB pattern');

    // 從統一數據庫獲取路線數據
    final routeData = hkbusDb.getRouteByNumber(
      widget.route,
      direction: widget.bound,
      serviceType: widget.serviceType,
      company: _selectedCompany,
    );

    if (routeData == null) {
      throw Exception('Route ${widget.route} not found in unified DB');
    }

    // 獲取 KMB 特定的站點列表
    final kmbStopsRaw = routeData.stopsByCompany['kmb'];
    if (kmbStopsRaw == null) {
      throw Exception('No KMB stops found for route ${widget.route}');
    }

    // 安全地提取站點列表
    List<String> kmbStops = [];
    if (kmbStopsRaw is String) {
      try {
        final parsed = jsonDecode(kmbStopsRaw);
        if (parsed is List) {
          kmbStops = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (kmbStopsRaw is List) {
      kmbStops = kmbStopsRaw.map((e) => e.toString()).toList();
    }

    if (kmbStops.isEmpty) {
      throw Exception('No KMB stops found for route ${widget.route}');
    }

    // 構建站點條目
    final entries = kmbStops.asMap().entries.map((entry) {
      return {
        'seq': entry.key + 1,
        'stop': entry.value,
      };
    }).toList();

    await _processStopEntries(entries, 'kmb');
  }

  Future<void> _fetchCtbData() async {
    final hkbusDb = context.read<HkbusDbProvider>();

    // 🔍 DEBUG: Trace fetch path
    debugPrint('🔍 _fetchCtbData: using unified DB pattern');

    // 從統一數據庫獲取路線數據
    final routeData = hkbusDb.getRouteByNumber(
      widget.route,
      direction: widget.bound,
      serviceType: widget.serviceType,
      company: _selectedCompany,
    );

    if (routeData == null) {
      throw Exception('Route ${widget.route} not found in unified DB');
    }

    // 獲取 CTB 特定的站點列表
    final ctbStopsRaw = routeData.stopsByCompany['ctb'];
    if (ctbStopsRaw == null) {
      throw Exception('No CTB stops found for route ${widget.route}');
    }

    // 安全地提取站點列表
    List<String> ctbStops = [];
    if (ctbStopsRaw is String) {
      try {
        final parsed = jsonDecode(ctbStopsRaw);
        if (parsed is List) {
          ctbStops = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (ctbStopsRaw is List) {
      ctbStops = ctbStopsRaw.map((e) => e.toString()).toList();
    }

    if (ctbStops.isEmpty) {
      throw Exception('No CTB stops found for route ${widget.route}');
    }

    // 構建站點條目
    final entries = ctbStops.asMap().entries.map((entry) {
      return {
        'seq': entry.key + 1,
        'stop': entry.value,
      };
    }).toList();

    await _processStopEntries(entries, 'ctb');
  }


  Future<void> _fetchNlbData() async {
    final hkbusDb = context.read<HkbusDbProvider>();
    
    // 从 HkbusDbProvider 获取路线数据
    final routeData = hkbusDb.getRouteByNumber(
      widget.route,
      direction: widget.bound,
      serviceType: widget.serviceType,
      company: _selectedCompany,
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

  Future<void> _fetchGmbData() async {
    final hkbusDb = context.read<HkbusDbProvider>();

    final routeData = hkbusDb.getRouteByNumber(
      widget.route,
      direction: widget.bound,
      serviceType: widget.serviceType,
      company: _selectedCompany,
    );

    if (routeData == null) {
      throw Exception('Route ${widget.route} not found in unified DB');
    }

    final gmbStopsRaw = routeData.stopsByCompany['gmb'];
    if (gmbStopsRaw == null) {
      throw Exception('No GMB stops found for route ${widget.route}');
    }

    List<String> gmbStops = [];
    if (gmbStopsRaw is String) {
      try {
        final parsed = jsonDecode(gmbStopsRaw);
        if (parsed is List) {
          gmbStops = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (gmbStopsRaw is List) {
      gmbStops = gmbStopsRaw.map((e) => e.toString()).toList();
    }

    if (gmbStops.isEmpty) {
      throw Exception('No GMB stops found for route ${widget.route}');
    }

    final entries = gmbStops.asMap().entries.map((entry) {
      return <String, dynamic>{
        'seq': entry.key + 1,
        'stop': entry.value,
        'gmb_stop_id': entry.value,
        'gmb_stop_seq': entry.key + 1, // 1-based seq for ETA API
      };
    }).toList();

    await _processStopEntries(entries, 'gmb');
  }


  // ✅ 新增 normalizeStops helper - 保證任何來源的 stops 都是 List<Map<String, dynamic>>
  List<Map<String, dynamic>> _normalizeStops(
    dynamic stopsRaw, {
    String? company,
  }) {
    final hkbusDb = context.read<HkbusDbProvider>();
    final List<Map<String, dynamic>> output = [];

    // 🔍 DEBUG: Track input
    debugPrint('🔍 _normalizeStops: input type=${stopsRaw?.runtimeType}, company=$company');
    if (stopsRaw is List && stopsRaw.isNotEmpty) {
      debugPrint('🔍 _normalizeStops: first item type=${stopsRaw.first?.runtimeType}');
    }

    if (stopsRaw == null) {
      debugPrint('🔍 _normalizeStops: returning empty (null input)');
      return output;
    }

    // 如果係 String，先嘗試 Decode
    if (stopsRaw is String) {
      try {
        final decoded = jsonDecode(stopsRaw);
        // Decode 完再 call 自己
        return _normalizeStops(decoded, company: company);
      } catch (e) {
        debugPrint('❌ _normalizeStops: Failed to decode string: $stopsRaw');
        return output;
      }
    }

    // 如果係 List
    if (stopsRaw is List) {
      debugPrint('🔍 _normalizeStops: processing List with ${stopsRaw.length} items');
      for (int i = 0; i < stopsRaw.length; i++) {
        final item = stopsRaw[i];

        if (item == null) {
          debugPrint('🔍 _normalizeStops: item $i is null, skipping');
          continue;
        }

        // Case A: 已經係 Map (API 格式) — enrich missing fields
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final sid = m['stop']?.toString();
          if (sid != null && sid.isNotEmpty) {
            m['name_tc'] ??= hkbusDb.getStopName(sid, isEnglish: false);  // ✅ fixed: enrich
            m['name_en'] ??= hkbusDb.getStopName(sid, isEnglish: true);
            if (m['lat'] == null || m['lng'] == null) {
              final c = hkbusDb.getStopCoordinates(sid);
              m['lat'] ??= c?['lat'];
              m['lng'] ??= c?['lng'];
              m['long'] ??= c?['lng'];
            }
          }
          output.add(m);
          continue;
        }

        // Case B: 係 stopId String（Unified DB 的 stopsByCompany 格式）
        final stopId = item.toString();
        if (stopId.isEmpty) {
          debugPrint('🔍 _normalizeStops: item $i has empty stopId, skipping');
          continue;
        }

        debugPrint('🔍 _normalizeStops: item $i is String stopId=$stopId');
        final coords = hkbusDb.getStopCoordinates(stopId);
        output.add({
          'seq': i + 1,
          'stop': stopId,
          'name_tc': hkbusDb.getStopName(stopId, isEnglish: false),
          'name_en': hkbusDb.getStopName(stopId, isEnglish: true),
          'kmb_stop_id': company == 'kmb' ? stopId : null,
          'ctb_stop_id': company == 'ctb' ? stopId : null,
          'gmb_stop_id': company == 'gmb' ? stopId : null,
          'gmb_stop_seq': company == 'gmb' ? (i + 1) : null, // ← 補上
          'nlb_stop_id': company == 'nlb' ? stopId : null,
          'lat': coords?['lat'],
          'lng': coords?['lng'],
          'long': coords?['lng'],
        });
      }
    } else if (stopsRaw is Map) {
      debugPrint('🔍 _normalizeStops: input is Map, attempting to extract company=$company');
       // 如果有人傳錯咗成個 Map 入嚟，例如 {"kmb": ["stop1", "stop2"]}
       final coKey = company?.toLowerCase() ?? 'kmb';
       if (stopsRaw.containsKey(coKey)) {
         debugPrint('🔍 _normalizeStops: extracting company=$coKey from Map');
         return _normalizeStops(stopsRaw[coKey], company: company);
       } else if (stopsRaw.isNotEmpty) {
         debugPrint('🔍 _normalizeStops: extracting first value from Map');
         return _normalizeStops(stopsRaw.values.first, company: company);
       }
    }

    debugPrint('🔍 _normalizeStops: returning ${output.length} stops');
    return output;
  }

  void _startEtaRefreshLoopIfNeeded() {
    if (_etaRefreshTimer != null || _expandedStopsById.isEmpty) return;

    _etaRefreshTimer = Timer.periodic(_etaRefreshInterval, (_) {
      _refreshExpandedStops();
    });
  }

  void _stopEtaRefreshLoopIfIdle() {
    if (_expandedStopsById.isNotEmpty) return;

    _etaRefreshTimer?.cancel();
    _etaRefreshTimer = null;
  }

  Future<void> _refreshExpandedStops() async {
    if (!mounted || _expandedStopsById.isEmpty || _etaRefreshInFlight) return;

    _etaRefreshInFlight = true;
    try {
      final expandedStops = _expandedStopsById.values.toList(growable: false);

      for (final stop in expandedStops) {
        await _fetchEtaForSingleStop(
          stop,
          force: true,
          showLoading: false,
        );
      }
    } finally {
      _etaRefreshInFlight = false;
    }
  }

  void _handleStopExpansionChange(Map<String, dynamic> stop, bool isExpanded) {
    final stopId = stop['stop']?.toString();
    if (stopId == null || stopId.isEmpty) return;

    if (isExpanded) {
      _expandedStopsById[stopId] = Map<String, dynamic>.from(stop);
      _startEtaRefreshLoopIfNeeded();

      final hasCache = _etaByStopId[stopId]?.isNotEmpty ?? false;

      _fetchEtaForSingleStop(
        stop,
        force: hasCache,
        showLoading: !hasCache,
      );
    } else {
      _expandedStopsById.remove(stopId);
      _stopEtaRefreshLoopIfIdle();
    }
  }

  void _resetExpandedEtaTracking({bool clearEtaCache = false}) {
    _etaRefreshTimer?.cancel();
    _etaRefreshTimer = null;
    _etaRefreshInFlight = false;

    _expandedStopsById.clear();
    _etaLoadingByStopId.clear();
    _etaRefreshingByStopId.clear();

    if (clearEtaCache) {
      _etaByStopId.clear();
    }
  }



  Future<void> _processStopEntries(List<Map<String, dynamic>> entries, String company) async {
    if (!mounted) return;
    
    // 🔍 DEBUG: Track input
    debugPrint('🔍 _processStopEntries: entries=${entries.length}, company=$company');
    if (entries.isNotEmpty) {
      debugPrint('🔍 _processStopEntries: first entry=${entries.first}');
    }
    
    final hkbusDb = context.read<HkbusDbProvider>();
    
    // 過濾和排序
    entries = entries.where((e) => e.containsKey('seq')).toList();
    debugPrint('🔍 _processStopEntries: after filter=${entries.length}');
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
    debugPrint('🔍 _processStopEntries: enriched=${enriched.length}');
    if (enriched.isNotEmpty) {
      debugPrint('🔍 _processStopEntries: first enriched=${enriched.first}');
    }

    // Normalize stops to ensure consistent format
    final normalizedStops = _normalizeStops(enriched, company: company);
    debugPrint('🔍 _processStopEntries: normalized=${normalizedStops.length}');

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
      _preFillStopKeys(); // ✅ 新增
      debugPrint('🔍 _processStopEntries: setState called with ${normalizedStops.length} stops');
    }

  }

  /// 獲取單一站點的 ETA（僅在展開時呼叫）
  ///
  /// 處理所有數據類型：
  /// - KMB: 16-char hex stop ID, service_type
  /// - CTB: 6-digit stop ID
  /// - NLB: String int stop ID + routeId
  /// - GMB: Integer stop ID + route_id + route_seq
  Future<void> _fetchEtaForSingleStop(
    Map<String, dynamic> stop, {
    bool force = false,
    bool showLoading = true,
  }) async {
    final stopId = stop['stop']?.toString();
    if (stopId == null || stopId.isEmpty) return;

    final hasCachedEta = _etaByStopId.containsKey(stopId) &&
        _etaByStopId[stopId]!.isNotEmpty;

    if (!force && hasCachedEta) {
      debugPrint('📦 ETA memory cache hit for stop: $stopId');
      return;
    }

    if (_etaLoadingByStopId.contains(stopId) ||
        _etaRefreshingByStopId.contains(stopId)) {
      return;
    }

    if (_routeContext == null) {
      debugPrint('⚠️ Route context not initialized, initializing now...');
      await _initializeRouteContext();
    }

    final busySet =
        showLoading ? _etaLoadingByStopId : _etaRefreshingByStopId;

    if (mounted) {
      setState(() => busySet.add(stopId));
    }

    try {
      List<UnifiedEta> etas = [];

      if (widget.companies.length > 1 && widget.useUnifiedDb) {
        etas = await _fetchJointOperationEtas(stop);
      } else {
        final co = _selectedCompany.toLowerCase();
        final companyStopId =
            stop['${co}_stop_id']?.toString() ?? stopId;

        // ── GMB 專用：用 stop-level RouteContext 帶入 stop_seq ──
        RouteContext effectiveContext =
            _routeContext ?? RouteContext(routeNumber: widget.route);

        if (co == 'gmb') {
          final rawSeq = stop['gmb_stop_seq'];
          final stopSeq = rawSeq is int
              ? rawSeq
              : int.tryParse(rawSeq?.toString() ?? '') ?? 0;

          effectiveContext = effectiveContext.copyWith(gmbStopSeq: stopSeq);
        }



        etas = await _etaService.fetchEta(
          company: _selectedCompany,
          routeNumber: widget.route,
          stopId: companyStopId,
          routeContext: effectiveContext,  // ← 用 effectiveContext 而非 _routeContext
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
        setState(() => busySet.remove(stopId));
      }
    }
  }

  /// 獲取聯營路線的所有公司 ETA
  Future<List<UnifiedEta>> _fetchJointOperationEtas(
    Map<String, dynamic> stop,
  ) async {
    final companyEtasMap = <String, List<UnifiedEta>>{};
    final futures = <Future<void>>[];

    for (final company in widget.companies) {
      // 每間公司必須用自己的 stop ID，不允許跨公司 fallback
      final coKey = '${company.toLowerCase()}_stop_id';
      final companyStopId = stop[coKey]?.toString();

      if (companyStopId == null || companyStopId.isEmpty) {
        debugPrint('⚠️ No ${company} stop ID in stop map (key=$coKey), skipping');
        companyEtasMap[company] = [];
        continue;
      }

      futures.add(
        _etaService
            .fetchEta(
          company: company,
          routeNumber: widget.route,
          stopId: companyStopId,
          routeContext:
              _routeContext ?? RouteContext(routeNumber: widget.route),
        )
            .then((companyEtas) {
          companyEtasMap[company] = companyEtas
              .map((eta) => UnifiedEta(
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
                  ))
              .toList();
        }).catchError((e) {
          debugPrint('❌ Failed to fetch ETA for $company: $e');
          companyEtasMap[company] = [];
        }),
      );
    }

    await Future.wait(futures);

    // 合併並按時間排序
    final allEtas = companyEtasMap.values.expand((e) => e).toList()
      ..sort((a, b) => a.eta.compareTo(b.eta));

    return allEtas;
  }

  /// 過濾掉距現在 ≤10 秒（即將或已離站）的 ETA
  /// isRealtime = true 時才過濾，預測班次不過濾（避免全空）
  List<UnifiedEta> _filterValidEtas(List<UnifiedEta> etas) {
    final now = DateTime.now();
    return etas.where((eta) {
      final diffSec = eta.eta.difference(now).inSeconds;
      // realtime: 必須 >10 秒才顯示
      // non-realtime / scheduled: 直接顯示（只過濾負數離站）
      if (eta.isRealtime) {
        return diffSec > 15;
      } else {
        return diffSec > -30; // 預測班次寬容 30 秒
      }
    }).toList();
  }


  /// 切換運營公司
  void _onCompanyChanged(String company) {
    if (company == _selectedCompany) return;

    setState(() {
      _selectedCompany = company;
      _resetExpandedEtaTracking(clearEtaCache: true);
    });

    _fetchData();
  }

  /// 选择路线变体
  void _onRouteVariantSelected(Map<String, dynamic> variant) {
    final company = variant['company'] as String? ?? '';
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => UnifiedRouteStatusPage(
          route: widget.route,
          companies: widget.companies,
          initialCompany: _selectedCompany,
          bound: variant['bound'] as String?,
          serviceType: variant['serviceType'] as String?,
          initialRouteId: variant['routeId'] as String?,
          useUnifiedDb: true,
        ),
      ),
    );
  }

  /// 构建路线变体卡片
  Widget _buildRouteVariantCard(Map<String, dynamic> variant, bool isEnglish) {
    final theme = Theme.of(context);
    final bound = variant['bound'] as String?;
    final serviceType = variant['serviceType'] as String?;
    final orig = isEnglish 
        ? (variant['orig_en'] ?? variant['orig_tc'] ?? '') 
        : (variant['orig_tc'] ?? variant['orig_en'] ?? '');
    final dest = isEnglish 
        ? (variant['dest_en'] ?? variant['dest_tc'] ?? '') 
        : (variant['dest_tc'] ?? variant['dest_en'] ?? '');
    
    // 方向标签
    String directionLabel = bound == 'O'
        ? (isEnglish ? 'Outbound' : '去程')
        : (bound == 'I' 
            ? (isEnglish ? 'Inbound' : '回程')
            : (bound ?? ''));
    
    // 服务类型标签（徽章样式）
    String serviceTypeLabel = '普通';
    final company = variant['company'] as String? ?? '';
    Color serviceTypeBgColor = theme.colorScheme.secondaryContainer;
    Color serviceTypeTextColor = theme.colorScheme.onSecondaryContainer;
    
    if (company.toLowerCase() == 'gmb') {
      // GMB: 显示地区名称
      final gmbRegion = variant['gmbRegion'] as String?;
      serviceTypeLabel = _getGmbRegionName(gmbRegion, isEnglish);
      serviceTypeBgColor = theme.colorScheme.tertiaryContainer;
      serviceTypeTextColor = theme.colorScheme.onTertiaryContainer;
    } else {
      // 其他公司: 显示服务类型
      switch (serviceType) {
        case '1': 
          serviceTypeLabel = isEnglish ? 'Ordinary' : '普通';
          serviceTypeBgColor = theme.colorScheme.secondaryContainer;
          serviceTypeTextColor = theme.colorScheme.onSecondaryContainer;
          break;
        case '2': 
          serviceTypeLabel = isEnglish ? 'Express' : '特快';
          serviceTypeBgColor = theme.colorScheme.primaryContainer;
          serviceTypeTextColor = theme.colorScheme.onPrimaryContainer;
          break;
        case '3': 
          serviceTypeLabel = isEnglish ? 'Holiday' : '假日';
          serviceTypeBgColor = theme.colorScheme.errorContainer;
          serviceTypeTextColor = theme.colorScheme.onErrorContainer;
          break;
        case '4': 
          serviceTypeLabel = isEnglish ? 'Night' : '通宵';
          serviceTypeBgColor = theme.colorScheme.surfaceVariant;
          serviceTypeTextColor = theme.colorScheme.onSurfaceVariant;
          break;
      }
    }
    
    // 检查是否是当前选中的变体
    final isSelected = variant['routeId'] == widget.initialRouteId ||
                       (bound == widget.bound && serviceType == widget.serviceType);
    
    return GestureDetector(
      onTap: () => _onRouteVariantSelected(variant),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.colorScheme.primaryContainer 
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? theme.colorScheme.primary 
                : theme.colorScheme.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 方向指示器
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                directionLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 路线信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        orig,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        dest,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 服务类型徽章
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: serviceTypeBgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      serviceTypeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: serviceTypeTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 选中指示器
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  /// 判断是否应该显示路线变体切换器
  bool _shouldShowVariantSwitcher() {
    if (_routeVariants.isEmpty) return false;
    
    final firstCompany = _routeVariants.first['company'] as String? ?? '';
    
    if (firstCompany.toLowerCase() == 'gmb') {
      // GMB: 检查是否有多个不同的地区
      final regions = _routeVariants
          .map((v) => v['gmbRegion'] as String?)
          .whereType<String>()
          .toSet();
      return regions.length > 1;
    } else {
      // 其他公司: 检查是否有多个不同的方向或服务类型
      final bounds = _routeVariants
          .map((v) => v['bound'] as String?)
          .whereType<String>()
          .toSet();
      final serviceTypes = _routeVariants
          .map((v) => v['serviceType'] as String?)
          .whereType<String>()
          .toSet();
      return bounds.length > 1 || serviceTypes.length > 1;
    }
  }

  /// 获取 GMB 地区名称
  String _getGmbRegionName(String? region, bool isEnglish) {
    if (region == null) return 'GMB';
    switch (region.toUpperCase()) {
      case 'HKI':
        return isEnglish ? 'Hong Kong Island' : '香港島';
      case 'KLN':
        return isEnglish ? 'Kowloon' : '九龍';
      case 'NT':
        return isEnglish ? 'New Territories' : '新界';
      default:
        return region;
    }
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
                : Icon(
                    _toggleNearBy ? Icons.near_me : Icons.near_me_outlined,
                    color: _toggleNearBy ? Colors.blue : null,
                  ),
            tooltip: (isEnglish ? 'Scroll to nearest stop' : '滾動至最近站點'),
            onPressed: (_locationLoading || _allStops.isEmpty)
                ? null 
                : () {
                    // Simply toggle and trigger the function
                    final newState = !_toggleNearBy;
                    setState(() => _toggleNearBy = newState);
                    _getUserLocationAndScrollToNearest(newState);
                  },
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

    // 🔍 DEBUG: Track stops data
    debugPrint('🔍 _buildListView: stops length=${stops.length}, type=${stops.runtimeType}');
    if (stops.isNotEmpty) {
      debugPrint('🔍 _buildListView: first stop type=${stops.first.runtimeType}, value=${stops.first}');
      if (stops.first is Map) {
        debugPrint('🔍 _buildListView: first stop keys=${(stops.first as Map).keys.toList()}');
      }
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (!devSettings.useFloatingRouteToggles)
          SliverToBoxAdapter(child: _buildHeader(isEnglish)),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              // 🔍 DEBUG: Track index access
              try {
                debugPrint('🔍 SliverChildBuilderDelegate: index=$index (type=${index.runtimeType}), stops.length=${stops.length}');
                if (index < 0 || index >= stops.length) {
                  debugPrint('❌ Index out of bounds: index=$index, length=${stops.length}');
                  return const SizedBox.shrink();
                }
                final stop = stops[index];
                debugPrint('🔍 Accessed stop at index=$index: type=${stop.runtimeType}');
                if (stop is! Map<String, dynamic>) {
                  debugPrint('❌ Stop is not Map<String, dynamic>: ${stop.runtimeType} = $stop');
                  return const SizedBox.shrink();
                }
                return _buildStopCard(stop, index.toString(), isEnglish);
              } catch (e, stackTrace) {
                debugPrint('❌ Error accessing stops[$index]: $e');
                debugPrint('❌ Stack trace: $stackTrace');
                return Card(
                  margin: const EdgeInsets.all(8),
                  color: Colors.red.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error at index $index: $e'),
                  ),
                );
              }
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

  Widget _buildStopCard(Map<String, dynamic> stop, String index, bool isEnglish) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final companyProv = context.read<CompanyProvider>();

    final stopId = stop['stop']?.toString() ?? '';
    final seq = stop['seq']?.toString() ?? '';
    final fare = stop['fare']?.toString() ?? '';

    final name = isEnglish
    ? (stop['name_en'].toString().toTitleCase() ?? stop['name_tc'] ?? stopId)
    : (stop['name_tc'] ?? stop['name_en'].toString().toTitleCase() ?? stopId);


    final etas = _etaByStopId[stopId] ?? <UnifiedEta>[];
    final etaLoading = _etaLoadingByStopId.contains(stopId);
    final isNearby = _isNearbyStop(stopId);
    final isHighlighted = _highlightedStopId == stopId;

    final nearbyDistStr = isNearby && _nearestDistanceM != null
        ? '${_nearestDistanceM!.round()}m'
        : null;

    final shouldAutoExpand =
        (widget.autoExpandSeq != null && seq == widget.autoExpandSeq) ||
        (widget.autoExpandStopId != null && stopId == widget.autoExpandStopId);

    if (shouldAutoExpand && !_expandedStopsById.containsKey(stopId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleStopExpansionChange(stop, true);
      });
    }


    return AnimatedContainer(
      key: _stopKeys.putIfAbsent(stopId, () => GlobalKey()),
      duration: const Duration(milliseconds: 220),
      curve: MotionConstants.emphasizedEasing,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        elevation: isHighlighted ? 4 : (isNearby ? 2 : 0),
        shadowColor: isNearby
            ? cs.tertiary.withValues(alpha: 0.20)
            : theme.shadowColor.withValues(alpha: 0.08),
        clipBehavior: Clip.antiAlias,
        color: isNearby
            ? cs.tertiaryContainer.withValues(alpha: 0.42)
            : isHighlighted
                ? cs.primaryContainer.withValues(alpha: 0.22)
                : cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isNearby
                ? cs.tertiary
                : isHighlighted
                    ? cs.primary.withValues(alpha: 0.35)
                    : Colors.transparent,
            width: (isNearby || isHighlighted) ? 1.4 : 1,
          ),
        ),
        child: Theme(
          data: theme.copyWith(
            dividerColor: Colors.transparent,
            splashColor: cs.primary.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: shouldAutoExpand,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            // ✅ 新版 — 統一走 _handleStopExpansionChange
            onExpansionChanged: (isExpanded) =>
              _handleStopExpansionChange(stop, isExpanded),

            leading: _buildStopLeading(
              seq: seq,
              isNearby: isNearby,
              isHighlighted: isHighlighted,
              colorScheme: cs,
              theme: theme,
            ),
            title: OptionalMarquee(
              text: name,
              style: theme.textTheme.titleSmall!.copyWith(
                fontWeight: isNearby ? FontWeight.w800 : FontWeight.w600,
                color: cs.onSurface,
                height: 1.2,
              ),
            ),
            subtitle: _buildStopSubtitle(
              isEnglish: isEnglish,
              fare: fare,
              isNearby: isNearby,
              nearbyDistStr: nearbyDistStr,
              etaPreview: null,//etas.isNotEmpty ? _formatEtaList(etas) : null,
              colorScheme: cs,
              theme: theme,
            ),
            children: [
              _buildExpandedStopContent(
                stopId: stopId,
                isEnglish: isEnglish,
                etaLoading: etaLoading,
                etas: etas,
                companyProv: companyProv,
                colorScheme: cs,
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopLeading({
    required String seq,
    required bool isNearby,
    required bool isHighlighted,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNearby
            ? colorScheme.tertiary
            : isHighlighted
                ? colorScheme.primaryContainer
                : colorScheme.primary,
      ),
      child: Center(
        child: Text(
          seq,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isNearby
                ? colorScheme.onTertiary
                : isHighlighted
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildStopSubtitle({
    required bool isEnglish,
    required String fare,
    required bool isNearby,
    required String? nearbyDistStr,
    required String? etaPreview,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (isNearby)
                _buildInfoChip(
                  label: nearbyDistStr != null
                      ? (isEnglish
                          ? 'Nearby · $nearbyDistStr'
                          : '附近 · $nearbyDistStr')
                      : (isEnglish ? 'Nearby' : '附近'),
                  backgroundColor: colorScheme.tertiary,
                  foregroundColor: colorScheme.onTertiary,
                  icon: Icons.near_me_rounded,
                  theme: theme,
                ),
              if (fare.isNotEmpty)
                _buildInfoChip(
                  label: '\$$fare',
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                  icon: Icons.payments_outlined,
                  theme: theme,
                ),
            ],
          ),
          if (etaPreview != null && etaPreview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              etaPreview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required ThemeData theme,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedStopContent({
    required String stopId,
    required bool isEnglish,
    required bool etaLoading,
    required List<UnifiedEta> etas,
    required CompanyProvider companyProv,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 18,
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
          if (etaLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEnglish ? 'Loading ETA...' : '載入到站時間...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else if (widget.companies.length > 1) ...[
            Text(
              isEnglish ? 'All Operators' : '所有營運商',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 10),
            ...widget.companies.map(
              (co) => _buildOperatorEtaRow(
                company: co,
                stopId: stopId,
                isEnglish: isEnglish,
                companyProv: companyProv,
                theme: theme,
                colorScheme: colorScheme,
              ),
            ),
          ] else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: etas.isNotEmpty 
                  ? _buildEtaList(etas, isEnglish)
                  : [
                      Text(
                        lang.endEta,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${isEnglish ? 'Stop ID' : '站點 ID'}: $stopId',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    // 添加 Material 3 弹跳效果
    return content
        .animate()
        .slideY(
          begin: -0.1,
          end: 0,
          duration: MotionConstants.contentTransition,
          curve: MotionConstants.bounceInEasing,
        )
        .fadeIn(
          duration: MotionConstants.contentTransition * 0.6,
          curve: MotionConstants.fadeInEasing,
        );
  }

  Widget _buildOperatorEtaRow({
    required String company,
    required String stopId,
    required bool isEnglish,
    required CompanyProvider companyProv,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final allEtas = _etaByStopId[stopId] ?? <UnifiedEta>[];
    final coEtas = _filterValidEtas(
        allEtas
        .where((eta) => eta.company.toLowerCase() == company.toLowerCase())
        .toList(),
      );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: companyProv.getBadgeBorderColor(company, context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              companyProv.getName(company, isEnglish),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: coEtas.isNotEmpty 
                  ? _buildEtaList(coEtas, isEnglish)
                  : [
                      Text(
                        lang.endEta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }



  /// 檢查站點是否在附近（約 150 米內）
  bool _isNearbyStop(String stopId) {
    return _nearestStopId == stopId &&
        (_nearestDistanceM ?? double.infinity) < _nearbyBadgeRange;
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

    final valid = _filterValidEtas(etas);
    if (valid.isEmpty) {
      return lang.endEta;
    }

    return valid.take(3).map((eta) => eta.formatDisplay(isEnglish)).join(' · ');
  }

  /// 构建 ETA widget 列表（每行一个 ETA，remark 显示在同一行）
  List<Widget> _buildEtaList(List<UnifiedEta> etas, bool isEnglish) {
    if (etas.isEmpty) return [];

    final lang = context.read<LanguageProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final valid = _filterValidEtas(etas);
    if (valid.isEmpty) {
      return [
        Text(
          lang.endEta,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ];
    }

    return valid.take(3).map((eta) {
      // 获取本地化的 remark
      final remark = isEnglish ? eta.remarkEn : eta.remarkTc;
      
      return Text(
        eta.formatDisplay(isEnglish, remark: remark),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      );
    }).toList();
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

    // Get route origin and destination
    final orig = isEnglish
        ? (data?['orig_en'] ?? data?['orig_tc'] ?? '')
        : (data?['orig_tc'] ?? data?['orig_en'] ?? '');
    final dest = isEnglish
        ? (data?['dest_en'] ?? data?['dest_tc'] ?? '')
        : (data?['dest_tc'] ?? data?['dest_en'] ?? '');

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
                
                // 方向指示器（路线起点和终点）
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.15),
                          width: 1.0,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            // 路线号和公司
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.route,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        Text(
                                          companyProv.getName(_selectedCompany, isEnglish),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.directions_bus,
                                      color: theme.colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            // 路线起点和终点
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 起点
                                  if (orig.isNotEmpty) ...[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '${isEnglish ? 'From' : '由'}:  ',
                                          style: TextStyle(
                                            letterSpacing: -0.05,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w400,
                                            height: 1,
                                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.88),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            orig,
                                            style: TextStyle(
                                              letterSpacing: -0.05,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              height: 1,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  // 终点
                                  if (dest.isNotEmpty) ...[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '${isEnglish ? 'To' : '往'}:  ',
                                          style: TextStyle(
                                            letterSpacing: -0.05,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w400,
                                            height: 1,
                                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.88),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            dest,
                                            style: TextStyle(
                                              letterSpacing: -0.05,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              height: 1,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
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
                
                // 路线变体列表（如果存在多个变体）
                if (_shouldShowVariantSwitcher()) ...[
                  const SizedBox(height: 12),
                  Text(
                    isEnglish ? 'Route Variants' : '路線變體',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._routeVariants.map((variant) => _buildRouteVariantCard(variant, isEnglish)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
