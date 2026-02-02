import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'api/kmb.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../kmb_route_status_page.dart';
import '../main.dart' show AccessibilityProvider, LanguageProvider;
import '../toTitleCase.dart';


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

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
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

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
      _nearby = [];
    });

    // Get language preference early
    LanguageProvider? langProv;
    if (mounted) {
      langProv = context.read<LanguageProvider>();
    }
  
    try {
    var status = await Permission.location.status;
    
    // Show rationale dialog if permission denied but not permanently
    if (status.isDenied) {
      final shouldRequest = await _showLocationRationaleDialog();
      if (!shouldRequest) {
        if (mounted) {
          setState(() {
            _error = langProv?.isEnglish ?? true 
                ? 'Location permission denied' 
                : '位置權限被拒絕';
            _loading = false;
          });
        }
        return;
      }
      
      // Request permission - this shows system popup
      status = await Permission.location.request();
    }
    

    // Handle permanently denied - direct to settings
    if (status.isPermanentlyDenied) {
      final shouldOpenSettings = await _showOpenSettingsDialog();
      if (shouldOpenSettings) {
        await openAppSettings();
      }
      if (mounted) {
        setState(() {
          _error = langProv?.isEnglish ?? true 
              ? 'Location permission required' 
              : '需要位置權限';
          _loading = false;
        });
      }
      return;
    }
    
    // Still not granted after request
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _error = langProv?.isEnglish ?? true 
              ? 'Location permission denied' 
              : '位置權限被拒絕';
          _loading = false;
        });
      }
      return;
    }
    


    

      // Use Geolocator to obtain a position
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _position = pos;

      // O(1) optimization: Build stop map and coordinates list once globally
      if (_globalStopMap == null || _allStopsWithCoords == null || _spatialGrid == null) {
        final stopMap = await Kmb.buildStopMap();
        
        if (stopMap.isEmpty) {
          setState(() {
            _error = langProv?.isEnglish ?? true 
              ? 'No stops data available. Please check your internet connection.' 
              : '沒有站點資料。請檢查您的網路連線。';
            _loading = false;
          });
          return;
        }
        
        _globalStopMap = stopMap;
        
        // Pre-compute all stop coordinates once and build spatial grid index
        final List<_StopDistance> allStops = [];
        final Map<String, List<_StopDistance>> grid = {};
        
        stopMap.forEach((stopId, meta) {
          try {
            final latRaw = meta['lat'] ?? meta['latitude'];
            final lngRaw = meta['long'] ?? meta['lng'] ?? meta['longitude'];
            if (latRaw == null || lngRaw == null) return;
            final lat = double.tryParse(latRaw.toString());
            final lng = double.tryParse(lngRaw.toString());
            if (lat == null || lng == null) return;
            
            final stop = _StopDistance(stopId: stopId, lat: lat, lng: lng, distanceMeters: 0, meta: meta);
            allStops.add(stop);
            
            // Add to spatial grid for O(1) lookup
            final gridKey = _getGridKey(lat, lng);
            grid.putIfAbsent(gridKey, () => []).add(stop);
          } catch (_) {}
        });
        
        _allStopsWithCoords = allStops;
        _spatialGrid = grid;
      }
      
      // O(1) spatial lookup: Only check stops in nearby grid cells
      final nearbyCells = _getNearbyCells(pos.latitude, pos.longitude, _rangeMeters);
      final List<_StopDistance> candidates = [];
      
      for (final cellKey in nearbyCells) {
        final cellStops = _spatialGrid![cellKey];
        if (cellStops != null) {
          candidates.addAll(cellStops);
        }
      }
      
      // O(k) where k = stops in nearby cells (typically 10-50 instead of 5000+)
      final List<_StopDistance> nearbyList = [];
      for (final stop in candidates) {
        final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, stop.lat, stop.lng);
        
        if (dist <= _rangeMeters) {
          nearbyList.add(_StopDistance(
            stopId: stop.stopId,
            lat: stop.lat,
            lng: stop.lng,
            distanceMeters: dist,
            meta: stop.meta,
          ));
        }
      }

      // O(k log k) where k is typically 10-50 (constant time in practice)
      nearbyList.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      
      setState(() {
        _nearby = nearbyList.take(50).toList();
        _loading = false;
      });

      // Fetch ETAs for nearby stops
      _fetchEtasForNearbyStops();
      
      // Set up auto-refresh every 30 seconds
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _fetchEtasForNearbyStops();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchEtasForNearbyStops() async {
    // Fetch all ETAs in parallel for better performance
    final futures = _nearby.map((stop) async {
      try {
        final etas = await Kmb.fetchStopEta(stop.stopId);
        return MapEntry(stop.stopId, etas);
      } catch (_) {
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
    // Fetch scale factor
    final double textScale = accProv.textScale;
    final isSelected = _rangeMeters == meters;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12 * textScale,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _rangeMeters = meters;
          });
          _init(); // Re-fetch with new range
        }
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
      checkmarkColor: Theme.of(context).colorScheme.primary,
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
    
    return Scaffold(
      body: _loading
          ? const Align(
              alignment: Alignment.bottomCenter, 
              child: Padding(
                padding: EdgeInsets.only(bottom: 2.0), // Adds 16 pixels of space at the top
                child: LinearProgressIndicator(year2023: false,),
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
                            Icons.straighten, 
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
                    Container(
                      width: double.infinity,
                      // 1. Reduced Padding (was 16/12)
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // 2. Reduced Icon Size (was 20)
                          Icon(
                            Icons.my_location,
                            size: 16, 
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          // 3. Reduced Spacing (was 8)
                          const SizedBox(width: 8), 
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      (langProv.isEnglish ? 'Current Location' : '目前位置'),
                                      // 4. Explicitly smaller font (was labelMedium)
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600, // Added weight for readability at small size
                                        fontSize: 11, // Force specific size if needed
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_position?.latitude.toStringAsFixed(6) ?? '-'}, ${_position?.longitude.toStringAsFixed(6) ?? '-'}',
                                      // 5. Explicitly smaller font (was labelSmall)
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                        fontSize: 10, // Even smaller for coordinates
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
    
    // Extract stop names from metadata
    // Fields come from API (/v1/transport/kmb/stop) or prebuilt JSON
    // API returns: name_en, name_tc, lat, long
    final nameEn = s.meta['name_en'] ?? s.meta['nameen'] ?? '';
    final nameTc = s.meta['name_tc'] ?? s.meta['nametc'] ?? '';
    final displayName = langProv.isEnglish
        ? ((nameEn?.toString().isNotEmpty ?? false) ? nameEn.toString() : (nameTc?.toString().isNotEmpty ?? false ? nameTc.toString() : s.stopId))
        : ((nameTc?.toString().isNotEmpty ?? false) ? nameTc.toString() : (nameEn?.toString().isNotEmpty ?? false ? nameEn.toString().toTitleCase() : s.stopId));
    
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
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showStopDetails(context, s, etas),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stop header
              Row(
                children: [
                  // Rank badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.54),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // Stop name and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AutoSizeText(
                          displayName.toTitleCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 11, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              _fmtDistance(s.distanceMeters, langProv: langProv),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            //Removed StopID for better visibility
                            /* Text(
                              s.stopId,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                                fontFamily: 'monospace',
                              ),
                            ), */
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  Icon(Icons.chevron_right, size: 30, color: Colors.grey[400]),
                ],
              ),
              
              // Routes
              if (etasByRoute.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: etasByRoute.entries.take(8).map((entry) {
                    return _buildRouteChip(context, entry.key, entry.value, langProv);
                  }).toList(),
                ),
              ] else if (_stopEtaCache.containsKey(s.stopId))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    langProv.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
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
    return Material(
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer 
          : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected 
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected 
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStopDetails(BuildContext context, _StopDistance stop, List<Map<String, dynamic>> etas) {
    final langProv = context.read<LanguageProvider>();
    
    // Extract stop names (same as _buildStopCard for consistency)
    final nameEn = stop.meta['name_en'] ?? stop.meta['nameen'] ?? '';
    final nameTc = stop.meta['name_tc'] ?? stop.meta['nametc'] ?? '';
    final displayName = langProv.isEnglish
        ? ((nameEn?.toString().isNotEmpty ?? false) ? nameEn.toString() : (nameTc?.toString().isNotEmpty ?? false ? nameTc.toString() : stop.stopId))
        : ((nameTc?.toString().isNotEmpty ?? false) ? nameTc.toString() : (nameEn?.toString().isNotEmpty ?? false ? nameEn.toString() : stop.stopId));
    
    // Group ETAs by route
    final Map<String, List<Map<String, dynamic>>> etasByRoute = {};
    for (final eta in etas) {
      final route = eta['route']?.toString() ?? '';
      if (route.isEmpty) continue;
      etasByRoute.putIfAbsent(route, () => []).add(eta);
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
        return ValueListenableBuilder<int>(
          valueListenable: sortOptionNotifier,
          builder: (context, sortOption, _) {
            // Sort function
            List<MapEntry<String, List<Map<String, dynamic>>>> getSortedEntries() {
              final entries = etasByRoute.entries.toList();
              
              entries.sort((a, b) {
                final routeA = a.key;
                final routeB = b.key;
                final etasA = a.value;
                final etasB = b.value;
                
                // Extract numeric part
                int? extractNumber(String route) {
                  final match = RegExp(r'\d+').firstMatch(route);
                  return match != null ? int.tryParse(match.group(0)!) : null;
                }
                
                if (sortOption == 1) {
                  // ✅ Sort by route number ONLY
                  final numA = extractNumber(routeA);
                  final numB = extractNumber(routeB);
                  
                  if (numA != null && numB != null) {
                    final numCompare = numA.compareTo(numB);
                    if (numCompare != 0) return numCompare;
                  }
                  return routeA.compareTo(routeB);
                }
                
                // ✅ Sort by ETA priority (sortOption == 0)
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
                
                // Fallback: route number
                final numA = extractNumber(routeA);
                final numB = extractNumber(routeB);
                if (numA != null && numB != null) {
                  return numA.compareTo(numB);
                }
                return routeA.compareTo(routeB);
              });
              
              return entries;
            }
            
            final sortedEntries = getSortedEntries();
            
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) => LiquidGlassLayer(
                // Define global glass settings for this layer
                settings: LiquidGlassSettings(
                  thickness: 19, // Glass refraction depth
                  blur: 10, // Background blur strength
                  glassColor: Theme.of(context).colorScheme.surface.withOpacity(0.3), // Semi-transparent tint
                  lightIntensity: 1.2,
                  saturation: 1.1,
                  refractiveIndex: 1.3,
                ),
                child: FakeGlass(
                  // Define the shape with top-rounded corners
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: 20, // Matches your original BorderRadius.circular(20)
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                langProv.isEnglish 
                                    ? 'KMB - ${displayName.toTitleCase()}' 
                                    : '九巴 - ${displayName.toTitleCase()}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
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
                      ),
                      
                      // Sort options
                      Padding(
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
                                      icon: Icons.access_time,
                                      isSelected: sortOption == 0,
                                      onTap: () => sortOptionNotifier.value = 0,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildSortChip(
                                      context: context,
                                      label: langProv.isEnglish ? 'Route No.' : '路線編號',
                                      icon: Icons.numbers,
                                      isSelected: sortOption == 1,
                                      onTap: () => sortOptionNotifier.value = 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Distance info
                      Padding(
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
                                  Icons.location_on,
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
                      ),
                      
                      const Divider(height: 8),
                      
                      // Content - ListView with sorted entries
                      Expanded(
                        child: sortedEntries.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.access_time, size: 48, color: Colors.grey[400]),
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
                                itemBuilder: (context, index) {
                                    final entry = sortedEntries[index];
                                    final route = entry.key;
                                    final routeEtas = entry.value;
                                    
                                    // ... 其餘的 ListView.builder 代碼保持不變
                                    routeEtas.sort((a, b) {
                                      final etaA = a['eta']?.toString() ?? '';
                                      final etaB = b['eta']?.toString() ?? '';
                                      return etaA.compareTo(etaB);
                                    });
                                    
                                    final destEn = routeEtas.first['dest_en'] ?? routeEtas.first['desten'] ?? '';
                                    final destTc = routeEtas.first['dest_tc'] ?? routeEtas.first['desttc'] ?? '';
                                    final displayDest = langProv.isEnglish ? destEn.toString().toTitleCase() : (destTc.isNotEmpty ? destTc.toString().toTitleCase() : destEn.toString().toTitleCase());
                                    final bound = routeEtas.first['dir'] ?? routeEtas.first['bound'] ?? '';
                                    final serviceType = routeEtas.first['service_type'] ?? routeEtas.first['servicetype'] ?? '';
                                    final hasValidEta = routeEtas.any((eta) => (eta['eta']?.toString() ?? '').isNotEmpty);
                                    
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 3, top: 6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: hasValidEta 
                                              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                              : Theme.of(context).colorScheme.outline.withOpacity(0.15),
                                          width: hasValidEta ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.of(context).pop();
                                            final seq = routeEtas.first['seq']?.toString();
                                            
                                            // ✓ 修正 1: 直接使用當前站點物件的 stopId
                                            // 這樣能保證 ID 與路線資料庫中的 ID 一致，StatusPage 才能正確比對
                                            final stopIdFromEta = stop.stopId;
                                            
                                            // ✓ 修正 2: 處理 Bound 方向格式，只取第一個字元 (O/I)
                                            String? normalizedBound;
                                            if (bound != null && bound.toString().isNotEmpty) {
                                              final b = bound.toString().trim().toUpperCase();
                                              if (b.isNotEmpty) normalizedBound = b[0]; // 取 'O' 或 'I'
                                            }

                                            Navigator.of(context).push(MaterialPageRoute(
                                              builder: (_) => KmbRouteStatusPage(
                                                route: route,
                                                bound: normalizedBound, // 傳遞正規化後的方向
                                                serviceType: serviceType.toString().isNotEmpty ? serviceType.toString() : null,
                                                companyId: null,
                                                autoExpandSeq: seq,
                                                autoExpandStopId: stopIdFromEta,
                                              ),
                                            ));
                                          },


                                          borderRadius: BorderRadius.circular(12),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context).colorScheme.primaryContainer,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        route,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                                        ),
                                                      ),
                                                    ),
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
                                                        Text(
                                                          abs,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w600,
                                                            color: timeColor,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          width: 4,
                                                          height: 4,
                                                          decoration: BoxDecoration(
                                                            color: timeColor,
                                                            shape: BoxShape.circle,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          timeDisplay,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w600,
                                                            color: timeColor,
                                                          ),
                                                        ),
                                                        if (rmk.toString().isNotEmpty) ...[
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              rmk,
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                              ),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
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
                                  },
                              ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }
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
}

class _StopDistance {
  final String stopId;
  final double lat;
  final double lng;
  final double distanceMeters;
  final Map<String, dynamic> meta;
  _StopDistance({required this.stopId, required this.lat, required this.lng, required this.distanceMeters, required this.meta});
}
