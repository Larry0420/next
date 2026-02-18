import 'dart:ui';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:lrt_next_train/backup/main.dart' hide LanguageProvider, AccessibilityProvider, DeveloperSettingsProvider;
import 'package:lrt_next_train/ctb_route_status_page.dart';
import 'package:lrt_next_train/optionalMarquee.dart';
import 'dart:async';
import 'api/kmb.dart';
import 'api/citybus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../kmb_route_status_page.dart';
// Keep only:
import '../main.dart' show AccessibilityProvider, LanguageProvider, DeveloperSettingsProvider;
import '../toTitleCase.dart';
import 'company_name.dart';

class KmbNearbyPage extends StatefulWidget {
  const KmbNearbyPage({super.key});

  @override
  State<KmbNearbyPage> createState() => _KmbNearbyPageState();
}

class _KmbNearbyPageState extends State<KmbNearbyPage> {
  bool _loading = true;
  String? _error;
  Position? _position;
  List<_StopDistance> _nearby = [];
  // Cache for stop ETAs to avoid repeated fetches
  final Map<String, List<Map<String, dynamic>>> _stopEtaCache = {};
  Timer? _refreshTimer;
  
  // Range selection
  double _rangeMeters = 150.0; // Default 200m
  final TextEditingController _customRangeController = TextEditingController();
  
  // Spatial index cache for O(1) nearby lookup
  static Map<String, Map<String, dynamic>>? _globalStopMap;
  static List<_StopDistance>? _allStopsWithCoords;
  static Map<String, List<_StopDistance>>? _spatialGrid; // Grid-based spatial index
  
  // Grid configuration: ~1km cells for Hong Kong (lat/lng ~0.009 degrees ≈ 1km)
  static const double _gridSize = 0.01; // Approximately 1km grid cells
  
  static String _getGridKey(double lat, double lng) {
    final gridLat = (lat / _gridSize).floor();
    final gridLng = (lng / _gridSize).floor();
    return '$gridLat,$gridLng';
  }
  
  static List<String> _getNearbyCells(double lat, double lng, double rangeMeters) {
    // Calculate how many grid cells we need to check based on range
    final cellsToCheck = (rangeMeters / 1000.0 / _gridSize).ceil() + 1;
    final gridLat = (lat / _gridSize).floor();
    final gridLng = (lng / _gridSize).floor();
    
    final List<String> cells = [];
    for (int dLat = -cellsToCheck; dLat <= cellsToCheck; dLat++) {
      for (int dLng = -cellsToCheck; dLng <= cellsToCheck; dLng++) {
        cells.add('${gridLat + dLat},${gridLng + dLng}');
      }
    }
    return cells;
  }

  final DraggableScrollableController _sheetController = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _rangeDebounce?.cancel();
    _refreshTimer?.cancel();
    _customRangeController.dispose();
    super.dispose();
  }

  // ✅ 正確：定義在類的頂層（與其他方法平級）
  String _fmtDistance(double meters, {LanguageProvider? langProv}) {
    final bool isEnglish = langProv?.isEnglish ?? true;
    
    if (meters < 1000) {
      final val = meters.toStringAsFixed(0);
      return isEnglish ? '$val m' : '$val 米';
    } else {
      final val = (meters / 1000).toStringAsFixed(2);
      return isEnglish ? '$val km' : '$val 公里';
    }
  }

  Future<bool> _showLocationRationaleDialog() async {
    if (!mounted) return false;
    
    final langProv = context.read<LanguageProvider>();
    final isEnglish = langProv.isEnglish;
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isEnglish ? 'Location Permission' : '位置權限'),
        content: Text(
          isEnglish
              ? 'This app needs location access to show nearby stops and help you navigate.'
              : '此應用程式需要位置權限以顯示附近站點並協助您導航。'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isEnglish ? 'Cancel' : '取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isEnglish ? 'Allow' : '允許'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showOpenSettingsDialog() async {
    if (!mounted) return false;
    
    final langProv = context.read<LanguageProvider>();
    final isEnglish = langProv.isEnglish;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          isEnglish ? 'Location Permission Required' : '需要位置權限',
          style: TextStyle(
            color: isDarkMode ? Theme.of(context).colorScheme.primaryContainer : Colors.black,
          ),
        ),
        content: Text(
          isEnglish
              ? 'Location permission is permanently denied. Please enable it in app settings.'
              : '位置權限已永久拒絕。請在應用程式設定中啟用。'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isEnglish ? 'Cancel' : '取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isEnglish ? 'Open Settings' : '開啟設定'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool?> _ensureLocationPermission(LanguageProvider? langProv) async {
    final bool isEn = langProv?.isEnglish ?? true;

    var preciseStatus = await Permission.location.status;
    var approxStatus = await Permission.locationWhenInUse.status;

    if (preciseStatus.isDenied && approxStatus.isDenied) {
      final shouldRequest = await _showLocationRationaleDialog();
      if (!shouldRequest) {
        _setError(isEn ? 'Location permission denied' : '位置權限被拒絕');
        return null;
      }
      preciseStatus = await Permission.location.request();
      approxStatus = await Permission.locationWhenInUse.status;
    }

    if (preciseStatus.isPermanentlyDenied && approxStatus.isPermanentlyDenied) {
      if (await _showOpenSettingsDialog()) await openAppSettings();
      _setError(isEn ? 'Location permission required' : '需要位置權限');
      return null;
    }

    if (!preciseStatus.isGranted && !approxStatus.isGranted) {
      _setError(isEn ? 'Location permission denied' : '位置權限被拒絕');
      return null;
    }

    final useApprox = !preciseStatus.isGranted && approxStatus.isGranted;
    if (useApprox && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isEn
            ? 'Using approximate location — nearby results may be less accurate'
            : '使用大概位置，附近結果可能不夠精確'),
        duration: const Duration(seconds: 4),
      ));
    }

    return useApprox; // null = denied, false = precise, true = approximate
  }

  void _setError(String msg) {
    if (mounted) setState(() { _error = msg; _loading = false; });
  }

  Future<void> _init() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; _nearby = []; });

    final langProv = mounted ? context.read<LanguageProvider>() : null;

    final useApprox = await _ensureLocationPermission(langProv);
    if (useApprox == null) return;

    final accuracy = useApprox ? LocationAccuracy.low : LocationAccuracy.best;

    try {
      if (_globalStopMap == null) {
        await Future.wait([
          Geolocator.getCurrentPosition(desiredAccuracy: accuracy)
              .then((pos) => _position = pos),
          _buildUnifiedStopMap(langProv),
        ]);
      } else {
        _position = await Geolocator.getCurrentPosition(desiredAccuracy: accuracy);
      }

      if (!mounted || _position == null) return;

      _updateNearbyList(_position!);
      _fetchEtasForNearbyStops();

      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _fetchEtasForNearbyStops(),
      );
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _buildUnifiedStopMap(LanguageProvider? langProv) async {
    final stopResults = await Future.wait([Kmb.buildStopMap(), Citybus.buildStopMap()]);
    final kmbStops = stopResults[0];
    final ctbStopsRaw = stopResults[1];

    if (kmbStops.isEmpty && ctbStopsRaw.isEmpty) {
      throw Exception(langProv?.isEnglish ?? true
          ? 'No stops data available. Please check your internet connection.'
          : '沒有站點資料。請檢查您的網路連線。');
    }

    final Map<String, Map<String, dynamic>> unifiedMap = {};
    kmbStops.forEach((id, data) => unifiedMap['kmb-$id'] = {...Map<String, dynamic>.from(data), 'co': 'KMB'});
    ctbStopsRaw.forEach((id, data) => unifiedMap['ctb-$id'] = {...Map<String, dynamic>.from(data as Map), 'co': 'CTB'});

    _globalStopMap = unifiedMap;

    final List<_StopDistance> allStops = [];
    final Map<String, List<_StopDistance>> grid = {};

    unifiedMap.forEach((stopId, meta) {
      try {
        final lat = double.tryParse((meta['lat'] ?? meta['latitude']).toString());
        final lng = double.tryParse((meta['long'] ?? meta['lng'] ?? meta['longitude']).toString());
        if (lat == null || lng == null) return;
        final stop = _StopDistance(stopId: stopId, lat: lat, lng: lng, distanceMeters: 0, meta: meta);
        allStops.add(stop);
        grid.putIfAbsent(_getGridKey(lat, lng), () => []).add(stop);
      } catch (_) {}
    });

    _allStopsWithCoords = allStops;
    _spatialGrid = grid;
  }

  void _updateNearbyList(Position pos) {
    final nearbyCells = _getNearbyCells(pos.latitude, pos.longitude, _rangeMeters);
    final nearbyList = <_StopDistance>[];

    for (final cellKey in nearbyCells) {
      final cellStops = _spatialGrid?[cellKey];
      if (cellStops == null) continue;
      for (final stop in cellStops) {
        final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, stop.lat, stop.lng);
        if (dist <= _rangeMeters) {
          nearbyList.add(_StopDistance(stopId: stop.stopId, lat: stop.lat, lng: stop.lng, distanceMeters: dist, meta: stop.meta));
        }
      }
    }

    nearbyList.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    if (mounted) setState(() { _nearby = nearbyList.take(50).toList(); _loading = false; });
  }

  Future<void> _fetchEtasForNearbyStops() async {
    final futures = _nearby.map((stop) async {
      try {
        final co = stop.meta['co'];
        final rawId = stop.stopId.split('-').last; // Remove 'kmb-' or 'ctb-' prefix

        List<Map<String, dynamic>> etas = [];
        
        if (co == 'CTB') {
          // 1. Fetch the list of all routes for this stop from the JSON mapping
          final routes = await Citybus.getRoutesForStop(rawId);
          
          if (routes.isNotEmpty) {
            // 2. Fetch ETAs for every route in parallel to save time
            final etaResults = await Future.wait(
              routes.map((r) => Citybus.fetchEta(rawId, r,))
            );
            
            // 3. Flatten the list of lists into a single unified ETA list
            etas = etaResults
                .expand((list) => list)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        } else {
          // KMB supports fetching all routes for a stop in a single call
          etas = await Kmb.fetchStopEta(rawId);
        }
        
        return MapEntry(stop.stopId, etas);
      } catch (e) {
        debugPrint('Error fetching ETAs for ${stop.stopId}: $e');
        return MapEntry(stop.stopId, <Map<String, dynamic>>[]);
      }
    }).toList();

    final results = await Future.wait(futures);
    
    if (mounted) {
      setState(() {
        for (final entry in results) {
          _stopEtaCache[entry.key] = entry.value;
        }
      });
    }
  }

  Widget _buildRangeChip(String label, double meters, LanguageProvider langProv, AccessibilityProvider accProv) {
    final isSelected = _rangeMeters == meters;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11 * accProv.textScale,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (selected) {
        if (selected) _onRangeChanged(meters);
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.primary,
      showCheckmark: false, // saves horizontal space
    );
  }


  Widget _buildCustomRangeChip(LanguageProvider langProv, AccessibilityProvider accProv) {
    final double textScale = accProv.textScale;
    final isCustom = ![100.0, 150.0, 200.0, 400.0].contains(_rangeMeters);
    return FilterChip(
      label: Text(
        isCustom 
          ? '${_rangeMeters.toInt()}'
          : (langProv.isEnglish ? 'Custom' : '自訂')
      ),
      labelStyle: TextStyle(
        fontSize: 12 * textScale,
      ),
      selected: isCustom,
      onSelected: (selected) {
        if (selected) {
          _showCustomRangeDialog(langProv);
        }
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }

  Timer? _rangeDebounce;

  void _onRangeChanged(double meters) {
    if (_rangeMeters == meters) return; // no-op if same
    setState(() => _rangeMeters = meters);
    _rangeDebounce?.cancel();
    _rangeDebounce = Timer(const Duration(milliseconds: 300), _init);
  }

  void _showCustomRangeDialog(LanguageProvider langProv) {
    _customRangeController.text = _rangeMeters.toInt().toString();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          langProv.isEnglish ? 'Custom Range' : '自訂範圍',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        content: TextField(
          controller: _customRangeController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: langProv.isEnglish ? 'Range (meters)' : '範圍（米）',
            hintText: '100',
            suffixText: langProv.isEnglish ? 'm' : '米',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(langProv.isEnglish ? 'Cancel' : '取消'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(_customRangeController.text);
              if (value != null && value > 0) {
                setState(() {
                  _rangeMeters = value;
                });
                Navigator.pop(context);
                _init(); // Re-fetch with custom range
              }
            },
            child: Text(langProv.isEnglish ? 'OK' : '確定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProv = context.watch<LanguageProvider>();
    
    // ADD THESE TWO LINES to resolve "Undefined name" errors
    final position = this._position; 
    final nearby = this._nearby; 

    return Scaffold(
      body: _loading
          ? const Align(
              alignment: Alignment.bottomCenter, 
              child: Padding(
                padding: EdgeInsets.only(bottom: 10.0), // Adds 16 pixels of space at the top
                child: LinearProgressIndicator(),
              ),
            )
          : (_error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        langProv.isEnglish ? "Error" : "錯誤",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red[700]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Range selector
                    Container(
                      width: double.infinity,
                      // 1. Reduce Padding for the container
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Reduced from 16/8
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // 2. Smaller Icon
                          Icon(
                            Icons.straighten_rounded, 
                            size: 16, 
                            color: Theme.of(context).colorScheme.primary
                            ), // Reduced from 18
                          const SizedBox(width: 6), // Reduced from 8
                          
                          // 3. Smaller Label Text
                          Text(
                            langProv.isEnglish ? 'Range(m)' : '範圍(米)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 11, // Explicitly set smaller font size
                            ),
                          ),
                          const SizedBox(width: 8), // Reduced from 12
                          
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  // 4. Chips (Your existing methods already use small font size '8')
                                  // Ensure the chips themselves are compact:
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      // Force material chips to be denser/smaller
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, 
                                      visualDensity: VisualDensity.compact, 
                                    ),
                                    child: Row(
                                      children: [
                                        _buildRangeChip('100', 100, langProv, context.read<AccessibilityProvider>()),
                                        const SizedBox(width: 4), // Reduced spacing between chips
                                        _buildRangeChip('150', 150, langProv, context.read<AccessibilityProvider>()),
                                        const SizedBox(width: 4),
                                        _buildRangeChip('200', 200, langProv, context.read<AccessibilityProvider>()),
                                        const SizedBox(width: 4),
                                        _buildRangeChip('400', 400, langProv, context.read<AccessibilityProvider>()),
                                        const SizedBox(width: 4),
                                        _buildCustomRangeChip(langProv, context.read<AccessibilityProvider>()),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Location header
                    // Location header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            size: 16, 
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8), 
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nearby.isNotEmpty 
                                          ? (() {
                                              final s = nearby.first; // Use 1st nearby stop
                                              final nameEn = s.meta['name_en'] ?? s.meta['nameen'] ?? '';
                                              final nameTc = s.meta['name_tc'] ?? s.meta['nametc'] ?? '';
                                              
                                              // Your specific display logic from _buildStopCard
                                              final String displayName = langProv.isEnglish
                                                  ? ((nameEn.toString().isNotEmpty) ? nameEn.toString() : (nameTc.toString().isNotEmpty ? nameTc.toString() : s.stopId))
                                                  : ((nameTc.toString().isNotEmpty) ? nameTc.toString() : (nameEn.toString().isNotEmpty ? nameEn.toString().toTitleCase() : s.stopId));
                                              
                                              return displayName.toTitleCase();
                                            })()
                                          : (langProv.isEnglish ? 'Current Location' : '目前位置'),
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${position?.latitude.toStringAsFixed(6) ?? '-'}, ${position?.longitude.toStringAsFixed(6) ?? '-'}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                        fontSize: 10,
                                        fontFeatures: [const FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),


                    // Stops list
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.only(
                          top: 6,
                          bottom: MediaQuery.of(context).viewInsets.bottom +
                              MediaQuery.of(context).padding.bottom +
                              kBottomNavigationBarHeight +
                              80,
                        ),

                        itemCount: _nearby.length,
                        itemBuilder: (context, idx) => _buildStopCard(context, idx, langProv),
                      ),
                    ),
                  ],
                )),
    );
  }

  Widget _buildStopCard(BuildContext context, int idx, LanguageProvider langProv) {
    final s = _nearby[idx];
    
    final devSettings = context.watch<DeveloperSettingsProvider>();
    final showRank = devSettings.showRankBadge; // 假設欄位名稱為 showRankBadge
    // 獲取主題狀態 (假設你用 Provider)
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. Get Company Information
    final companyProv = context.watch<CompanyProvider>();
    final String? companyId = s.meta['co'] ?? s.meta['company']; // Extract company code
    final badgeBgColor = companyProv.getBadgeBgColor(companyId, context);
    final badgeBorderColor = companyProv.getBadgeBorderColor(companyId, context);
    final badgeTextColor = companyProv.getBadgeTextColor(companyId, context);
    final companyName = companyProv.getName(companyId, langProv.isEnglish);
      // Extract stop names from metadata
    final nameEn = s.meta['name_en'] ?? s.meta['nameen'] ?? '';
    final nameTc = s.meta['name_tc'] ?? s.meta['nametc'] ?? '';
    final displayName = langProv.isEnglish
        ? ((nameEn.toString().isNotEmpty) ? nameEn.toString() : (nameTc.toString().isNotEmpty ? nameTc.toString() : s.stopId))
        : ((nameTc.toString().isNotEmpty) ? nameTc.toString() : (nameEn.toString().isNotEmpty ? nameEn.toString().toTitleCase() : s.stopId));
    
    // Get ETAs for this stop
    final etas = _stopEtaCache[s.stopId] ?? [];
    
    // Group ETAs by route
    final Map<String, List<Map<String, dynamic>>> etasByRoute = {};
    for (final eta in etas) {
      final route = eta['route']?.toString() ?? '';
      if (route.isEmpty) continue;
      etasByRoute.putIfAbsent(route, () => []).add(eta);
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      // 使用三段色風格優化 Card 邊框
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: badgeBorderColor.withValues(alpha: 0.3), // 統一使用公司邊框色
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showStopDetails(context, s, etas),
        // 2. 處理視覺反饋的圓角（確保水波紋不會超出邊框）
        borderRadius: BorderRadius.circular(12), 
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            children: [
              Row(
                children: [
                  // 2. 序號 Badge 套用三段色
                  // 條件判斷：只有當開發者設定開啟時才顯示序號
                  if (showRank) ...[
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: badgeBgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: badgeBorderColor, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeTextColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10), // 只有顯示 Badge 時才需要的間距
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 3. 公司標籤套用三段色 (同 Dialer 一致)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeBgColor,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: badgeBorderColor, width: 0.5),
                              ),
                              child: Text(
                                companyName,
                                style: TextStyle(
                                  fontSize: 9, 
                                  color: badgeTextColor, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OptionalMarquee(
                                text: displayName.toTitleCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: badgeTextColor, // 站名顏色跟隨公司主色
                                  height: 1.2, // 配合你的 OptionalMarquee 高度檢測
                                ),
                                velocity: 50.0, // 列表中建議速度中等
                                blankSpace: 30.0,
                                pauseAfterRound: const Duration(seconds: 2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.near_me_rounded, size: 11, color: badgeTextColor),
                            const SizedBox(width: 3),
                            Text(
                              _fmtDistance(s.distanceMeters, langProv: langProv),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 30, color: Colors.grey[400]),
                ],
              ),
              
              // 1. 統一間距處理 (放在 Column 內)
              const SizedBox(height: 12),

              // 2. 使用 AnimatedSwitcher 處理狀態切換動畫
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.bounceIn,
                switchOutCurve: Curves.bounceOut,
                child: _buildFooterSection(s, etasByRoute, langProv, isDark, badgeTextColor),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterSection(
    _StopDistance s, 
    Map<String, List<Map<String, dynamic>>> etasByRoute, 
    LanguageProvider langProv, 
    bool isDark,
    Color coColor,
  ) {
    // 情況 A: 有路線資料
    if (etasByRoute.isNotEmpty) {
      return SizedBox(
        key: const ValueKey('routes'),
        width: double.infinity,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: etasByRoute.entries.take(8).map((entry) {
            return _buildRouteChip(context, entry.key, entry.value, langProv);
          }).toList(),
        ),
      );
    }

    // 情況 B: 已加載但無班次 (Empty State)
    if (_stopEtaCache.containsKey(s.stopId)) {
      return Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 12, color: isDark ? Colors.grey[500] : Colors.grey[400]),
            const SizedBox(width: 6),
            Text(
              langProv.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    // 情況 C: 加載中 (Loading State)
    return Padding(
      key: const ValueKey('loading'),
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 3,
          width: 120, // 稍微縮短寬度，視覺上更精緻
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              // 使用品牌主色 (coColor) 作為進度條顏色，強化公司辨識度
              backgroundColor: coColor.withValues(alpha: 0.1),
              color: coColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteChip(BuildContext context, String route, List<Map<String, dynamic>> routeEtas, LanguageProvider langProv) {
    // Sort by eta time
    routeEtas.sort((a, b) {
      final etaA = a['eta']?.toString() ?? '';
      final etaB = b['eta']?.toString() ?? '';
      return etaA.compareTo(etaB);
    });
    
    final dir = routeEtas.first['dir']?.toString() ?? '';
    
    // Get first ETA
    final firstEta = routeEtas.isNotEmpty ? routeEtas.first : null;
    String etaText = '—';
    Color etaColor = Colors.grey;
    
    if (firstEta != null) {
      final etaStr = firstEta['eta']?.toString() ?? '';
      if (etaStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(etaStr).toLocal();
          final now = DateTime.now();
          final diff = dt.difference(now);
          
          if (diff.inMinutes <= 0) {
            etaText = langProv.isEnglish ? 'Due' : '即到';
            etaColor = Colors.green;
          } else if (diff.inMinutes <= 2) {
            etaText = '${diff.inMinutes}′';
            etaColor = Colors.red;
          } else if (diff.inMinutes <= 5) {
            etaText = '${diff.inMinutes}′';
            etaColor = Colors.orange;
          } else if (diff.inMinutes < 60) {
            etaText = '${diff.inMinutes}′';
            etaColor = Colors.blue;
          } else {
            etaText = DateFormat.Hm().format(dt);
            etaColor = Colors.grey[700]!;
          }
        } catch (_) {}
      }
    }
    
    // Direction icon and color
    IconData dirIcon = Icons.arrow_forward;
    Color dirColor = Colors.blue;
    if (dir.toUpperCase().startsWith('O')) {
      dirIcon = Icons.arrow_circle_right_outlined;
      dirColor = Colors.green;
    } else if (dir.toUpperCase().startsWith('I')) {
      dirIcon = Icons.arrow_circle_left_outlined;
      dirColor = Colors.orange;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: dirColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: dirColor.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Route number
          Text(
            route,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: dirColor,
            ),
          ),
          const SizedBox(width: 3),
          Icon(dirIcon, size: 11, color: dirColor),
          const SizedBox(width: 5),
          // ETA
          Text(
            etaText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: etaColor,
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for sort chips
  Widget _buildSortChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primaryContainer;
    final inactiveColor = colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final activeContentColor = colorScheme.onPrimaryContainer;
    final inactiveContentColor = colorScheme.onSurfaceVariant;

    return Material(
      color: isSelected ? activeColor : inactiveColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias, // Ensures ink splash respects rounded corners
      child: InkWell(
        onTap: onTap,
        // No need for borderRadius here since parent clips
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Increased vertical padding for better touch target
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center, // Ensure vertical center alignment
            children: [
              Icon(
                icon,
                size: 18, // Slightly larger icon for better visibility
                color: isSelected ? activeContentColor : inactiveContentColor,
              ),
              const SizedBox(width: 6), // More breathing room between icon and text
              Flexible( // Prevents overflow if text is long
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13, // Standard readable size
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? activeContentColor : inactiveContentColor,
                    height: 1.2, // Fixes line height to vertically center text with icon
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Update _showStopDetails to include company info in title
  void _showStopDetails(BuildContext context, _StopDistance stop, List<Map<String, dynamic>> etas) {
    final langProv = context.read<LanguageProvider>();
    final companyProv = context.read<CompanyProvider>();
    final String? co = stop.meta['co'];
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    final companyName = companyProv.getName(co, langProv.isEnglish);
    
    // Extract stop names
    final nameEn = stop.meta['name_en'] ?? stop.meta['nameen'] ?? '';
    final nameTc = stop.meta['name_tc'] ?? stop.meta['nametc'] ?? '';
    final displayName = langProv.isEnglish
        ? ((nameEn?.toString().isNotEmpty ?? false) ? nameEn.toString() : (nameTc?.toString().isNotEmpty ?? false ? nameTc.toString() : stop.stopId))
        : ((nameTc?.toString().isNotEmpty ?? false) ? nameTc.toString() : (nameEn?.toString().isNotEmpty ?? false ? nameEn.toString() : stop.stopId));
    
    // Group ETAs by route
    // Use a composite key to distinguish directions and variants
    final Map<String, List<Map<String, dynamic>>> etasByRoute = {};
    for (final eta in etas) {
      final route = eta['route']?.toString() ?? '';
      final dir = eta['dir']?.toString() ?? '';
      final serviceType = eta['service_type']?.toString() ?? '1';
      
      if (route.isEmpty) continue;
      
      // Composite key ensures "968-O-1" and "968-I-1" are separate entries
      final compositeKey = '$route-$dir-$serviceType';
      etasByRoute.putIfAbsent(compositeKey, () => []).add(eta);
    }

    final distance = stop.distanceMeters;
    
    // 在 showModalBottomSheet 調用處直接使用
    final sortOptionNotifier = ValueNotifier<int>(0); // 在這裡創建

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white.withValues(alpha: 0.0),
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (context) {
        final sheetController = DraggableScrollableController(); // local
        return ValueListenableBuilder<int>(
          valueListenable: sortOptionNotifier,
          builder: (context, sortOption, _) {
            List<MapEntry<String, List<Map<String, dynamic>>>> getSortedEntries() {
              final entries = etasByRoute.entries.toList();
              int? extractNumber(String route) {
                final match = RegExp(r'\d+').firstMatch(route);
                return match != null ? int.tryParse(match.group(0)!) : null;
              }

              entries.sort((a, b) {
                final routeA = a.key;
                final routeB = b.key;
                final etasA = a.value;
                final etasB = b.value;

                if (sortOption == 1) {
                  final numA = extractNumber(routeA);
                  final numB = extractNumber(routeB);
                  if (numA != null && numB != null) {
                    final numCompare = numA.compareTo(numB);
                    if (numCompare != 0) return numCompare;
                  }
                  return routeA.compareTo(routeB);
                }

                final hasEtaA = etasA.any((eta) => (eta['eta']?.toString() ?? '').isNotEmpty);
                final hasEtaB = etasB.any((eta) => (eta['eta']?.toString() ?? '').isNotEmpty);
                if (hasEtaA != hasEtaB) return hasEtaB ? 1 : -1;

                if (hasEtaA && hasEtaB) {
                  try {
                    final earliestA = etasA
                        .where((eta) => (eta['eta']?.toString() ?? '').isNotEmpty)
                        .map((eta) => DateTime.parse(eta['eta'].toString()))
                        .reduce((a, b) => a.isBefore(b) ? a : b);
                    final earliestB = etasB
                        .where((eta) => (eta['eta']?.toString() ?? '').isNotEmpty)
                        .map((eta) => DateTime.parse(eta['eta'].toString()))
                        .reduce((a, b) => a.isBefore(b) ? a : b);
                    final comparison = earliestA.compareTo(earliestB);
                    if (comparison != 0) return comparison;
                  } catch (_) {}
                }

                final numA = extractNumber(routeA);
                final numB = extractNumber(routeB);
                if (numA != null && numB != null) return numA.compareTo(numB);
                return routeA.compareTo(routeB);
              });

              return entries;
            }

            final sortedEntries = getSortedEntries();

            return DraggableScrollableSheet(
              controller: sheetController,
              initialChildSize: 0.4,
              minChildSize: 0.4,
              maxChildSize: 0.75,
              expand: false,
              builder: (context, scrollController) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: _buildSheetBody(
                        context,
                        langProv,
                        sortOptionNotifier,
                        displayName,
                        sortOption,
                        distance,
                        sortedEntries,
                        scrollController,
                        stop,
                        co,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    /*showDialog(
      fullscreenDialog: false,
      useSafeArea: true,
      context: context,
      builder: (_) => AlertDialog(
        title: Text( langProv.isEnglish ? 'KMB - ${displayName.toTitleCase()}' : '九巴 - ${displayName.toTitleCase()}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              //Removed to StopID for better visibility 
              /*Text(langProv.isEnglish ? 'Stop ID: ${stop.stopId}' : '站點編號: ${stop.stopId}', style: TextStyle(fontSize: 12)),
              */
              
              // 修改後
              Text(
                '${langProv.isEnglish ? "Distance" : "距離"}: ${_fmtDistance(distance, langProv: langProv)}',
                style: TextStyle(fontSize: 12),
              ),

              //Text('Lat: ${stop.lat.toStringAsFixed(6)}, Lng: ${stop.lng.toStringAsFixed(6)}', style: TextStyle(fontSize: 11, color: Colors.grey)),
              SizedBox(height: 12),
              if (etasByRoute.isEmpty)
                Text(langProv.isEnglish ? 'No upcoming ETAs' : '沒有即將到站的班次', style: TextStyle(color: Colors.grey))
              else
                ...etasByRoute.entries.map((entry) {
                  final route = entry.key;
                  final routeEtas = entry.value;
                  
                  // Sort by eta time
                  routeEtas.sort((a, b) {
                    final etaA = a['eta']?.toString() ?? '';
                    final etaB = b['eta']?.toString() ?? '';
                    return etaA.compareTo(etaB);
                  });
                  
                  final destEn = routeEtas.first['dest_en'] ?? routeEtas.first['desten'] ?? '';
                  final destTc = routeEtas.first['dest_tc'] ?? routeEtas.first['desttc'] ?? '';
                  final displayDest = langProv.isEnglish ? destEn : (destTc.isNotEmpty ? destTc : destEn);
                  final bound = routeEtas.first['dir'] ?? routeEtas.first['bound'] ?? '';
                  final serviceType = routeEtas.first['service_type'] ?? routeEtas.first['servicetype'] ?? '';
                  
                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      title: Text(langProv.isEnglish ? 'Route $route To $displayDest' : '路線 $route 往 $displayDest', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: routeEtas.take(3).map((eta) {
                          final etaStr = eta['eta']?.toString() ?? '';
                          final rmkEn = eta['rmk_en'] ?? eta['rmken'] ?? '';
                          final rmkTc = eta['rmk_tc'] ?? eta['rmktc'] ?? '';
                          final rmk = langProv.isEnglish ? rmkEn : (rmkTc.isNotEmpty ? rmkTc : rmkEn);
                          
                          String timeDisplay = '—';
                          if (etaStr.isNotEmpty) {
                            try {
                              final dt = DateTime.parse(etaStr).toLocal();
                              final now = DateTime.now();
                              final diff = dt.difference(now);
                              if (diff.inMinutes <= 0) {
                                timeDisplay = langProv.isEnglish ? 'Due' : '即將到站';
                              } else if (diff.inMinutes < 60) {
                                timeDisplay = langProv.isEnglish ? '${diff.inMinutes} min' : '${diff.inMinutes}分鐘';
                              } else {
                                timeDisplay = DateFormat.Hm().format(dt);
                              }
                            } catch (_) {}
                          }
                          
                          return Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              rmk.toString().isNotEmpty ? '$timeDisplay · $rmk' : timeDisplay,
                              style: TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        // Get seq from first ETA entry for auto-expand
                        final seq = routeEtas.first['seq']?.toString();
                        final stopIdFromEta = routeEtas.first['stop']?.toString();
                        // Navigate to route status page with auto-expand
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => KmbRouteStatusPage(
                            route: route,
                            bound: bound.toString().isNotEmpty ? bound.toString().toUpperCase() : null,
                            serviceType: serviceType.toString().isNotEmpty ? serviceType.toString() : null,
                            autoExpandSeq: seq,
                            autoExpandStopId: stopIdFromEta,
                          ),
                        ));
                      },
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(langProv.isEnglish ? 'Close' : '關閉'),
          ),
        ],
      ),
    );*/
  }
  
  // Rename to _buildSheetBody to avoid conflict with the existing _buildContent list method
  Widget _buildSheetBody(
    BuildContext context,
    LanguageProvider langProv,
    ValueNotifier<int> sortOptionNotifier,
    String displayName,
    int sortOption,
    double distance,
    List<MapEntry<String, List<Map<String, dynamic>>>> sortedEntries,
    ScrollController scrollController,
    _StopDistance stop,
    String? co,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(context),
        _buildHeader(context, langProv, sortOptionNotifier, displayName, co),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Distance badge on the left
              _buildDistanceInfo(context, langProv, distance),
              // Sort options on the right (ensure _buildSortOptions is wrapped in Flexible/Expanded if needed)
              Flexible(
                child: _buildSortOptions(context, langProv, sortOption, sortOptionNotifier),
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        _buildContent(context, langProv, sortedEntries, scrollController, stop),
      ],
    );

  }


  // Add these methods to your class:
  Widget _buildDragHandle(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }


  // Update method signature
  Widget _buildHeader(
    BuildContext context,
    LanguageProvider langProv,
    ValueNotifier<int> sortOptionNotifier,
    String displayName,
    String? co, 
  ) {
    // 1. 獲取 CompanyProvider 資源
    final companyProv = Provider.of<CompanyProvider>(context, listen: false);
    
    // 2. 獲取三段色與名稱
    final companyName = companyProv.getName(co, langProv.isEnglish);
    final badgeBgColor = companyProv.getBadgeBgColor(co, context);
    final badgeBorderColor = companyProv.getBadgeBorderColor(co, context);
    final badgeTextColor = companyProv.getBadgeTextColor(co, context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                // 3. 套用三段色風格的公司標籤
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBgColor, // 淡色背景
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: badgeBorderColor, // 中深色邊框
                      width: 1,
                    ),
                  ),
                  child: Text(
                    companyName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: badgeTextColor, // 最深色文字
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                
                // 車站名稱
                Expanded(
                  child: OptionalMarquee(
                    text: displayName.toTitleCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                      // 建議高度設為 1.2 至 1.4，配合 OptionalMarquee 內部邏輯
                      height: 1.2, 
                    ),
                    // 參數調整：
                    velocity: 100.0, // Header 建議速度慢啲 (40 比較舒服)
                    blankSpace: 50.0, // 滾動完之後留多啲位先再出
                    pauseAfterRound: const Duration(seconds: 3), // 睇完一輪停 3 秒
                  ),
                ),

              ],
            ),
          ),

          // 關閉按鈕
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              sortOptionNotifier.dispose();
              Navigator.of(context).pop();
            },
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortOptions(BuildContext context, LanguageProvider langProv, int sortOption, ValueNotifier<int> sortOptionNotifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.sort,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSortChip(
                    context: context,
                    label: langProv.isEnglish ? 'Time' : '時間',
                    icon: Icons.access_time_rounded,
                    isSelected: sortOption == 0,
                    onTap: () => sortOptionNotifier.value = 0,
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(
                    context: context,
                    label: langProv.isEnglish ? 'Route No.' : '路線編號',
                    icon: Icons.numbers_rounded,
                    isSelected: sortOption == 1,
                    onTap: () => sortOptionNotifier.value = 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceInfo(BuildContext context, LanguageProvider langProv, double distance) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '${langProv.isEnglish ? "Distance" : "距離"} ${_fmtDistance(distance, langProv: langProv)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    LanguageProvider langProv,
    List<MapEntry<String, List<Map<String, dynamic>>>> sortedEntries,
    ScrollController scrollController,
    _StopDistance stop,
  ) {
    return Expanded(
      child: sortedEntries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time_filled_rounded, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    langProv.isEnglish ? 'No upcoming ETAs' : '沒有即將到站的班次',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) => _buildRouteEtaCard(context, sortedEntries[index], langProv, stop),
            ),
    );
  }

  // 2. Ensure _buildRouteEtaCard is defined inside _KmbNearbyPageState class
  Widget _buildRouteEtaCard(
    BuildContext context,
    MapEntry<String, List<Map<String, dynamic>>> entry,
    LanguageProvider langProv,
    _StopDistance stop,
  ) {
    final routeKey = entry.key;
    final routeEtas = entry.value;
    final route = routeEtas.first['route']?.toString() ?? '';

    routeEtas.sort((a, b) {
      final etaA = a['eta']?.toString() ?? '';
      final etaB = b['eta']?.toString() ?? '';
      return etaA.compareTo(etaB);
    });

    final destEn = routeEtas.first['dest_en'] ?? '';
    final destTc = routeEtas.first['dest_tc'] ?? '';
    final displayDest = langProv.isEnglish 
      ? destEn.toString().toTitleCase() 
      : (destTc.isNotEmpty ? destTc : destEn).toString();

    final bound = routeEtas.first['dir'] ?? routeEtas.first['bound'] ?? '';
    final serviceType = routeEtas.first['service_type'] ?? routeEtas.first['servicetype'] ?? '';
    final hasValidEta = routeEtas.any((eta) => (eta['eta']?.toString() ?? '').isNotEmpty);

    // DETECT COMPANY: Check 'co' or 'company' field
    final companyId = routeEtas.first['co']?.toString() ?? 
                      routeEtas.first['company']?.toString() ?? 
                      'KMB'; // Default to KMB if not specified

    return Container(
      margin: const EdgeInsets.only(bottom: 3, top: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasValidEta
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
          width: hasValidEta ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: const Color.fromARGB(0, 0, 0, 0),
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            final seq = routeEtas.first['seq']?.toString();
            final stopIdFromEta = stop.stopId;

            String? normalizedBound;
            if (bound != null && bound.toString().isNotEmpty) {
              final b = bound.toString().trim().toUpperCase();
              if (b.isNotEmpty) normalizedBound = b[0];
            }

            // ROUTING LOGIC: Navigate to appropriate page based on company
            final companyUpper = companyId.toUpperCase();
            
            if (companyUpper == 'CTB' || companyUpper == 'NWFB') {
              // Navigate to CTB Route Status Page
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CtbRouteStatusPage(
                  route: route,
                  bound: normalizedBound,
                  serviceType: serviceType.toString().isNotEmpty ? serviceType.toString() : null,
                  companyId: companyUpper, // Required parameter
                  autoExpandStopId: stopIdFromEta,
                  autoExpandSeq: seq,
                ),
              ));
            } else {
              // Navigate to KMB Route Status Page (default)
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => KmbRouteStatusPage(
                  route: route,
                  bound: normalizedBound,
                  serviceType: serviceType.toString().isNotEmpty ? serviceType.toString() : null,
                  companyId: null,
                  autoExpandSeq: seq,
                  autoExpandStopId: stopIdFromEta,
                ),
              ));
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildRouteBadge(route, bound, context),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        langProv.isEnglish ? 'To $displayDest' : '往 $displayDest',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 8),
                ...routeEtas.take(3).map((eta) {
                  final etaStr = eta['eta']?.toString() ?? '';
                  final rmkEn = eta['rmk_en'] ?? eta['rmken'] ?? '';
                  final rmkTc = eta['rmk_tc'] ?? eta['rmktc'] ?? '';
                  final rmk = langProv.isEnglish ? rmkEn : (rmkTc.isNotEmpty ? rmkTc : rmkEn);

                  String timeDisplay = '—', abs = '';
                  Color timeColor = Colors.grey;

                  if (etaStr.isNotEmpty) {
                    try {
                      final dt = DateTime.parse(etaStr).toLocal();
                      final now = DateTime.now();
                      final diff = dt.difference(now);
                      if (diff.inMinutes <= 0) {
                        timeDisplay = langProv.isEnglish ? 'Due' : '即將到站';
                        timeColor = Colors.red;
                        abs = DateFormat.Hm().format(dt);
                      } else if (diff.inMinutes <= 5) {
                        timeDisplay = langProv.isEnglish ? '${diff.inMinutes} min' : '${diff.inMinutes}分鐘';
                        timeColor = Colors.orange;
                        abs = DateFormat.Hm().format(dt);
                      } else if (diff.inMinutes < 60) {
                        timeDisplay = langProv.isEnglish ? '${diff.inMinutes} min' : '${diff.inMinutes}分鐘';
                        timeColor = Colors.green;
                        abs = DateFormat.Hm().format(dt);
                      } else {
                        timeDisplay = DateFormat.Hm().format(dt);
                        timeColor = Colors.blue;
                      }
                    } catch (_) {}
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text(abs, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: timeColor)),
                        const SizedBox(width: 8),
                        Container(width: 4, height: 4, decoration: BoxDecoration(color: timeColor, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(timeDisplay, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: timeColor)),
                        if (rmk.toString().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(rmk, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteBadge(String route, String dir, BuildContext context) {
    // Determine direction colors (matching existing app logic)
    Color dirColor = Colors.blue;
    if (dir.toUpperCase().startsWith('O')) {
      dirColor = Colors.green;
    } else if (dir.toUpperCase().startsWith('I')) {
      dirColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dirColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dirColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        route,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: dirColor,
          letterSpacing: -0.2,
        ),
      ),
    );
  }


}

class _StopDistance {
  final String stopId;
  final double lat;
  final double lng;
  final double distanceMeters;
  final Map<String, dynamic> meta;
  _StopDistance({required this.stopId, required this.lat, required this.lng, required this.distanceMeters, required this.meta});
}
