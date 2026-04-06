import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lrt_next_train/toTitleCase.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/location_provider.dart';

import 'kmb/api/mtr_bus.dart';

import 'hkbus_db_provider.dart';
import 'kmb/company_name.dart';
import 'main.dart' show LanguageProvider, DeveloperSettingsProvider, MotionConstants, ConnectivityProvider;
import 'optionalMarquee.dart';
import 'services/route_id_resolver.dart';
import 'services/unified_eta_service.dart';
import 'widgets/route_sheet/draggable_route_sheet.dart';

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
  /// ✅ NEW: Accept pre-fetched location from navigation
  final Position? initialLocation;

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
    this.initialLocation,
  });

  @override
  State<UnifiedRouteStatusPage> createState() => _UnifiedRouteStatusPageState();
}

class _UnifiedRouteStatusPageState extends State<UnifiedRouteStatusPage> 
    with WidgetsBindingObserver {
  static const String _mapViewPreferenceKey = 'unified_route_status_map_view_enabled';
  static const String _nearbyPreferenceKey = 'unified_route_status_nearby_enabled';
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

  // ✅ Connectivity provider for network state checking
  late final ConnectivityProvider _connectivity;

  @override
  void initState() {
    super.initState();
    // ✅ Add WidgetsBindingObserver for lifecycle management
    WidgetsBinding.instance.addObserver(this);
    
    // 確保是單一公司代碼（避免 "kmb+ctb" 這樣的組合值）
    _selectedCompany = (widget.initialCompany ?? widget.companies.first).toLowerCase().split('+').first;  // ✅ fixed: ensure lowercase
    _loadPreferences(); // Combined preference loader
    _initializeLocation();
    _initializeRouteContext();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ Watch ConnectivityProvider for network state changes
    _connectivity = context.watch<ConnectivityProvider>();
  }

  /// 初始化路線上下文（解析各公司 route ID）
  Future<void> _initializeRouteContext() async {
    try {
      await _routeIdResolver.initialize();

      if (!mounted) return;

      final hkbusDb = context.read<HkbusDbProvider>();
      
      UnifiedBusRoute? routeData;
      
      // ✅ 如果 initialRouteId 看起來像 NLB routeId（不包含 "+"），使用 getRouteByNlbId 查找
      if (widget.initialRouteId != null && !widget.initialRouteId!.contains('+')) {
        routeData = hkbusDb.getRouteByNlbId(widget.initialRouteId!);
        debugPrint('🔍 Using getRouteByNlbId for ${widget.initialRouteId}: ${routeData != null ? "found" : "not found"}');
      }
      
      // ✅ 如果找不到或不是 NLB routeId，使用原始邏輯
      if (routeData == null && widget.initialRouteId != null) {
        routeData = hkbusDb.getRouteById(widget.initialRouteId!);
      }
      
      // ✅ 最後回退到 getRouteByNumber
      routeData ??= hkbusDb.getRouteByNumber(
        widget.route,
        direction: widget.bound,
        serviceType: widget.serviceType,
        company: _selectedCompany,
      );

      if (routeData != null) {
        final bound = _getBoundFromRouteData(routeData);
        
        _resolvedRouteIds = await _routeIdResolver.resolveRouteIds(
          hkbusRouteId: routeData.routeId,
          routeNumber: widget.route,
          companies: widget.companies,
          bound: bound, // ✅ 传递 bound 参数用于 NLB 方向匹配
        );

        if (!mounted) return;

        // ✅ For MTR Heavy Rail: routeNumber IS the lineCode (e.g., "TML", "TKL")
        String? mtrLineCode;
        if (_selectedCompany.toLowerCase() == 'mtr') {
          mtrLineCode = widget.route; // routeNumber is the 3-letter line code
          debugPrint('🚆 MTR Heavy Rail detected: routeNumber="$widget.route" → mtrLineCode="$mtrLineCode"');
        }

        // 構建 RouteContext
        _routeContext = RouteContext(
          routeNumber: widget.route,
          bound: bound,
          serviceType: widget.serviceType ?? '1',
          nlbRouteId: _resolvedRouteIds?.nlbRouteId,
          gmbRouteId: _resolvedRouteIds?.gmbRouteId,
          gmbRegion: _resolvedRouteIds?.gmbRegion,
          gmbRouteSeq: 1, // 默認第一個方向
          mtrLineCode: mtrLineCode, // ✅ Set mtrLineCode for MTR Heavy Rail
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
    
    // 收集所有路线变体（NLB/GMB 等常缺 bound 欄位，需與 getRouteByNumber 一致推斷 O/I）
    final variants = <Map<String, dynamic>>[];
    for (final route in matches) {
      for (final company in route.companies) {
        if (company.toLowerCase() != _selectedCompany.toLowerCase()) continue;
        final bound = hkbusDb.inferBoundForRoute(route, company.toLowerCase(), matches);
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

      if (!mounted) return;

      final gmbVariants = await routeIdResolver.getGmbRouteVariants(widget.route);

      if (!mounted) return;

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
        
        final routeSeqRaw = gmbVariant['route_seq'];
        final routeSeq = routeSeqRaw is int
            ? routeSeqRaw
            : int.tryParse(routeSeqRaw?.toString() ?? '') ?? 1;
        final bound = routeSeq <= 1 ? 'O' : 'I';

        final variant = {
          'routeId': hkbusRouteId, // 使用 hkbus_db 格式的 routeId（英文）
          'gmbRouteId': gmbRouteId, // 保留 GMB API 的 routeId
          'gmbRouteSeq': routeSeq,
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
    // ✅ Remove WidgetsBindingObserver
    WidgetsBinding.instance.removeObserver(this);
    
    // ✅ Stop ETA refresh loop before disposing
    _stopEtaRefreshLoop();
    
    _etaRefreshTimer?.cancel();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _draggableController.dispose();
    super.dispose();
  }

  /// ✅ Handle app lifecycle state changes (background/foreground)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // ✅ App returned to foreground: resume refresh and fetch visible stops immediately
        if (_expandedStopsById.isNotEmpty) {
          debugPrint('📱 App resumed, starting ETA refresh loop');
          _startEtaRefreshLoopIfNeeded();
          _refreshExpandedStops(); // Immediate refresh for visible stops
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // ✅ App went to background: stop refresh to save battery and network
        debugPrint('📱 App went to background, stopping ETA refresh loop');
        _stopEtaRefreshLoop();
        break;
      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
  }
  
  /// ✅ Stop ETA refresh loop (called on background/hidden/dispose)
  void _stopEtaRefreshLoop() {
    if (_etaRefreshTimer != null) {
      _etaRefreshTimer!.cancel();
      _etaRefreshTimer = null;
      debugPrint('⏸️ ETA refresh loop stopped');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _showMapView = prefs.getBool(_mapViewPreferenceKey) ?? false;
          // Load the Nearby toggle state
          _toggleNearBy = prefs.getBool(_nearbyPreferenceKey) ?? false;
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

  /// Initialize location from LocationProvider
  /// 
  /// Uses pre-fetched location from global provider instead of fetching again
  Future<void> _initializeLocation() async {
    try {
      // ✅ Use passed location first (fastest)
      if (widget.initialLocation != null) {
        setState(() => _userPosition = widget.initialLocation);
        debugPrint('✅ Using passed location from navigation');
        return;
      }
      
      // Fallback to provider
      final locationProvider = context.read<LocationProvider>();
      
      // Use pre-fetched location from provider
      if (locationProvider.hasLocation) {
        setState(() => _userPosition = locationProvider.currentPosition);
        debugPrint('✅ Using pre-fetched location from LocationProvider');
      }
      
      // If no location available, try to refresh
      if (_userPosition == null && locationProvider.hasPermission) {
        await locationProvider.refreshLocation();
        if (locationProvider.hasLocation) {
          setState(() => _userPosition = locationProvider.currentPosition);
        }
      }
    } catch (e) {
      debugPrint('❌ Error initializing location from provider: $e');
    }
  }

  /// 獲取用戶位置，更新最近站點，並滾動到該站點
  /// 參考 hkbus/hk-independent-bus-eta RouteEtaPage.tsx 邏輯：
  /// 排序找距離最小者，而非固定閾值，Nearby badge 另外設 200m 範圍
  /// 
  /// ✅ OPTIMIZED: Uses pre-fetched location from LocationProvider
  /// instead of fetching location again
  Future<void> _getUserLocationAndScrollToNearest(bool jump) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nearbyPreferenceKey, jump);

    // 1. Handle the "Toggle Off" state immediately
    if (!jump) {
      setState(() {
        _nearestStopId = null;
        _nearestDistanceM = null;
        _highlightedStopId = null;
        _locationLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _locationLoading = true);

    try {
      // ✅ OPTIMIZED: Use pre-fetched location from provider
      final locationProvider = context.read<LocationProvider>();
      Position? pos = locationProvider.currentPosition;
      
      // If no location available, try to refresh
      if (pos == null && locationProvider.hasPermission) {
        await locationProvider.refreshLocation();
        pos = locationProvider.currentPosition;
      }
      
      // Handle permission denied
      if (pos == null && locationProvider.permissionDenied) {
        if (mounted) {
          setState(() => _locationLoading = false);
        }
        // Optionally show permission request dialog
        return;
      }
      
      if (pos == null) {
        if (mounted) {
          setState(() => _locationLoading = false);
        }
        return;
      }
      
      if (!mounted) return;
      setState(() => _userPosition = pos);
      
      if (_allStops.isEmpty) return;

      final ranked = _allStops
          .where((s) =>
              s['lat'] != null &&
              (s['long'] ?? s['lng']) != null &&
              s['stop'] != null)
          .map((s) {
            final lat = double.tryParse(s['lat'].toString());
            final lng = double.tryParse((s['long'] ?? s['lng']).toString());
            if (lat == null || lng == null) return null;
            // pos is guaranteed to be non-null at this point
            final dist = Geolocator.distanceBetween(
              pos!.latitude, pos!.longitude, lat, lng,
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
    
    // Clear stale caches when fetching new data to prevent wrong ETA being shown
    _resetExpandedEtaTracking(clearEtaCache: true);
    
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
    
    // ✅ 如果 initialRouteId 看起來像 NLB routeId（不包含 "+"），使用 getRouteByNlbId 查找
    if (widget.initialRouteId != null && !widget.initialRouteId!.contains('+')) {
      routeData = hkbusDb.getRouteByNlbId(widget.initialRouteId!);
    }
    
    // ✅ 如果找不到或不是 NLB routeId，使用原始邏輯
    if (routeData == null && widget.initialRouteId != null && widget.initialRouteId!.isNotEmpty) {
      routeData = hkbusDb.getRouteById(widget.initialRouteId!);
    }
    
    // ✅ 最後回退到 getRouteByNumber
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
        final coKey = _selectedCompany.toLowerCase();  // ✅ fixed: ensure lowercase key
        final stopId = group['$coKey${'_stop_id'}'] ??
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
          'lrtfeeder_stop_id': group['lrtfeeder_stop_id'],  // ✅ 新增 lrtfeeder stop ID
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
        // Stops from buildStopGroupsForRoute are already properly formatted
        // No need to call _normalizeStops again (which was causing issues with circular routes)
        _allStops = stops;
        data = {
          'route': widget.route,
          'stops': stops,
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
          await _fetchGmbData();
          break;
        case 'lrtfeeder':
          await _fetchMtrBusData();  
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

  Future<void> _fetchMtrBusData() async {
    // MTR Bus API returns all stops for a route in one response
    // We need to fetch the schedule and extract stop data
    
    debugPrint('🔍 _fetchMtrData: route=${widget.route}, bound=${widget.bound}');
    
    // Determine language (default to Traditional Chinese)
    final isEnglish = context.read<LanguageProvider>().isEnglish;
    final language = isEnglish ? 'en' : 'zh';
    
    try {
      // Fetch schedule from MTR Bus API
      final schedule = await MtrBus.fetchSchedule(widget.route, language);
      
      // Extract all stops from the schedule
      final allStops = MtrBus.extractStops(schedule);
      
      if (allStops.isEmpty) {
        throw Exception('No MTR Bus stops found for route ${widget.route}');
      }
      
      debugPrint('🔍 MTR Bus: found ${allStops.length} stops (all directions)');
      
      // ✅ Determine target direction: D=downbound=O, U=upbound=I
      final targetBound = widget.bound?.toUpperCase() ?? 'O';
      final targetDirection = targetBound == 'I' ? 'U' : 'D';
      
      // Convert to standard format and filter by direction
      final stops = <Map<String, dynamic>>[];
      for (final stop in allStops) {
        final stopId = stop['busStopId']?.toString() ?? '';
        final stopSeq = MtrBus.getStopSequence(stopId);
        
        // ✅ Extract direction from stop ID (D=downbound, U=upbound)
        final stopDirection = MtrBus.getDirectionFromStopId(stopId);
        final directionChar = stopId.contains('-D') ? 'D' : (stopId.contains('-U') ? 'U' : '');
        
        // ✅ Filter: Only include stops matching target direction
        if (directionChar.isNotEmpty && directionChar != targetDirection) {
          continue;  // Skip stops from wrong direction
        }
        
        stops.add({
          'seq': stopSeq,
          'stop': stopId,
          'name_tc': stop['busStopName_tc']?.toString(),
          'name_en': stop['busStopName_en']?.toString(),
          'lrtfeeder_stop_id': stopId,
          'lat': stop['latitude']?.toString(),
          'lng': stop['longitude']?.toString(),
          'long': stop['longitude']?.toString(),
          'fare': stop['fare']?.toString(),
          'bound': stopDirection,  // ✅ Add bound to stop data
        });
      }
      
      debugPrint('🔍 MTR Bus: ${stops.length} stops after direction filter (target=$targetDirection)');
      
      // Get route info from the schedule
      final routeName = schedule['routeName']?.toString() ?? widget.route;
      final routeStatus = schedule['routeStatus']?.toString() ?? '0';
      
      // Build origin/destination from first/last stop
      String? origTc, origEn, destTc, destEn;
      if (stops.isNotEmpty) {
        final firstStop = stops.first;
        final lastStop = stops.last;
        
        origTc = firstStop['name_tc']?.toString();
        origEn = firstStop['name_en']?.toString();
        destTc = lastStop['name_tc']?.toString();
        destEn = lastStop['name_en']?.toString();
      }
      
      if (mounted) {
        setState(() {
          _allStops = stops;
          data = {
            'route': widget.route,
            'stops': stops,
            'companies': ['lrtfeeder'],
            'orig_tc': origTc,
            'orig_en': origEn,
            'dest_tc': destTc,
            'dest_en': destEn,
            'routeStatus': routeStatus,
          };
          loading = false;
        });
        _preFillStopKeys();
        debugPrint('✅ MTR Bus data loaded: ${stops.length} stops');
      }
    } catch (e) {
      debugPrint('❌ Error fetching MTR Bus data: $e');
      rethrow;
    }
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

    debugPrint('▶️ Starting ETA refresh loop (interval: ${_etaRefreshInterval.inSeconds}s, stops: ${_expandedStopsById.length})');
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
    
    // ✅ Check network state before fetching
    if (_connectivity.isOffline) {
      debugPrint('📡 Network offline, skipping ETA refresh');
      return;
    }

    _etaRefreshInFlight = true;
    try {
      // ✅ Parallel ETA requests for better performance
      final futures = _expandedStopsById.keys.map((stopId) async {
        final freshStop = _allStops.firstWhere(
          (s) => s['stop']?.toString() == stopId,
          orElse: () => _expandedStopsById[stopId]!,  // fallback to cached if not found
        );
        await _fetchEtaForSingleStop(
          freshStop,
          force: true,
          showLoading: false,
        );
      });
      
      await Future.wait(futures, eagerError: false);
    } catch (e) {
      debugPrint('❌ Error refreshing ETAs: $e');
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
        etas = await _fetchJointOperationEtas(stop, force: force);
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
        } else if (co == 'mtr') {
          // ✅ For MTR Heavy Rail: stopId IS the stationCode (e.g., "TKO", "HOM")
          effectiveContext = effectiveContext.copyWith(mtrStationCode: companyStopId);
        }



        etas = await _etaService.fetchEta(
          company: _selectedCompany,
          routeNumber: widget.route,
          stopId: companyStopId,
          routeContext: effectiveContext,  // ← 用 effectiveContext 而非 _routeContext
          useCache: !force,  // ← Bypass cache when force refresh is requested
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
    Map<String, dynamic> stop, {
    bool force = false,
  }) async {
    final companyEtasMap = <String, List<UnifiedEta>>{};
    final futures = <Future<void>>[];

    for (final company in widget.companies) {
      // 每間公司必須用自己的 stop ID，不允許跨公司 fallback
      final coKey = '${company.toLowerCase()}_stop_id';
      final companyStopId = stop[coKey]?.toString();

      if (companyStopId == null || companyStopId.isEmpty) {
        debugPrint('⚠️ No $company stop ID in stop map (key=$coKey), skipping');
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
          useCache: !force,  // ← Bypass cache when force refresh is requested
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
    // Use _allStops directly - already normalized in _fetchFromUnifiedDb/_processStopEntries
    // Avoid redundant _normalizeStops call which can cause stop ID mapping issues
    final List<Map<String, dynamic>> stops = _allStops;

    // 🔍 DEBUG: Track stops data
    debugPrint('🔍 _buildListView: stops length=${stops.length}, type=${stops.runtimeType}');
    if (stops.isNotEmpty) {
      debugPrint('🔍 _buildListView: first stop type=${stops.first.runtimeType}, value=${stops.first}');
      debugPrint('🔍 _buildListView: first stop keys=${(stops.first as Map).keys.toList()}');
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
    ? (stop['name_en']?.toString().toTitleCase() ?? stop['name_tc'] ?? stopId)
    : (stop['name_tc'] ?? stop['name_en']?.toString().toTitleCase() ?? stopId);


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
    return content;
        /**.animate()
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
        **/
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

    // Sort by ETA time (not sequence - unreliable for MTR Bus where all sequences are equal)
    // This ensures correct chronological order for all companies
    valid.sort((a, b) => a.eta.compareTo(b.eta));

    // Deduplicate by ETA time (within 60 seconds tolerance)
    // Prevents duplicate buses from showing (API may return duplicates)
    final deduplicated = <UnifiedEta>[];
    for (final eta in valid) {
      final isDuplicate = deduplicated.any((existing) {
        final timeDiff = (eta.eta.difference(existing.eta)).abs();
        return timeDiff.inSeconds < 60;
      });
      if (!isDuplicate) {
        deduplicated.add(eta);
      }
    }

    return deduplicated.take(3).map((eta) {
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
    final lang = context.read<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final companyProv = context.read<CompanyProvider>();

    // Get route origin and destination
    final origTc = data?['orig_tc'] ?? '';
    final origEn = data?['orig_en'] ?? '';
    final destTc = data?['dest_tc'] ?? '';
    final destEn = data?['dest_en'] ?? '';

    return DraggableRouteSheet(
      controller: _draggableController,
      routeNumber: widget.route,
      selectedCompany: _selectedCompany,
      originTc: origTc,
      originEn: origEn,
      destTc: destTc,
      destEn: destEn,
      isEnglish: isEnglish,
      companies: widget.companies,
      routeVariants: _routeVariants,
      getCompanyName: (co) => companyProv.getName(co, isEnglish),
      onCompanyChanged: (company) => _onCompanyChanged(company!),
    );
  }
}
