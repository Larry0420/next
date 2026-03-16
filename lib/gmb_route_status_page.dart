// GMB (Green Minibus) Route Status Page
// Displays route details, stops, and real-time ETA for GMB routes
//
// Data structure from prebuilt assets:
// {
//   "69": {  // routeNo
//     "variants": [
//       {
//         "routeId": 2000410,
//         "routeSeq": 1,
//         "region": "HKI",
//         "orig_tc": "數碼港",
//         "orig_en": "Cyberport",
//         "dest_tc": "鰂魚涌",
//         "dest_en": "Quarry Bay",
//         "stops": [{"stop_seq": 1, "stop_id": 20003337, ...}]
//       }
//     ]
//   }
// }

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kmb/api/gmb.dart';
import 'main.dart' show LanguageProvider, DeveloperSettingsProvider, EnhancedScrollPhysics;

class GmbRouteStatusPage extends StatefulWidget {
  final String routeNo;          // Display route number (e.g., "69")
  final int? initialRouteId;     // GMB route ID (e.g., 2000410)
  final int? initialRouteSeq;    // Direction: 1 or 2
  final String? region;          // HKI, KLN, or NT

  const GmbRouteStatusPage({
    super.key,
    required this.routeNo,
    this.initialRouteId,
    this.initialRouteSeq,
    this.region,
  });

  @override
  State<GmbRouteStatusPage> createState() => _GmbRouteStatusPageState();
}

class _GmbRouteStatusPageState extends State<GmbRouteStatusPage> {
  static const String _mapViewPreferenceKey = 'gmb_route_status_map_view_enabled';

  // State
  bool _loading = true;
  String? _error;

  // Data
  List<Map<String, dynamic>> _variants = [];
  int? _selectedRouteId;
  int? _selectedRouteSeq;
  Map<String, dynamic>? _selectedVariantData;
  Map<String, Map<String, dynamic>> _stopMap = {}; // stop_id -> stop details

  // Map View
  bool _showMapView = false;
  final MapController _mapController = MapController();
  final DraggableScrollableController _draggableController = DraggableScrollableController();

  // Animated highlight state
  String? _highlightedStopId;
  Timer? _highlightTimer;

  // Location
  Position? _userPosition;
  bool _locationLoading = false;

  // Keys for scrolling
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _stopKeys = {};

  @override
  void initState() {
    super.initState();
    _loadMapViewPreference();
    _initializeLocation();
    _fetchRouteData();
    _addToHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _draggableController.dispose();
    _highlightTimer?.cancel();
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

  Future<void> _addToHistory() async {
    // Deferred until data is loaded
  }

  Future<void> _initializeLocation() async {
    try {
      final status = await Permission.location.status;
      if (status.isGranted) {
        final last = await Geolocator.getLastKnownPosition();
        if (mounted && last != null) setState(() => _userPosition = last);

        final current = await Geolocator.getCurrentPosition();
        if (mounted) setState(() => _userPosition = current);
      }
    } catch (_) {}
  }

  Future<void> _fetchRouteData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Load prebuilt route data
      final routeMap = await _loadPrebuiltRouteData();

      // 2. Load prebuilt stop metadata
      final stopMap = await _loadPrebuiltStopData();

      if (!mounted) return;

      final routeNo = widget.routeNo.toUpperCase();
      if (!routeMap.containsKey(routeNo)) {
        throw Exception('Route $routeNo not found in GMB data');
      }

      final routeData = routeMap[routeNo] as Map<String, dynamic>;
      final variantsList = (routeData['variants'] as List<dynamic>? ?? [])
          .map((v) => Map<String, dynamic>.from(v))
          .toList();

      if (variantsList.isEmpty) {
        throw Exception('No variants found for route $routeNo');
      }

      // Sort variants by routeSeq then routeId
      variantsList.sort((a, b) {
        final seqA = a['routeSeq'] as int? ?? 1;
        final seqB = b['routeSeq'] as int? ?? 1;
        if (seqA != seqB) return seqA.compareTo(seqB);
        final idA = a['routeId'] as int? ?? 0;
        final idB = b['routeId'] as int? ?? 0;
        return idA.compareTo(idB);
      });

      // Select default variant
      int? selectedId = widget.initialRouteId;
      int? selectedSeq = widget.initialRouteSeq;

      if (selectedId != null) {
        // Find variant matching initialRouteId
        final match = variantsList.firstWhere(
          (v) => v['routeId'] == selectedId,
          orElse: () => variantsList.first,
        );
        selectedId = match['routeId'] as int?;
        selectedSeq = match['routeSeq'] as int? ?? 1;
      } else {
        // Use first variant
        selectedId = variantsList.first['routeId'] as int?;
        selectedSeq = variantsList.first['routeSeq'] as int? ?? 1;
      }

      final selectedData = variantsList.firstWhere(
        (v) => v['routeId'] == selectedId && v['routeSeq'] == selectedSeq,
        orElse: () => variantsList.first,
      );

      setState(() {
        _variants = variantsList;
        _stopMap = stopMap;
        _selectedRouteId = selectedId;
        _selectedRouteSeq = selectedSeq;
        _selectedVariantData = selectedData;
        _loading = false;
      });

      // Add to history
      if (_selectedVariantData != null) {
        final label = '${_selectedVariantData!['orig_en']} > ${_selectedVariantData!['dest_en']}';
        final region = _selectedVariantData!['region'] as String? ?? widget.region ?? 'HKI';
        await GMB.addToHistory(
          _selectedRouteId!,
          _selectedRouteSeq!,
          widget.routeNo,
          region,
          label,
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _loadPrebuiltRouteData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/prebuilt/gmb_route_stops.json');
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      debugPrint('Error loading GMB route data: $e');
      // Try to build from API as fallback
      return await GMB.buildRouteToStopsMap();
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadPrebuiltStopData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/prebuilt/gmb_stops.json');
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
    } catch (e) {
      debugPrint('Error loading GMB stop data: $e');
      // Try to build from API as fallback
      return await GMB.buildStopMap();
    }
  }

  void _onVariantSelected(int routeId, int routeSeq) {
    if (routeId == _selectedRouteId && routeSeq == _selectedRouteSeq) return;

    final variant = _variants.firstWhere(
      (v) => v['routeId'] == routeId && v['routeSeq'] == routeSeq,
      orElse: () => _variants.first,
    );

    setState(() {
      _selectedRouteId = routeId;
      _selectedRouteSeq = routeSeq;
      _selectedVariantData = variant;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNearestStop();
    });
  }

  void _toggleDirection() {
    if (_variants.length < 2) return;

    // Find opposite routeSeq
    final targetSeq = _selectedRouteSeq == 1 ? 2 : 1;
    final opposite = _variants.firstWhere(
      (v) => v['routeSeq'] == targetSeq,
      orElse: () => _variants.first,
    );

    _onVariantSelected(opposite['routeId'] as int, targetSeq);
  }

  Future<void> _scrollToNearestStop() async {
    if (_userPosition == null || _selectedVariantData == null) return;

    final stops = _selectedVariantData!['stops'] as List? ?? [];
    double minDistance = double.infinity;
    String? nearestStopId;

    for (final s in stops) {
      final stopId = s['stop_id'].toString();
      final meta = _stopMap[stopId];
      if (meta == null) continue;

      final lat = double.tryParse(meta['lat']?.toString() ?? '');
      final lng = double.tryParse(meta['long']?.toString() ?? '');

      if (lat != null && lng != null) {
        final d = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          lat,
          lng,
        );
        if (d < minDistance) {
          minDistance = d;
          nearestStopId = stopId;
        }
      }
    }

    if (nearestStopId != null) {
      final key = _stopKeys[nearestStopId];
      if (key?.currentContext != null) {
        await Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: isEnglish ? 'Back' : '返回',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${lang.route} ${widget.routeNo}'),
        actions: [
          IconButton(
            icon: Icon(_showMapView ? Icons.splitscreen : Icons.map),
            tooltip: _showMapView
                ? (isEnglish ? 'Show list' : '顯示列表')
                : (isEnglish ? 'Show map' : '顯示地圖'),
            onPressed: () {
              setState(() => _showMapView = !_showMapView);
              _saveMapViewPreference(_showMapView);
            },
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () async {
              setState(() => _locationLoading = true);
              await _initializeLocation();
              await _scrollToNearestStop();
              setState(() => _locationLoading = false);
            },
          ),
          IconButton(
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: () {
              if (_selectedVariantData != null && _selectedRouteId != null) {
                final label = isEnglish
                    ? 'To: ${_selectedVariantData!['dest_en']}'
                    : '往: ${_selectedVariantData!['dest_tc']}';
                final region = _selectedVariantData!['region'] as String? ?? widget.region ?? 'HKI';
                GMB.pinRoute(
                  _selectedRouteId!,
                  _selectedRouteSeq!,
                  widget.routeNo,
                  region,
                  label,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isEnglish ? 'Pinned' : '已釘選')),
                );
              }
            },
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchRouteData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_selectedVariantData == null) {
      return const Center(child: Text('No data found'));
    }

    final devSettings = context.watch<DeveloperSettingsProvider>();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 12.0,
            right: 12.0,
            top: 12.0,
            bottom: devSettings.useFloatingRouteToggles ? 80.0 : 0,
          ),
          child: _showMapView
              ? (isLandscape
                  ? Row(children: [
                      Expanded(child: _buildMapView()),
                      const SizedBox(width: 8),
                      Expanded(child: _buildListView(devSettings)),
                    ])
                  : Column(children: [
                      Expanded(flex: 1, child: _buildMapView()),
                      const SizedBox(height: 8),
                      Expanded(flex: 2, child: _buildListView(devSettings)),
                    ]))
              : _buildListView(devSettings),
        ),
        _buildFloatingBar(),
      ],
    );
  }

  Widget _buildListView(DeveloperSettingsProvider devSettings) {
    final stops = _selectedVariantData!['stops'] as List? ?? [];
    final paddingBottom = devSettings.useFloatingRouteToggles ? 200.0 : 20.0;

    return CustomScrollView(
      controller: _scrollController,
      physics: EnhancedScrollPhysics(),
      slivers: [
        if (!devSettings.useFloatingRouteToggles)
          SliverToBoxAdapter(child: _buildHeader()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final stopEntry = stops[index];
              return _buildStopCard(stopEntry, index);
            },
            childCount: stops.length,
          ),
        ),
        SliverPadding(padding: EdgeInsets.only(bottom: paddingBottom)),
      ],
    );
  }

  Widget _buildHeader() {
    if (_selectedVariantData == null) return const SizedBox.shrink();

    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    final orig = isEnglish
        ? _selectedVariantData!['orig_en']
        : _selectedVariantData!['orig_tc'];
    final dest = isEnglish
        ? _selectedVariantData!['dest_en']
        : _selectedVariantData!['dest_tc'];
    final region = _selectedVariantData!['region'] as String? ?? widget.region ?? 'HKI';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'GMB',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$orig → $dest',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  _getRegionName(region, isEnglish),
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getRegionName(String region, bool isEnglish) {
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

  Widget _buildFloatingBar() {
    final devSettings = context.watch<DeveloperSettingsProvider>();
    if (!devSettings.useFloatingRouteToggles) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: FakeGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 24),
          settings: LiquidGlassSettings(
            blur: 12.0,
            thickness: 50.0,
            glassColor: theme.colorScheme.surface.withValues(alpha: 0.3),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_variants.length > 1)
                  Expanded(
                    child: _buildDirectionToggle(isEnglish),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionToggle(bool isEnglish) {
    final canToggle = _variants.any((v) => v['routeSeq'] == (_selectedRouteSeq == 1 ? 2 : 1));

    return InkWell(
      onTap: canToggle ? _toggleDirection : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: canToggle
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.swap_horiz,
              size: 18,
              color: canToggle
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              isEnglish
                  ? (_selectedRouteSeq == 1 ? 'To Destination' : 'To Origin')
                  : (_selectedRouteSeq == 1 ? '往目的地' : '往起點'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: canToggle
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopCard(Map<String, dynamic> stopEntry, int index) {
    final stopId = stopEntry['stop_id'].toString();
    final stopSeq = stopEntry['stop_seq'].toString();
    final meta = _stopMap[stopId];

    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    String nameEn = meta?['name_en']?.toString() ?? '';
    String nameTc = meta?['name_tc']?.toString() ?? '';

    // Fallback to stopEntry if meta not available
    if (nameEn.isEmpty) nameEn = stopEntry['name_en']?.toString() ?? '';
    if (nameTc.isEmpty) nameTc = stopEntry['name_tc']?.toString() ?? '';

    final displayName = isEnglish
        ? (nameEn.isNotEmpty ? nameEn : nameTc)
        : (nameTc.isNotEmpty ? nameTc : nameEn);

    // Check if nearby
    bool isNearby = false;
    if (_userPosition != null && meta != null) {
      final lat = double.tryParse(meta['lat']?.toString() ?? '');
      final lng = double.tryParse(meta['long']?.toString() ?? '');
      if (lat != null && lng != null) {
        final d = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          lat,
          lng,
        );
        isNearby = d < 200;
      }
    }

    // Store key for scrolling
    _stopKeys[stopId] = GlobalKey();

    return Container(
      key: _stopKeys[stopId],
      child: GmbStopCard(
        routeId: _selectedRouteId!,
        stopId: int.tryParse(stopId) ?? 0,
        seq: stopSeq,
        displayName: displayName,
        nameEn: nameEn,
        nameTc: nameTc,
        isEnglish: isEnglish,
        isNearby: isNearby,
      ),
    );
  }

  Widget _buildMapView() {
    final stops = _selectedVariantData!['stops'] as List? ?? [];
    final List<Marker> markers = [];
    final List<LatLng> points = [];

    for (final s in stops) {
      final stopId = s['stop_id'].toString();
      final seq = s['stop_seq'].toString();
      final meta = _stopMap[stopId];
      if (meta == null) continue;

      final lat = double.tryParse(meta['lat']?.toString() ?? '');
      final lng = double.tryParse(meta['long']?.toString() ?? '');
      if (lat == null || lng == null) continue;

      final point = LatLng(lat, lng);
      points.add(point);
      final isHighlighted = _highlightedStopId == stopId;

      markers.add(Marker(
        point: point,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () {
            setState(() => _showMapView = false);
            _saveMapViewPreference(false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final key = _stopKeys[stopId];
              if (key?.currentContext != null) {
                Scrollable.ensureVisible(
                  key!.currentContext!,
                  duration: const Duration(milliseconds: 500),
                );
              }
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isHighlighted)
                _PulsingRing(color: Theme.of(context).colorScheme.tertiary),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? Theme.of(context).colorScheme.tertiary
                      : Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: isHighlighted ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isHighlighted
                          ? Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5)
                          : Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                      blurRadius: isHighlighted ? 8 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  seq,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isHighlighted ? 14 : 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    }

    // Calculate center
    LatLng center;
    double zoom = 13.0;

    if (_userPosition != null) {
      center = LatLng(_userPosition!.latitude, _userPosition!.longitude);
      zoom = 14.0;
    } else if (points.isNotEmpty) {
      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (final point in points) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;
      final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

      if (maxDiff > 0.1) zoom = 11.0;
      else if (maxDiff > 0.05) zoom = 12.0;
      else if (maxDiff > 0.02) zoom = 13.0;
      else zoom = 14.0;
    } else {
      center = const LatLng(22.3193, 114.1694);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
          minZoom: 10.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.lrtnexttrain',
            maxZoom: 19,
            minZoom: 10,
            maxNativeZoom: 18,
            panBuffer: 2,
            tileSize: 256,
            retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
            tileProvider: NetworkTileProvider(),
            keepBuffer: 5,
          ),
          if (points.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 4.0,
                  color: Colors.green.withValues(alpha: 0.7),
                ),
              ],
            ),
          MarkerLayer(markers: markers),
          CurrentLocationLayer(
            alignPositionOnUpdate: AlignOnUpdate.never,
            alignDirectionOnUpdate: AlignOnUpdate.never,
            style: LocationMarkerStyle(
              marker: DefaultLocationMarker(
                color: Theme.of(context).colorScheme.error,
                child: Icon(
                  Icons.navigation,
                  color: Theme.of(context).colorScheme.onError,
                  size: 10,
                ),
              ),
              markerSize: const Size(18, 18),
              markerDirection: MarkerDirection.heading,
              headingSectorColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
              headingSectorRadius: 60,
              accuracyCircleColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
              showAccuracyCircle: true,
              showHeadingSector: true,
            ),
          ),
        ],
      ),
    );
  }
}

class GmbStopCard extends StatefulWidget {
  final int routeId;
  final int stopId;
  final String seq;
  final String displayName;
  final String nameEn;
  final String nameTc;
  final bool isEnglish;
  final bool isNearby;

  const GmbStopCard({
    super.key,
    required this.routeId,
    required this.stopId,
    required this.seq,
    required this.displayName,
    required this.nameEn,
    required this.nameTc,
    required this.isEnglish,
    required this.isNearby,
  });

  @override
  State<GmbStopCard> createState() => _GmbStopCardState();
}

class _GmbStopCardState extends State<GmbStopCard> {
  bool _expanded = false;
  bool _loading = false;
  List<Map<String, dynamic>>? _etas;
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _fetchEta();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _fetchEta(silent: true),
      );
    } else {
      _refreshTimer?.cancel();
    }
  }

  Future<void> _fetchEta({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);

    try {
      final results = await GMB.fetchRouteStopEtaByStopId(
        widget.routeId,
        widget.stopId,
      );

      // Flatten the ETA data from the nested structure
      // Each result has: { "enabled": true, "stop_id": ..., "eta": [...] }
      final List<Map<String, dynamic>> flattenedEtas = [];
      for (final result in results) {
        if (result['enabled'] == true && result['eta'] is List) {
          final etaList = (result['eta'] as List).cast<Map<String, dynamic>>();
          flattenedEtas.addAll(etaList);
        }
      }

      // Sort by eta_seq
      flattenedEtas.sort((a, b) => 
        (a['eta_seq'] as int? ?? 0).compareTo(b['eta_seq'] as int? ?? 0));

      if (mounted) {
        setState(() {
          _etas = flattenedEtas;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isActive = _expanded || widget.isNearby;

    return Card(
      elevation: isActive ? 2 : 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: widget.isNearby
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.3)
          : (isActive ? colorScheme.surfaceContainerHigh : colorScheme.surfaceContainerLow),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: widget.isNearby ? colorScheme.tertiary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Seq Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.isNearby ? colorScheme.tertiary : Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.seq,
                      style: TextStyle(
                        color: widget.isNearby ? colorScheme.onTertiary : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ETA Preview or Icon
                  if (!_expanded && !widget.isNearby)
                    Icon(Icons.expand_more, color: colorScheme.onSurfaceVariant),
                ],
              ),
              // Expanded Area (ETA)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                child: _expanded ? _buildEtaList() : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEtaList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_etas == null || _etas!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(widget.isEnglish ? 'No upcoming minibuses' : '暫無班次'),
      );
    }

    return Column(
      children: [
        const Divider(),
        ..._etas!.map((e) {
          final diff = e['diff'] as int?; // Relative minutes
          final remarksTc = e['remarks_tc']?.toString();
          final remarksEn = e['remarks_en']?.toString();
          final remarks = widget.isEnglish
              ? (remarksEn ?? remarksTc)
              : (remarksTc ?? remarksEn);

          String timeText;
          Color timeColor;

          if (diff != null) {
            if (diff <= 0) {
              timeText = widget.isEnglish ? 'Arriving' : '即到達';
              timeColor = Colors.green;
            } else if (diff < 60) {
              timeText = '$diff ${widget.isEnglish ? 'min' : '分鐘'}';
              timeColor = diff <= 5 ? Colors.orange : Colors.green;
            } else {
              final hours = diff ~/ 60;
              final mins = diff % 60;
              timeText = widget.isEnglish
                  ? '${hours}h ${mins}m'
                  : '${hours}小時${mins}分鐘';
              timeColor = Colors.blue;
            }
          } else {
            timeText = '--';
            timeColor = Colors.grey;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: timeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: timeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: timeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (remarks != null && remarks.isNotEmpty)
                  Expanded(
                    child: Text(
                      remarks,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Color color;

  const _PulsingRing({required this.color});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 40 * _animation.value,
          height: 40 * _animation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(
              alpha: (1.5 - _animation.value) * 0.5,
            ),
          ),
        );
      },
    );
  }
}