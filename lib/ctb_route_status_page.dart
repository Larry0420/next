// Standard Dart libraries
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

// Flutter core and foundation
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// Flutter/Third-party packages
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Local project files / API
import '/kmb/api/citybus.dart';
import '../main.dart' show LanguageProvider, DeveloperSettingsProvider, UIConstants, EnhancedScrollPhysics, AccessibilityProvider;
import 'optionalMarquee.dart';
import 'toTitleCase.dart';


class CtbRouteStatusPage extends StatefulWidget {
  final String route;
  final String? bound;
  final String? serviceType;
  final String? companyId;
  /// Optional stop ID to auto-expand when page loads
  final String? autoExpandStopId;
  /// Optional sequence number to auto-expand when page loads
  final String? autoExpandSeq;
  const CtbRouteStatusPage({
    super.key, 
    required this.route, 
    this.bound, 
    this.serviceType,
    required this.companyId,
    this.autoExpandStopId,
    this.autoExpandSeq,
  });

  @override
  State<CtbRouteStatusPage> createState() => _CtbRouteStatusPageState();
}
String? _autoExpandSeq;
class _CtbRouteStatusPageState extends State<CtbRouteStatusPage> {
  // Preference key for map view state
  static const String _mapViewPreferenceKey = 'ctb_route_status_map_view_enabled';
  final DraggableScrollableController _draggableController = DraggableScrollableController();



  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  // route variant selectors and route-level ETA state
  List<String> _directions = [];
  List<String> _serviceTypes = [];
  String? _selectedDirection;
  String? _selectedServiceType;

  bool _routeEtaLoading = false;
  String? _routeEtaError;
  List<Map<String, dynamic>>? _routeEtaEntries;
  
  // O(1) ETA lookup cache - precomputed HashMap for instant seq->ETAs mapping
  Map<String, List<Map<String, dynamic>>>? _etaBySeqCache;

  // Route details for verification and display
  Map<String, dynamic>? _routeDetails;
  bool _routeDetailsLoading = false;
  String? _routeDetailsError;
  
  // Scroll controller for auto-scroll to nearest stop
  final ScrollController _scrollController = ScrollController();
  
  // User location for finding nearest stop
  Position? _userPosition;
  bool _locationLoading = false;
  bool _showLocationBanner = false; // Show compact banner during locating
  
  // Floating bottom bar visibility
  bool _showFloatingBar = true;
  double _lastScrollOffset = 0.0;
  
  // Map view state
  bool _showMapView = false;
  final MapController _mapController = MapController();
  
  // Animated highlight state for clicked stop
  String? _highlightedStopId;
  Timer? _highlightTimer;
  
  // Keys for per-stop widgets to support ensureVisible auto-scroll
  final Map<String, GlobalKey> _stopKeys = {};
  
  // Variant-scoped auto-scroll guard to avoid repositioning on auto-refresh
  String? _lastAutoScrollVariantKey;
  
  /// Track if ETA has been fetched at least once (for silent refresh)
  bool _hasLoadedEtaOnce = false;
  
  // ETA auto-refresh (page-level, similar to LRT adaptive timer)
  Timer? _etaRefreshTimer;
  Duration _etaRefreshInterval = const Duration(seconds: 15);
  int _etaConsecutiveErrors = 0;
  // When false, page-level periodic ETA refresh is disabled and per-card fetching is used.
  // Set to true to re-enable the legacy page-level timer behavior.
  final bool _enablePageLevelEtaAutoRefresh = false;
  

  
  // Method to jump to a specific location on the map with animated highlight
  void _jumpToMapLocation(double latitude, double longitude, {String? stopId}) {
    // Set highlighted stop for animation
    if (stopId != null) {
      setState(() {
        _highlightedStopId = stopId;
      });
      
      // Clear highlight after 3 seconds
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
      // Enable map view if not already shown
      setState(() {
        _showMapView = true;
      });
      // Save preference when map is enabled
      _saveMapViewPreference(true);
      // Wait for map to build, then move to location
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _mapController.move(LatLng(latitude, longitude), 17.0); // Closer zoom for better view
          }
        });
      });
    } else {
      // Map already shown, just move to location
      _mapController.move(LatLng(latitude, longitude), 17.0);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMapViewPreference();
    _fetch();
    _addToHistory();
    //_scrollController.addListener(_onScroll);
    _initializeLocation(); // Get user location on startup
    // Start ETA auto-refresh after first frame when selections are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartEtaAutoRefresh();
    });
  }
  
  /// Load saved map view preference from SharedPreferences
  Future<void> _loadMapViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPreference = prefs.getBool(_mapViewPreferenceKey);
      if (savedPreference != null && mounted) {
        setState(() {
          _showMapView = savedPreference;
        });
      }
    } catch (_) {
      // Silently fail - use default value
    }
  }
  
  /// Save map view preference to SharedPreferences
  Future<void> _saveMapViewPreference(bool showMapView) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mapViewPreferenceKey, showMapView);
    } catch (_) {
      // Silently fail
    }
  }
  
  /// Initialize user location if permission is granted
  Future<void> _initializeLocation() async {
    try {
      final status = await Permission.location.status;
      if (status.isGranted) {
        // FAST: Get last known position first for instant nearby detection
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null && mounted) {
            setState(() => _userPosition = lastPos);
          }
        } catch (_) {}

        // Show banner only if no position yet
        if (_userPosition == null && mounted) {
          setState(() => _showLocationBanner = true);
        }

        // ACCURATE: Get current position in background
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Location request timed out'),
        );
        if (mounted) {
          setState(() {
            _userPosition = pos;
            _showLocationBanner = false;
          });
        }
      }
    } catch (e) {
      // Silently fail - location is optional
      if (mounted) {
        setState(() => _showLocationBanner = false);
      }
    }
  }
  
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Only toggle floating bar, do NOT call _fetch() here
    if (maxScroll - currentOffset < 100) {
      if (_showFloatingBar) {
        setState(() => _showFloatingBar = false);
      }
    } else if (maxScroll - currentOffset > 150) {
      if (!_showFloatingBar) {
        setState(() => _showFloatingBar = true);
      }
    }
    _lastScrollOffset = currentOffset;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _stopEtaAutoRefresh();
    _draggableController.dispose();
    super.dispose();
  }

  void _addToHistory() async {
    // Add this route to history automatically
    final r = widget.route.trim().toUpperCase();
    String label = r;

    // Wait a bit for route details to load
    await Future.delayed(const Duration(milliseconds: 500));

    if (_routeDetails != null) {
      final routeData = _routeDetails!.containsKey('data')
          ? _routeDetails!['data'] as Map<String, dynamic>?
          : _routeDetails!;

      if (routeData != null && mounted) {
        final lang = context.read<LanguageProvider>();
        final isEnglish = lang.isEnglish;
        final orig = isEnglish
            ? routeData['orig_en'] ?? routeData['orig_tc'] ?? ''
            : routeData['orig_tc'] ?? routeData['orig_en'] ?? '';
        final dest = isEnglish
            ? routeData['dest_en'] ?? routeData['dest_tc'] ?? ''
            : routeData['dest_tc'] ?? routeData['dest_en'] ?? '';

        if (orig.isNotEmpty && dest.isNotEmpty) {
          label = '$r: $orig → $dest';
        }
      }
    }

    // CTB: No service type parameter
    await Citybus.addToHistory(
      r,
      label,
    );
  }


  String _formatEta(BuildContext context, dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      // Respect device/user 24-hour preference when available
      final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
      if (use24) {
        return DateFormat.Hm().format(dt); // 24-hour HH:mm
      } else {
        // jm() will format as e.g. 5:08 PM for en_US, or follow locale conventions
        final locale = Localizations.localeOf(context).toString();
        return DateFormat.jm(locale).format(dt);
      }
    } catch (_) {
      return raw?.toString() ?? '—';
    }
  }

  /// Return a compact relative + absolute ETA string suitable for quick glance.
  /// Examples: "5 min (19:56)", "Due (19:56)", "Departed".
    /// Return a compact relative + absolute ETA string suitable for quick glance.
  /// Examples: "5 min (19:56)", "Due (19:56)", "Departed".
  String _formatEtaWithRelative(BuildContext context, dynamic raw) {
    if (raw == null) return '—';
    try {
      final isEnglish = context.read<LanguageProvider>().isEnglish;
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final diff = dt.difference(now);
      final absSeconds = diff.inSeconds.abs();

      String relative;

      // "Due" window: within 45 seconds either side (slightly relaxed from 30s)
      if (absSeconds < 45) {
        relative = isEnglish ? 'Due' : '即將到達';
      } else if (diff.isNegative) {
        // Past
        final mins = diff.abs().inMinutes;
        if (mins < 1) {
          // Between 45s and 60s ago
          relative = isEnglish ? 'Departed' : '已離開';
        } else if (mins < 60) {
          relative = isEnglish ? '$mins min ago' : '$mins分鐘前';
        } else {
          final h = diff.abs().inHours;
          final m = diff.abs().inMinutes % 60;
          relative = isEnglish
              ? '${h}h${m > 0 ? ' ${m}m' : ''} ago'
              : '$h小時${m > 0 ? '$m分' : ''}前';
        }
      } else {
        // Future
        final mins = diff.inMinutes;
        if (mins < 1) {
          // Between 45s and 60s future
          relative = isEnglish ? 'Due' : '即將到達';
        } else if (mins < 60) {
          relative = isEnglish ? '$mins min' : '$mins分鐘';
        } else {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          relative = isEnglish
              ? '${h}h${m > 0 ? ' ${m}m' : ''}'
              : '$h小時${m > 0 ? '$m分' : ''}';
        }
      }

      final abs = _formatEta(context, raw);
      // Simplify output if it just says "Departed" to avoid redundancy like "Departed (10:00)" if preferred, 
      // but keeping absolute time is usually helpful for context.
      return '$relative ($abs)';
    } catch (_) {
      return raw?.toString() ?? '—';
    }
  }

  bool _combinedLoading = false;
  String? _combinedError;
  Map<String, dynamic>? _combinedData;
  

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });
    
    // Start loading route info immediately (independent of stop list)
    final r = widget.route.trim().toUpperCase();
    _loadVariantsFromCache(r, widget.bound,);
    
    try {
      // Try to load prebuilt assets first (fast startup)
      final rnorm = widget.route.trim().toUpperCase();
      final prebuiltLoaded = await _attemptLoadPrebuilt(rnorm);
      if (prebuiltLoaded) {
        setState(() { loading = false; });
        return;
      }
  final useRouteApi = await Citybus.getUseRouteApiSetting();
      final base = RegExp(r'^(\\d+)').firstMatch(r)?.group(1) ?? r;

      if (useRouteApi) {
        // User prefers freshest per-route API
        final result = await Citybus.fetchRouteStatus(r);
        setState(() { 
          data = result;
          loading = false;
        });
        return;
      }

      // Default: use prebuilt map first, fall back to per-route API
      final map = await Citybus.buildRouteToStopsMap();
      if (map.containsKey(r) || map.containsKey(base)) {
        final entries = map[r] ?? map[base]!;
        setState(() {
          data = {
            'type': 'RouteStopList',
            'version': 'prebuilt',
            'generatedtimestamp': DateTime.now().toIso8601String(),
            'data': entries,
          };
          loading = false;
        });
      } else {
        final result = await Citybus.fetchRouteStatus(r);
        setState(() { 
          data = result;
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  /// Try to read prebuilt JSON assets and populate `data` if the route is present.
  /// Returns true when prebuilt data was found and applied.
  Future<bool> _attemptLoadPrebuilt(String route) async {
    try {
      String? raw;
      // Try bundled asset first (packaged with app, most reliable)
      try {
        raw = await rootBundle.loadString('assets/prebuilt/ctb_route_stops.json');
      } catch (_) {
        raw = null;
      }

      // Fallback to app documents prebuilt (written by Regenerate prebuilt data)
      if (raw == null) {
        try {
          final doc = await getApplicationDocumentsDirectory();
          final f = File('${doc.path}/prebuilt/ctb_route_stops.json');
          if (f.existsSync()) raw = await f.readAsString();
        } catch (_) {}
      }
      if (raw == null || raw.isEmpty) return false;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      // Keys are route strings; try exact or base match
      final r = route.toUpperCase();
      if (decoded.containsKey(r)) {
        final routeValue = decoded[r];
        List<Map<String, dynamic>> entries;
        
        // Case A: legacy list-of-entries format
        if (routeValue is List) {
          entries = List<Map<String, dynamic>>.from(routeValue.map((e) => Map<String, dynamic>.from(e as Map)));
        }
        // Case B: optimized per-bound structure { "I": { orig_en, orig_tc, dest_en, dest_tc, stops: [...] }, "O": {...} }
        else if (routeValue is Map) {
          final routeObj = routeValue as Map<String, dynamic>;
          entries = <Map<String, dynamic>>[];
          
          routeObj.forEach((boundKey, boundVal) {
            try {
              final boundObj = boundVal as Map<String, dynamic>;
              
              // ✅ 修正：同時提取起點和終點
              final origEn = (boundObj['orig_en'] ?? boundObj['origen'] ?? '')?.toString() ?? '';
              final origTc = (boundObj['orig_tc'] ?? boundObj['origtc'] ?? '')?.toString() ?? '';
              final destEn = (boundObj['dest_en'] ?? boundObj['desten'] ?? '')?.toString() ?? '';
              final destTc = (boundObj['dest_tc'] ?? boundObj['desttc'] ?? '')?.toString() ?? '';
              
              final stopsList = boundObj['stops'];
              
              if (stopsList is List) {
                for (final rawEntry in stopsList) {
                  try {
                    final entry = Map<String, dynamic>.from(rawEntry as Map);
                    
                    // Inject bound
                    entry['bound'] = boundKey; // 'I' or 'O'
                    
                    if (entry.containsKey('dir')) {
                      final dirValue = entry['dir']?.toString().trim().toUpperCase() ?? '';
                      if (dirValue == 'I' || dirValue == 'O') {
                        entry['bound'] = dirValue;
                      }
                    }
                    
                    entry['direction'] = boundKey == 'I' ? 'inbound' : 'outbound';
                    
                    // ✅ 注入起點和終點
                    if (origEn.isNotEmpty) entry['origen'] = origEn;
                    if (origTc.isNotEmpty) entry['origtc'] = origTc;
                    if (destEn.isNotEmpty) entry['desten'] = destEn;
                    if (destTc.isNotEmpty) entry['desttc'] = destTc;
                    
                    entries.add(entry);
                  } catch (_) {}
                }
              }
            } catch (_) {}
          });
        } else {
          return false; // Unknown format
        }
        
        // Immediately show the raw entries to avoid blocking UI while we enrich
        setState(() {
          data = {
            'type': 'RouteStopList',
            'version': 'prebuilt-asset',
            'generatedtimestamp': DateTime.now().toIso8601String(),
            'data': entries,
          };
          _combinedData = null;
        });

        // Enrich stop entries with metadata off the main isolate to avoid jank
        try {
          final stopMap = await Citybus.buildStopMap();
          final enriched = await compute(_enrichEntriesForStopMap, {'entries': entries, 'stopMap': stopMap});
          if (mounted) {
            setState(() {
              data = {
                'type': 'RouteStopList',
                'version': 'prebuilt-asset',
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': enriched,
              };
              _combinedData = {
                'type': 'CombinedRouteStatus',
                'route': r,
                'serviceType': null,
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': {
                  'stops': enriched,
                  'routeEta': [],
                }
              };
            });
          }
        } catch (_) {
          // ignore enrichment failures; raw entries already displayed
        }
        // populate variants from cache by ensuring route->stops map is built
        try { await Citybus.buildRouteToStopsMap(); } catch (_) {}
        _loadVariantsFromCache(r, widget.bound,);
        return true;
      }

      // Try base numeric key
      final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1);
      if (base != null && decoded.containsKey(base)) {
        final routeValue = decoded[base];
        List<Map<String, dynamic>> entries;
        
        // Case A: legacy list-of-entries format
        if (routeValue is List) {
          entries = List<Map<String, dynamic>>.from(routeValue.map((e) => Map<String, dynamic>.from(e as Map)));
        }
        // Case B: optimized per-bound structure { "I": { dest_en, dest_tc, stops: [...] }, "O": {...} }
        else if (routeValue is Map) {
          final routeObj = routeValue as Map<String, dynamic>;
          entries = <Map<String, dynamic>>[];
          routeObj.forEach((boundKey, boundVal) {
            try {
              final boundObj = boundVal as Map<String, dynamic>;
              final destEn = (boundObj['dest_en'] ?? boundObj['desten'] ?? '')?.toString() ?? '';
              final destTc = (boundObj['dest_tc'] ?? boundObj['desttc'] ?? '')?.toString() ?? '';
              final stopsList = boundObj['stops'];
              if (stopsList is List) {
                for (final rawEntry in stopsList) {
                  try {
                    final entry = Map<String, dynamic>.from(rawEntry as Map);
                    // Inject bound and dest fields for convenience
                    // Ensure bound is set correctly - use boundKey from JSON structure
                    entry['bound'] = boundKey; // 'I' or 'O'
                    // Also preserve original 'dir' field if present, but normalize to bound
                    if (entry.containsKey('dir')) {
                      final dirValue = entry['dir']?.toString().trim().toUpperCase() ?? '';
                      // If dir is 'I' or 'O', use it; otherwise use boundKey
                      if (dirValue == 'I' || dirValue == 'O') {
                        entry['bound'] = dirValue;
                      }
                    }
                    entry['direction'] = boundKey == 'I' ? 'inbound' : 'outbound';
                    if (destEn.isNotEmpty) entry['dest_en'] = destEn;
                    if (destTc.isNotEmpty) entry['dest_tc'] = destTc;
                    entries.add(entry);
                  } catch (_) {}
                }
              }
            } catch (_) {}
          });
        } else {
          return false; // Unknown format
        }
        
        setState(() {
          data = {
            'type': 'RouteStopList',
            'version': 'prebuilt-asset',
            'generatedtimestamp': DateTime.now().toIso8601String(),
            'data': entries,
          };
          _combinedData = null;
        });
        try {
          final stopMap = await Citybus.buildStopMap();
          final enriched = await compute(_enrichEntriesForStopMap, {'entries': entries, 'stopMap': stopMap});
          if (mounted) {
            setState(() {
              data = {
                'type': 'RouteStopList',
                'version': 'prebuilt-asset',
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': enriched,
              };
              _combinedData = {
                'type': 'CombinedRouteStatus',
                'route': r,
                'serviceType': null,
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': {
                  'stops': enriched,
                  'routeEta': [],
                }
              };
            });
          }
        } catch (_) {}
        try { await Citybus.buildRouteToStopsMap(); } catch (_) {}
        _loadVariantsFromCache(r, widget.bound,);
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    return Scaffold(
      appBar: AppBar(
        // 1. Custom Back Button (Localized)
        // This ensures the tooltip matches your app's language, not just the system language
        leading: 
        //Consumer<AccessibilityProvider>(
          //builder: (context, accessibility, _) => 
          IconButton(
            icon: Icon(Icons.arrow_back, size: 24 /* *accessibility.iconScale*/),
            tooltip: isEnglish ? 'Back' : '返回',
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 24,
          ),
        //),

        title: Text('${lang.route} ${widget.route}'),

        actions: [
          // 2. Map/List Toggle
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => IconButton(
              icon: Icon(
                _showMapView ? Icons.splitscreen : Icons.map,
                size: 24 * accessibility.iconScale,
              ),
              tooltip: _showMapView
                  ? (isEnglish ? 'Show list only' : '僅顯示列表')
                  : (isEnglish ? 'Show map' : '顯示地圖'),
              onPressed: () {
                final newValue = !_showMapView;
                setState(() {
                  _showMapView = newValue;
                });
                _saveMapViewPreference(newValue);
              },
              splashRadius: 24,
            ),
          ),

          // 3. Location Button
          if (_scrollController.hasClients)
            Consumer<AccessibilityProvider>(
              builder: (context, accessibility, _) => IconButton(
                icon: _locationLoading 
                  ? SizedBox(
                      width: 20 * accessibility.iconScale,
                      height: 20 * accessibility.iconScale,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, 
                        color: Theme.of(context).appBarTheme.iconTheme?.color ?? Theme.of(context).iconTheme.color
                      ),
                    )
                  : Icon(
                      _userPosition != null ? Icons.my_location : Icons.location_searching,
                      size: 24 * accessibility.iconScale,
                    ),
                tooltip: isEnglish ? 'Scroll to nearest stop' : '捲動至最近站點',
                onPressed: _locationLoading ? null : () async {
                  // Get current stops from the list
                  List<Map<dynamic, dynamic>> stops = [];
                  if (_variantStops != null && _variantStops!.isNotEmpty) {
                    stops = _variantStops!;
                  } else {
                    // Try to get from cached data
                    try {
                      final routeMap = await Citybus.buildRouteToStopsMap();
                      final r = widget.route.trim().toUpperCase();
                      final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
                      final entries = routeMap[r] ?? routeMap[base] ?? [];
                    
                      // Filter by selected direction/service
                      stops = entries.where((e) {
                        if (!e.containsKey('seq')) return false;
                        if (_selectedDirection != null) {
                          final bound = e['bound']?.toString().trim().toUpperCase() ?? '';
                          if (bound.isNotEmpty && _selectedDirection!.isNotEmpty &&
                              bound[0] != _selectedDirection![0]) {
                            return false;
                          }
                        }
                        if (_selectedServiceType != null) {
                          final st = e['service_type']?.toString() ?? e['servicetype']?.toString() ?? '';
                          if (st != _selectedServiceType) return false;
                        }
                        return true;
                      }).toList();
                    
                      stops.sort((a, b) {
                        final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
                        final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
                        return ai.compareTo(bi);
                      });
                    } catch (_) {}
                  }
                
                  if (stops.isNotEmpty) {
                    await _getUserLocationAndScrollToNearest(stops);
                  }
                },
              ),
            ),

          // 4. Pin Button
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => IconButton(
              icon: const Icon(Icons.push_pin_outlined),
              tooltip: lang.pinRoute,
              onPressed: _pinRoute,
            ),
          ),  

          // 5. Language Toggle (Your Snippet)
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => IconButton(
              icon: Icon(Icons.translate, size: 24 * accessibility.iconScale),
              tooltip: lang.language,
              onPressed: lang.toggle,
              splashRadius: 24,
            ),
          ),
        ],
      ),

      body: Stack(
        children: [
          Consumer<DeveloperSettingsProvider>(
            builder: (context, devSettings, _) {
              // Determine if we should show split view (map + list together)
              final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
              final showSplitView = _showMapView;
              final screenWidth = MediaQuery.of(context).size.width;
              final isMobile = screenWidth < 600;
              
              return Padding(
                // Add bottom padding only when floating bar is enabled
                padding: EdgeInsets.only(
                  left: 12.0, 
                  right: 12.0, 
                  top: 12.0, 
                  bottom: devSettings.useFloatingRouteToggles ? 80.0 : 12.0,
                ),
                child: showSplitView
                  ? (isLandscape 
                      // Landscape: side-by-side split view
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Map on left (less space on mobile)
                            Expanded(
                              flex: isMobile ? 2 : 1,
                              child: _buildMapView(),
                            ),
                            const SizedBox(width: 8),
                            // List on right (more space on mobile for better readability)
                            Expanded(
                              flex: isMobile ? 3 : 1,
                              child: _buildListView(devSettings),
                            ),
                          ],
                        )
                      // Portrait: top-bottom split view
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Map on top (less space on mobile for more list visibility)
                            Expanded(
                              flex: isMobile ? 2 : 1,
                              child: _buildMapView(),
                            ),
                            const SizedBox(height: 8),
                            // List on bottom (more space on mobile)
                            Expanded(
                              flex: isMobile ? 3 : 1,
                              child: _buildListView(devSettings),
                            ),
                          ],
                        ))
                  // Map view disabled: show only list
                  : _buildListView(devSettings),
              );
            },
          ),
          // Floating bottom bar with direction and service type toggles
          _buildFloatingBottomBar(),
        ],
      ),
    );
  }

    /// Build the list view using Slivers for better performance and flexibility
  Widget _buildListView(DeveloperSettingsProvider devSettings) {
    final bottomPadding = devSettings.useFloatingRouteToggles ? 250.0 : 50.0;

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // 1. Route Header (Fixed at top when floating toggles are disabled)
        if (!devSettings.useFloatingRouteToggles)
          SliverToBoxAdapter(
            child: Column(
              children: [
                RouteDestinationWidget(
                  route: widget.route,
                  direction: _selectedDirection,
                  serviceType: _selectedServiceType,
                  cachedRouteData: _routeDetails,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

        // 2. Main Content States (Loading / Error / Data)
        if (loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              key: const ValueKey('loading'),
              child: CircularProgressIndicator(
                strokeWidth: 3.0,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          )
        else if (error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              key: const ValueKey('error'),
              child: Text(
                'Error: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          )
        else if (data == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              key: ValueKey('no_data'),
              child: Text('No data'),
            ),
          )
        else ...[
          // 3. Selectors (Direction/Service Type)
          // Show selectors if directions exist OR service types exist (CTB may have directions but no service types)
          if ((_directions.isNotEmpty || _serviceTypes.isNotEmpty) && !devSettings.useFloatingRouteToggles)
            SliverToBoxAdapter(child: _buildSelectorsCard()),

          // 4. Combined Data Loading/Error Indicators
          if (_combinedLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: UIConstants.cardPadding,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ),
            ),
          if (_combinedError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: UIConstants.cardPadding,
                child: Text(
                  'Combined error: $_combinedError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),

          // 5. Station List (Sliver Implementation)
          _buildSliverStationList(bottomPadding),
        ],
      ],
    );
  }

  /// Helper to build the correct SliverList based on data source (Variant or Cached)
  Widget _buildSliverStationList(double bottomPadding) {
    // A. Priority: Use Variant Stops (Route-Stop API) if available
    if (_variantStops != null && _selectedDirection != null && _selectedServiceType != null) {
      return _buildSliverVariantList(_variantStops!, bottomPadding);
    }

    // Variant loading state
    if (_variantStopsLoading) {
      return const SliverToBoxAdapter(
        child: Card(
          margin: EdgeInsets.all(12),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: CircularProgressIndicator(year2023: false,)),
          ),
        ),
      );
    }

    // Variant error state
    if (_variantStopsError != null) {
      return SliverToBoxAdapter(
        child: Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'Error loading route stops: $_variantStopsError',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      );
    }

    // B. Fallback: Use Cached Route-To-Stops Map
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([Citybus.buildRouteToStopsMap(), Citybus.buildStopMap()]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Card(
              margin: EdgeInsets.all(12),
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator(year2023: false,)),
              ),
            ),
          );
        }

        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Error loading maps: ${snap.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          );
        }

        // Process cached data - handle null data safely
        if (snap.data == null || snap.data!.length < 2) {
          return const SliverToBoxAdapter(
            child: Card(
              margin: EdgeInsets.all(12),
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text('No data available'),
              ),
            ),
          );
        }
        
        // Safely cast with null checks
        final routeMapData = snap.data![0];
        final stopMapData = snap.data![1];
        
        final routeMap = (routeMapData is Map<String, List<Map<String, dynamic>>>)
            ? routeMapData
            : <String, List<Map<String, dynamic>>>{};
        final stopMap = (stopMapData is Map<String, Map>)
            ? stopMapData.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)))
            : <String, Map<String, dynamic>>{};

        final r = widget.route.trim().toUpperCase();
        final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
        final entries = routeMap[r] ?? routeMap[base] ?? [];

        if (entries.isEmpty) {
          return const SliverToBoxAdapter(
            child: Card(
              margin: EdgeInsets.all(12),
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text('No stop data for route'),
              ),
            ),
          );
        }

        // Filter and Deduplicate Logic
        final lang = context.watch<LanguageProvider>();
        final isEnglish = lang.isEnglish;

        String? normChar(dynamic v) {
          if (v == null) return null;
          final s = v.toString().trim().toUpperCase();
          if (s.isEmpty) return null;
          // Accept values starting with I or O (covers 'I','O','IN','OUT','INBOUND','OUTBOUND')
          final c = s[0];
          if (c == 'I' || c == 'O') return c;
          return null;
        }

        final selectedBoundChar = normChar(_selectedDirection);
        final selectedService = _selectedServiceType;
        final uniqueStopsMap = <String, Map<String, dynamic>>{};

        for (final e in entries) {
          if (!e.containsKey('seq')) continue;
          
          final entryRoute = e['route']?.toString().trim().toUpperCase();
          final currentRoute = widget.route.trim().toUpperCase();
          if (entryRoute != null && entryRoute.isNotEmpty && entryRoute != currentRoute) continue;

          final seq = e['seq']?.toString() ?? '';
          if (seq.isEmpty) continue;

          if (selectedBoundChar != null && normChar(e['bound']) != selectedBoundChar) continue;
          
          if (selectedService != null) {
            final entryServiceType = e['service_type']?.toString() ?? e['servicetype']?.toString() ?? '';
            if (entryServiceType != selectedService) continue;
          }

          // Use composite key: bound + seq to handle same seq in different bounds
          final boundKey = normChar(e['bound'] ?? e['dir'] ?? e['direction']) ?? '';
          final compositeKey = '${boundKey}_$seq';
          if (!uniqueStopsMap.containsKey(compositeKey)) {
            uniqueStopsMap[compositeKey] = e;
          }
        }

        final stops = uniqueStopsMap.values.toList();
        stops.sort((a, b) {
          final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        // ETA Loading State
        if (_routeEtaLoading) {
           return SliverToBoxAdapter(
             child: Card(
               margin: const EdgeInsets.all(12),
               child: Padding(
                 padding: const EdgeInsets.all(24.0),
                 child: Center(
                   child: CircularProgressIndicator(
                     valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                   ),
                 ),
               ),
             ),
           );
        }

        // Auto-scroll logic
        final variantKey = '${r}_${selectedBoundChar}_${selectedService}_cached';
        if (_lastAutoScrollVariantKey != variantKey) {
          _lastAutoScrollVariantKey = variantKey;
          if (_userPosition != null && !_locationLoading && stops.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _getUserLocationAndScrollToNearest(stops);
            });
          }
        }

        return _buildSliverListDelegate(stops, stopMap, bottomPadding);
      },
    );
  }

  /// Reusable SliverList builder for both Variant and Cached data
  Widget _buildSliverVariantList(List<Map<dynamic, dynamic>> stops, double bottomPadding) {
    // Helper to normalize bound
    String? normChar(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim().toUpperCase();
      if (s.isEmpty) return null;
      final c = s[0];
      if (c == 'I' || c == 'O') return c;
      return null;
    }

    // Deduplicate and Sort - use composite key to handle same seq in different bounds
    final uniqueStopsMap = <String, Map<dynamic, dynamic>>{};
    for (final stop in stops) {
      final seq = stop['seq']?.toString() ?? '';
      if (seq.isEmpty) {
        debugPrint('⚠️ Warning: Stop with no seq field found: ${stop['stop']}');
        continue;
      }

      // ✅ CRITICAL: Ensure bound is correctly extracted from stop data
      final boundKey = normChar(stop['bound'] ?? stop['dir'] ?? stop['direction']);
      
      // ✅ 新增：如果沒有 bound，使用 selectedDirection 作為 fallback
      if (boundKey == null || boundKey.isEmpty) {
        if (_selectedDirection != null) {
          final fallbackBound = _selectedDirection!.toUpperCase().startsWith('I') ? 'I' : 'O';
          stop['bound'] = fallbackBound;
          debugPrint('ℹ️ Using selected direction as fallback for stop seq=$seq: $fallbackBound');
        } else {
          debugPrint('⚠️ Warning: Stop seq=$seq has no bound information and no selected direction, skipping');
          continue; // Skip stops with missing bound when we can't determine it
        }
      }

      // Use composite key: bound + seq to handle same seq in different bounds
      final effectiveBound = normChar(stop['bound']) ?? '';
      final compositeKey = '${effectiveBound}_$seq';
      if (!uniqueStopsMap.containsKey(compositeKey)) {
        uniqueStopsMap[compositeKey] = stop;
      }
    }

    final sortedStops = uniqueStopsMap.values.toList();
    // Sort by bound first (I before O), then by seq within each bound
    sortedStops.sort((a, b) {
      // First compare by bound (I comes before O)
      final aBound = (a['bound'] ?? a['dir'] ?? a['direction'])?.toString().trim().toUpperCase() ?? '';
      final bBound = (b['bound'] ?? b['dir'] ?? b['direction'])?.toString().trim().toUpperCase() ?? '';
      final aBoundChar = aBound.isNotEmpty ? aBound[0] : '';
      final bBoundChar = bBound.isNotEmpty ? bBound[0] : '';

      if (aBoundChar != bBoundChar) {
        // I comes before O
        if (aBoundChar == 'I') return -1;
        if (bBoundChar == 'I') return 1;
        // If neither is I, maintain order
        return aBoundChar.compareTo(bBoundChar);
      }

      // Same bound, sort by seq
      final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });

    // Variant Loading Check
    if (_routeEtaLoading) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      );
    }

    // Auto-scroll
    final variantKey = '${widget.route}_${_selectedDirection}_${_selectedServiceType}_variant';
    if (_lastAutoScrollVariantKey != variantKey) {
      _lastAutoScrollVariantKey = variantKey;
      if (_userPosition != null && !_locationLoading && sortedStops.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _getUserLocationAndScrollToNearest(sortedStops);
        });
      }
    }

    // Since variant stops already have metadata enriched, we pass an empty map or rely on internal data
    return _buildSliverListDelegate(sortedStops, {}, bottomPadding); 
  }

  /// Core delegate builder to avoid code duplication
  Widget _buildSliverListDelegate(
    List<Map<dynamic, dynamic>> stops,
    Map<String, Map<String, dynamic>> stopMap, // Optional external map for cached mode
    double bottomPadding,
  ) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final etaByStop = _etaBySeqCache ?? <String, List<Map<String, dynamic>>>{};

    // Helper to normalize bound
    String? normChar(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim().toUpperCase();
      if (s.isEmpty) return null;
      final c = s[0];
      if (c == 'I' || c == 'O') return c;
      return null;
    }

    // 🔍 Debug: 顯示 etaBySeqCache 的所有 keys
    if (etaByStop.isNotEmpty) {
      debugPrint('📊 etaBySeqCache keys: ${etaByStop.keys.toList()}');
    } else {
      debugPrint('⚠️ etaBySeqCache is EMPTY!');
    }

    return SliverPadding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final s = stops[index];
            final seq = s['seq']?.toString() ?? '';
            final stopId = s['stop']?.toString() ?? '';

            if (seq.isEmpty || stopId.isEmpty) {
              return const SizedBox.shrink();
            }

            // Resolve Metadata: Variant data has it inside, Cached data needs lookup
            final meta = stopMap[stopId];
            final nameEn = meta != null ? (meta['name_en'] ?? meta['nameen']) : (s['name_en'] ?? s['nameen']?.toString() ?? '');
            final nameTc = meta != null ? (meta['name_tc'] ?? meta['nametc']) : (s['name_tc'] ?? s['nametc']?.toString() ?? '');
            final displayName = isEnglish
                ? (nameEn.isNotEmpty ? nameEn : (nameTc.isNotEmpty ? nameTc : stopId))
                : (nameTc.isNotEmpty ? nameTc : (nameEn.isNotEmpty ? nameEn : stopId));
            
            final latStr = meta != null ? (meta['lat'] ?? meta['latitude']) : (s['lat'] ?? s['latitude']?.toString());
            final lngStr = meta != null ? (meta['long'] ?? meta['lng']) : (s['long'] ?? s['lng']?.toString());

            // ETAs and Nearby check - use composite key for lookup
            String? getBoundChar(dynamic v) {
              if (v == null) return null;
              final s = v.toString().trim().toUpperCase();
              if (s.isEmpty) return null;
              final c = s[0];
              if (c == 'I' || c == 'O') return c;
              return null;
            }

            final boundKey = getBoundChar(s['bound'] ?? s['dir'] ?? s['direction']);
            
            // ✅ 修正:更強的 fallback 邏輯
            String effectiveBound;
            if (boundKey != null && boundKey.isNotEmpty) {
              effectiveBound = boundKey;
            } else if (_selectedDirection != null && _selectedDirection!.isNotEmpty) {
              // Fallback to selectedDirection
              effectiveBound = _selectedDirection!.toUpperCase().startsWith('I') ? 'I' : 'O';
              debugPrint('⚠️ Stop seq=$seq, stopId=$stopId has no bound, using selectedDirection fallback: $effectiveBound');
            } else {
              // ❌ 最壞情況:沒有 bound 也沒有 selectedDirection
              debugPrint('❌ CRITICAL: Stop seq=$seq, stopId=$stopId has NO bound and NO selectedDirection!');
              debugPrint('   Stop data: ${s.keys.toList()}');
              debugPrint('   s[\'bound\']: ${s['bound']}');
              debugPrint('   s[\'dir\']: ${s['dir']}');
              debugPrint('   s[\'direction\']: ${s['direction']}');
              effectiveBound = ''; // 會導致 compositeKey = '' 然後找不到 ETA
            }

            // CRITICAL: boundKey must match the format used in ETA cache: 'I' or 'O'
            // Composite key format: bound+seq (e.g., "I5", "O10")
            final compositeKey = effectiveBound.isNotEmpty ? '${effectiveBound}_$seq' : '';

            // IMPORTANT: Only use compositeKey for lookup, NO fallback to just `seq`
            // Fallback to seq-only causes cross-bound collisions and incorrect ETA display
            final List<Map<String, dynamic>> etas = compositeKey.isNotEmpty 
                ? (etaByStop[compositeKey] ?? [])
                : [];

            // 🔍 Debug: 當沒有 ETA 時輸出詳細資訊
            if (etas.isEmpty && etaByStop.isNotEmpty) {
              debugPrint('🔍 No ETA for stop:');
              debugPrint('   stopId: $stopId, seq: $seq');
              debugPrint('   boundKey: $boundKey');
              debugPrint('   effectiveBound: $effectiveBound');
              debugPrint('   compositeKey: "$compositeKey"');
              debugPrint('   selectedDirection: $_selectedDirection');
              debugPrint('   etaBySeqCache has keys: ${etaByStop.keys.take(5).toList()}...');
            }

            final isNearby = _userPosition != null && latStr != null && lngStr != null
                ? _isNearbyStop(latStr, lngStr)
                : false;

            return _buildCompactStopCard(
              context: context,
              seq: seq,
              stopId: stopId,
              displayName: displayName,
              nameEn: nameEn,
              nameTc: nameTc,
              etas: etas,
              isEnglish: isEnglish,
              latitude: latStr,
              longitude: lngStr,
              isNearby: isNearby,
            );
          },
          childCount: stops.length,
        ),
      ),
    );
  }

  /*/// Build the list view showing route details and stops
  Widget _buildListView(DeveloperSettingsProvider devSettings) {
    return Column(
      children: [
        //This is to show DEST to the TOP - Fixed Route Destination (like AppBar) - always visible at top
        /*RouteDestinationWidget(
          route: widget.route,
          direction: _selectedDirection,
          serviceType: _selectedServiceType,
          cachedRouteData: _routeDetails,
        ),
        */

        // ✅ 只在 floating bar 關閉時顯示
        if (!devSettings.useFloatingRouteToggles) ...[
          RouteDestinationWidget(
            route: widget.route,
            direction: _selectedDirection,
            serviceType: _selectedServiceType,
            cachedRouteData: _routeDetails,
          ),
          const SizedBox(height: 8),
        ],

        // Show route details card independently (even while loading stops)
        //if (_routeDetails != null && !devSettings.useFloatingRouteToggles)
        //  _buildRouteDetailsCard(),
        //if (_routeDetails != null && devSettings.useFloatingRouteToggles)
        //  _buildRouteDetailsCard(),
        
        // Show stop list or loading state with smooth animations
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              );
            },
            child: loading
                ? Center(
                    key: const ValueKey('loading'),
                    child: CircularProgressIndicator(
                      strokeWidth: 3.0,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : (error != null
                    ? Center(
                        key: const ValueKey('error'),
                        child: Text(
                          'Error: $error',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      )
                    : (data == null
                        ? Center(
                            key: const ValueKey('no_data'),
                            child: Text('No data'),
                          )
                        : Column(
                            key: const ValueKey('content'),
                            children: [
                              if (_combinedLoading)
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: Padding(
                                    key: const ValueKey('combined_loading'),
                                    padding: UIConstants.cardPadding,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Theme.of(context).colorScheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_combinedError != null)
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: Padding(
                                    key: const ValueKey('combined_error'),
                                    padding: UIConstants.cardPadding,
                                    child: Text(
                                      'Combined error: $_combinedError',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(child: _buildStructuredView()),
                            ],
                          ))),
          ),
        ),
      ],
    );
  }*/

  Widget _buildFloatingBottomBar() {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final theme = Theme.of(context);
    final devSettings = context.watch<DeveloperSettingsProvider>();

    // Don't show if setting is disabled
    if (!devSettings.useFloatingRouteToggles) {
      return const SizedBox.shrink();
    }
    
    // Show if directions exist (CTB may have directions but no service types)
    if (_directions.isEmpty && _serviceTypes.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 🆕 根據內容動態計算最大高度
    final availableServiceTypes = _getServiceTypesForDirection(_selectedDirection);
    final hasMultipleDirections = _directions.length > 1;
    final hasMultipleServiceTypes = availableServiceTypes.length > 1;
    final maxSize = (_serviceTypes.isEmpty) ? 0.26 : 0.38;

    return DraggableScrollableSheet(
      controller: _draggableController,
      initialChildSize: 0.25,
      minChildSize: 0.15,
      maxChildSize: maxSize,
      snap: true,
      snapSizes: [0.15, 0.25, maxSize],
      snapAnimationDuration: const Duration(milliseconds: 250),
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: FakeGlass(  // ✅ 使用 FakeGlass 而非 LiquidGlass
          shape: LiquidRoundedSuperellipse(borderRadius: 20),
          settings: LiquidGlassSettings(
            blur: 10.0, 
            thickness: 19,                                             // ✅ 提高模糊
            glassColor: theme.colorScheme.surface.withOpacity(0.15), // ✅ 降至 0.15
            lightIntensity: 1.2,
            saturation: 1.1,
            refractiveIndex: 1.3,
          ),
          child: Container(
            decoration: BoxDecoration(
              // ✅ 移除 color 屬性，避免雙重不透明
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                // Drag handle indicator
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: UIConstants.spacingM,
                      right: UIConstants.spacingM,
                      bottom: UIConstants.spacingL,
                      top: UIConstants.spacingXS
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          // Route destination summary
                          RouteDestinationWidget(
                            route: widget.route,
                            direction: _selectedDirection,
                            serviceType: _selectedServiceType,
                            cachedRouteData: _routeDetails,
                          ),
                          const SizedBox(height: 8),


                          // Direction toggles
                          if (_directions.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 18, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  isEnglish ? 'Direction' : '方向',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: Row(
                                children: _directions.map((d) {
                                  final isSelected = _selectedDirection == d;
                                  final dUpper = d.toUpperCase();
                                  final isOutbound = dUpper.startsWith('O');
                                  final isInbound = dUpper.startsWith('I');
                                  final isSpecial = !isOutbound && !isInbound;

                                  final dirLabel = isSpecial
                                    ? (isEnglish ? 'Direction $d' : '方向 $d')
                                    : isOutbound 
                                        ? (isEnglish ? 'Outbound' : '去程')
                                        : (isEnglish ? 'Inbound' : '回程');
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(right: UIConstants.spacingS),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      child: FilterChip(
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isSpecial
                                                  ? Icons.alt_route
                                                  : (isOutbound ? Icons.arrow_circle_right : Icons.arrow_circle_left),
                                              size: 16,
                                              color: isSelected 
                                                ? theme.colorScheme.onPrimary
                                                : isSpecial
                                                    ? theme.colorScheme.secondary
                                                    : (isOutbound ? theme.colorScheme.primary : theme.colorScheme.tertiary),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(dirLabel),
                                          ],
                                        ),
                                        selected: isSelected,
                                        selectedColor: isSpecial
                                          ? theme.colorScheme.secondary.withOpacity(0.9)
                                          : isOutbound 
                                              ? theme.colorScheme.primary.withOpacity(0.9)
                                              : theme.colorScheme.tertiary.withOpacity(0.9),
                                        backgroundColor: isSpecial
                                          ? theme.colorScheme.secondary.withOpacity(0.1)
                                          : isOutbound
                                              ? theme.colorScheme.primary.withOpacity(0.1)
                                              : theme.colorScheme.tertiary.withOpacity(0.1),
                                        checkmarkColor: theme.colorScheme.onPrimary,
                                        labelStyle: TextStyle(
                                          color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                        elevation: isSelected ? 4 : 0,
                                        pressElevation: 2,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(() => _selectedDirection = d);
                                            _fetchRouteDetails(widget.route, d,);
                                            _fetchRouteEta(widget.route, silent: _hasLoadedEtaOnce);
                                            _restartEtaAutoRefresh();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                          
                          // Service type toggles
                          if (_serviceTypes.isNotEmpty && _serviceTypes.length > 1) ...[
                            if (_directions.isNotEmpty) const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.alt_route, size: 18, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  isEnglish ? 'Service Type' : '班次類型',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: EnhancedScrollPhysics.enhanced(),
                              child: Row(
                                children: (_serviceTypes..sort()).map((st) {
                                  final isSelected = _selectedServiceType == st;
                                  final typeLabel = st == '1'
                                      ? (isEnglish ? 'Normal Service' : '常規班次')
                                      : (isEnglish ? 'Special Service ($st)' : '特別班次 ($st)');
                                  
                                  return Padding(
                                    padding: EdgeInsets.only(right: UIConstants.spacingS, bottom: maxSize),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      child: FilterChip(
                                        label: Text(typeLabel),
                                        selected: isSelected,
                                        selectedColor: theme.colorScheme.primary,
                                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                        checkmarkColor: theme.colorScheme.onPrimary,
                                        labelStyle: TextStyle(
                                          color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                        elevation: isSelected ? 4 : 0,
                                        pressElevation: 2,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(() => _selectedServiceType = st);
                                            _fetchRouteDetails(widget.route, _selectedDirection ?? 'O',);
                                            _fetchRouteEta(widget.route, silent: _hasLoadedEtaOnce);
                                            _restartEtaAutoRefresh();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
            ),
          ),
        ),
      ),
    );
  }

  void _pinRoute() async {
    final lang = context.read<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    // Get route details for the pin
    String routeLabel = widget.route;
    if (_routeDetails != null) {
      final routeData = _routeDetails!.containsKey('data') 
        ? (_routeDetails!['data'] as Map<String, dynamic>?)
        : _routeDetails!;
      
      if (routeData != null) {
        final orig = isEnglish 
          ? (routeData['orig_en'] ?? routeData['orig_tc'] ?? '')
          : (routeData['orig_tc'] ?? routeData['orig_en'] ?? '');
        final dest = isEnglish
          ? (routeData['dest_en'] ?? routeData['dest_tc'] ?? '')
          : (routeData['dest_tc'] ?? routeData['dest_en'] ?? '');
        if (orig.isNotEmpty && dest.isNotEmpty) {
          routeLabel = '${widget.route}: $orig → $dest';
        }
      }
    }
    
    // Save to preferences (you'll need to implement this in kmb.dart)
    await Citybus.pinRoute(
      widget.route, 
      _selectedDirection ?? widget.bound ?? 'O',
      /*_selectedServiceType ?? widget.serviceType ?? '1',
      routeLabel,*/
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lang.routePinned} ${widget.route}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildStructuredView() {
    final payload = data!['data'];
    final devSettings = context.watch<DeveloperSettingsProvider>();

    final List<Widget> sections = [];

    // Hide technical response info - users don't need to see this
    // sections.add(Card(
    //   child: ListTile(
    //     title: Text('Response'),
    //     subtitle: Text('type: $type\nversion: $version\ngenerated: $generated'),
    //   ),
    // ));

    // If payload is a list, inspect the first item to determine its shape
    if (payload is List && payload.isNotEmpty) {
      final first = payload.first as Map<String, dynamic>;

      // Hide route info/list - not user-friendly
      // if (first.containsKey('route') && first.containsKey('co')) {
      //   sections.add(_buildRouteInfoList(payload.cast<Map<String, dynamic>>()));
      // }

      // Route-stop list (contains seq and stop)
      if (first.containsKey('seq') && first.containsKey('stop')) {
        // Hide technical stops list - keep only user-friendly version
        //sections.add(_buildStopsList(payload.cast<Map<String, dynamic>>()));

        sections.add(_buildOptimizedStationList());
      }

      // Hide ETA entries list - shown in optimized station list instead
      // if (first.containsKey('etaseq') || first.containsKey('eta')) {
      //   sections.add(_buildEtaList(payload.cast<Map<String, dynamic>>()));
      // }

      // If none of the above matched, fall back to raw list view
      if (!first.containsKey('route') && !first.containsKey('seq') && !first.containsKey('eta')) {
        // Hide raw JSON for unknown formats
        // sections.add(_buildRawJsonCard());
      }

      // Hide combined data card - information shown in optimized list instead
      // if (_combinedData != null) {
      //   sections.insert(0, _buildCombinedCard(_combinedData!));
      // }
    } else if (payload is Map<String, dynamic>) {
      // Hide key-value card - not user-friendly
      // sections.add(_buildKeyValueCard('Data', payload));
    } else {
      // Hide raw JSON
      // sections.add(_buildRawJsonCard());
    }

    // If we have discovered service types, show selectors
    // Only show old-style selector card if floating toggles are disabled
    // Route details card is now shown independently at the top (outside this view)
    if (_serviceTypes.isNotEmpty && !devSettings.useFloatingRouteToggles) {
      sections.insert(0, _buildSelectorsCard());
    }

    // Hide raw JSON at the end - users don't need debug info
    // sections.add(_buildRawJsonCard());

    

    return SingleChildScrollView(
      //controller: _scrollController, // <--- Attach the controller here!
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      ),
    );
  }

  Widget _buildSelectorsCard() {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: UIConstants.spacingM, vertical: UIConstants.spacingS),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_directions.length > 1) ...[
              Row(
                children: [
                  Icon(Icons.alt_route, size: 18, color: Theme.of(context).iconTheme.color ?? Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    isEnglish ? 'Direction' : '方向',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _directions.map((d) {
                  final isSelected = _selectedDirection == d;
                  final isOutbound = d.toUpperCase().startsWith('O');
                  final label = isEnglish 
                    ? (isOutbound ? 'Outbound' : 'Inbound')
                    : (isOutbound ? '去程' : '回程');
                  
                  return FilterChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedDirection = d;
                          _fetchRouteDetails(widget.route.trim().toUpperCase(), d,);
                          // Fetch ETA for the selected direction
                          _fetchRouteEta(widget.route.trim().toUpperCase(), silent: _hasLoadedEtaOnce);
                        });
                        _restartEtaAutoRefresh();
                      }
                    },
                    selectedColor: isOutbound 
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.2) 
                      : Theme.of(context).colorScheme.tertiary.withOpacity(0.2),
                    checkmarkColor: isOutbound ? Theme.of(context).colorScheme.primary.withOpacity(0.85) : Theme.of(context).colorScheme.tertiary.withOpacity(0.85),
                    avatar: isSelected 
                      ? Icon(
                          isOutbound ? Icons.arrow_circle_right : Icons.arrow_circle_left,
                          size: 18,
                          color: isOutbound ? Theme.of(context).colorScheme.primary.withOpacity(0.85) : Theme.of(context).colorScheme.tertiary.withOpacity(0.85),
                        )
                      : null,
                  );
                }).toList(),
              ),
            ],
            if (_serviceTypes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.route, size: 18, color: Theme.of(context).iconTheme.color ?? Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    isEnglish ? 'Service Type' : '服務類型',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _serviceTypes.map((s) {
                  final isSelected = _selectedServiceType == s;
                  return FilterChip(
                    label: Text(isEnglish ? 'Type $s' : '類型 $s'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedServiceType = s;
                          _fetchRouteEta(widget.route.trim().toUpperCase(), silent: _hasLoadedEtaOnce);
                          if (_selectedDirection != null) {
                            _fetchRouteDetails(widget.route.trim().toUpperCase(), _selectedDirection!,);
                          }
                        });
                        _restartEtaAutoRefresh();
                      }
                    },
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    checkmarkColor: Theme.of(context).colorScheme.primary,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }



  Future<void> _fetchCombined() async {
    setState(() {
      _combinedLoading = true;
      _combinedError = null;
      _combinedData = null;
    });
    try {
      final combined = await Citybus.fetchCombinedRouteStatus(widget.route);
      setState(() { _combinedData = combined; });
    } catch (e) {
      setState(() { _combinedError = e.toString(); });
    } finally {
      setState(() { _combinedLoading = false; });
    }
  }

  Widget _buildCombinedCard(Map<String, dynamic> combined) {
    final meta = combined['data'] ?? {};
  final List stops = meta['stops'] ?? [];

  if (stops.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(UIConstants.spacingM), child: Text('No combined stops')));

    final combinedRouteEta = meta['routeEta'] ?? [];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(title: Text('Combined status for ${combined['route']} · svc: ${combined['serviceType'] ?? 'n/a'} · ETAs: ${combinedRouteEta.length}')),
      ...stops.map((s) {
      final stopId = s['stop'] ?? '';
      final stopInfo = s['stopInfo'] as Map<String, dynamic>?;
      final List<Map<String, dynamic>> etas = (s['etas'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ?? <Map<String, dynamic>>[];
            final stopName = stopInfo != null ? (stopInfo['nameen'] ?? stopInfo['nametc'] ?? stopId) : stopId;
            return ListTile(
              title: Text('$stopId · $stopName'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (etas.isEmpty) const Text('No ETAs'),
                  for (final e in etas)
                    Text('${e['etaseq'] ?? ''} · ${_formatEtaWithRelative(context, e['eta'] ?? e['eta_time'])} · ${e['desten'] ?? e['desttc'] ?? ''}'),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Load available directions from cached data (CTB doesn't use service types)
  void _loadVariantsFromCache(String r, String? initialDirection) async {
    try {
      // Ensure route-stops map is built first
      await Citybus.buildRouteToStopsMap();
      
      // Discover available directions for this route
      final variants = await Citybus.discoverRouteVariants(r);
      
      setState(() {
        // Extract and normalize directions (CTB uses 'I'/'O')
        _directions = (variants['directions'] as List<dynamic>?)?.cast<String>() ?? [];
        _serviceTypes = []; // CTB doesn't use service types
        
        // Auto-select direction with priority: initialDirection > 'O' > first available
        _selectedDirection = initialDirection != null && _directions.contains(initialDirection)
            ? initialDirection
            : _directions.isNotEmpty
                ? (_directions.contains('O') ? 'O' : _directions.first)
                : null;
        
        _selectedServiceType = null; // CTB doesn't have service types
        
        debugPrint('CTB Variants - Route: $r, Directions: $_directions, Selected: $_selectedDirection');
      });
      
      // Fetch route details and ETA if direction is selected
      if (_selectedDirection != null) {
        _fetchRouteDetails(r.trim().toUpperCase(), _selectedDirection!);
        _fetchRouteEta(r.trim().toUpperCase(), silent: _hasLoadedEtaOnce);
        _restartEtaAutoRefresh();
      }
    } catch (e) {
      debugPrint('Error loading CTB variants: $e');
      
      // Use empty variants if discovery fails
      if (mounted) {
        setState(() {
          _directions = [];
          _serviceTypes = [];
        });
      }
    }
  }

  /// Fetch route-level ETA for all stops on this route
  /// CTB doesn't use service_type - it's always empty/null
  /// Fetch route-level ETA for all stops on this route
  /// CTB doesn't use service_type - it's always empty/null
  bool _isFetchingEta = false;
  Future<void> _fetchRouteEta(String route, {bool silent = false}) async {
    // 🛡️ Guard: Prevent overlapping requests
    if (_isFetchingEta) return;
    _isFetchingEta = true;
    
    // Capture the direction requested to detect race conditions later
    final requestedDirection = _selectedDirection;

    // CRITICAL: Set loading ONLY if not silent
    if (!silent && mounted) {
      setState(() {
        _routeEtaLoading = true;
        _routeEtaError = null;
      });
    }

    try {
      final r = route.trim().toUpperCase();
      if (r.isEmpty) throw ArgumentError('route is empty');

      // Fetch route-level ETA (uses batching internally now)
      final selectedDirectionForEta = requestedDirection != null
          ? (requestedDirection.toUpperCase().startsWith('I') ? 'I' : 'O')
          : null;
          
      final entries = await Citybus.fetchRouteEta(r, direction: selectedDirectionForEta);

      if (!mounted) return;
      
      // 🛡️ Race Condition Check: If direction changed while fetching, discard results
      if (_selectedDirection != requestedDirection) {
        debugPrint('⚠️ Discarding ETA results for $requestedDirection as user switched to $_selectedDirection');
        return;
      }

      final selectedBoundChar = _selectedDirection != null
          ? (_selectedDirection!.toUpperCase().startsWith('I') ? 'I' : 'O')
          : null;

      // Build O(1) lookup cache: bound_seq -> [ETAs]
      final Map<String, List<Map<String, dynamic>>> etaBySeq = {};

      String? normChar(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim().toUpperCase();
        if (s.isEmpty) return null;
        final c = s[0];
        if (c == 'I' || c == 'O') return c;
        return null;
      }

      // Pre-process stops for quick fallback lookup
      final routeMap = await Citybus.buildRouteToStopsMap();
      final routeStops = routeMap[r] ?? [];
      final stopIdToBound = <String, String>{};
      final stopIdToSeq = <String, String>{};

      for (final stop in routeStops) {
        final stopId = (stop['stop'] ?? '').toString();
        if (stopId.isNotEmpty) {
          final bound = stop['bound'] ?? stop['dir'] ?? stop['direction'];
          if (bound != null) {
            final boundStr = bound.toString().trim().toUpperCase();
            if (boundStr.isNotEmpty) stopIdToBound[stopId] = boundStr[0];
          }
          final seq = (stop['seq'] ?? '').toString();
          if (seq.isNotEmpty) stopIdToSeq[stopId] = seq;
        }
      }

      for (final eta in entries) {
        final stopId = (eta['stop'] ?? '')?.toString() ?? '';
        String seq = (eta['seq'] ?? eta['stop_seq'])?.toString() ?? '';

        // Fallback: lookup seq if missing
        if (seq.isEmpty && stopId.isNotEmpty) seq = stopIdToSeq[stopId] ?? '';
        if (seq.isEmpty) continue;

        // Fallback: lookup bound if missing
        String? etaBoundChar = normChar(eta['bound'] ?? eta['dir'] ?? eta['direction']);
        if (etaBoundChar == null && stopId.isNotEmpty) {
          etaBoundChar = stopIdToBound[stopId];
          if (etaBoundChar != null) eta['bound'] = etaBoundChar;
        }

        // Final Fallback: use selected direction
        if (etaBoundChar == null && selectedBoundChar != null) {
          etaBoundChar = selectedBoundChar;
          eta['bound'] = selectedBoundChar;
        }

        // Filter by selected bound
        if (selectedBoundChar != null && etaBoundChar != selectedBoundChar) continue;

        if (etaBoundChar == null || etaBoundChar.isEmpty) continue;

        // Ensure seq matches for display
        if (!eta.containsKey('seq')) eta['seq'] = seq;

        // Store in cache with composite key
        final compositeKey = '${etaBoundChar}_$seq';
        etaBySeq.putIfAbsent(compositeKey, () => []).add(eta);
      }

      // Sort ETAs by eta_seq
      for (final list in etaBySeq.values) {
        list.sort((a, b) {
          final ai = int.tryParse((a['eta_seq'] ?? a['etaseq'])?.toString() ?? '') ?? 0;
          final bi = int.tryParse((b['eta_seq'] ?? b['etaseq'])?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });
      }

      if (mounted) {
        setState(() {
          _routeEtaEntries = entries;
          _etaBySeqCache = etaBySeq;
          _hasLoadedEtaOnce = true;
          _routeEtaError = null;
          _etaConsecutiveErrors = 0;
        });
      }
    } catch (e) {
      _etaConsecutiveErrors += 1;
      if (!silent && mounted) {
        setState(() => _routeEtaError = e.toString());
      }
    } finally {
      _isFetchingEta = false; // Release guard
      if (mounted) {
        setState(() => _routeEtaLoading = false);
      }
      _maybeAdjustEtaTimer();
    }
  }

  // 🆕 根據選中方向獲取可用的 service types
  List<String> _getServiceTypesForDirection(String? direction) {
    if (direction == null || data == null) return _serviceTypes;
    
    try {
      final payload = data!['data'];
      if (payload is! List || payload.isEmpty) return _serviceTypes;
      
      final entries = payload.cast<Map<String, dynamic>>();
      final dirChar = direction.trim().toUpperCase()[0];
      
      // 過濾出該方向的所有 service types
      final availableTypes = entries
          .where((e) {
            final bound = e['bound']?.toString().trim().toUpperCase() ?? '';
            return bound.isNotEmpty && bound[0] == dirChar;
          })
          .map((e) => e['service_type']?.toString() ?? '1')
          .toSet()
          .toList();
      
      availableTypes.sort();
      return availableTypes.isNotEmpty ? availableTypes : _serviceTypes;
    } catch (_) {
      return _serviceTypes;
    }
  }

  Future<void> _fetchRouteDetails(String route, String direction) async {
    if (!mounted) return;
    
    setState(() {
      _routeDetailsLoading = true;
      _routeDetailsError = null;
      _routeDetails = null;
    });

    try {
      final details = await Citybus.fetchRouteWithParams(route, direction);
      
      if (!mounted) return;
      
      setState(() {
        _routeDetails = details;
      });

      // Also fetch route-stops for this specific variant
      _fetchRouteStopsForVariant(route, direction);
    } catch (e) {
      if (mounted) {
        setState(() {
          _routeDetailsError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _routeDetailsLoading = false;
        });
      }
    }
  }


  // ===== ETA Auto-Refresh (modeled after LRT startAutoRefresh) =====
  void _maybeStartEtaAutoRefresh() {
    if (!_enablePageLevelEtaAutoRefresh) return;
    if (_etaRefreshTimer != null && _etaRefreshTimer!.isActive) return;
    // CTB: Don't require service type check
    if (_selectedDirection == null) return;

    final r = widget.route.trim().toUpperCase();

    _etaRefreshTimer = Timer.periodic(_etaRefreshInterval, (_) {
      if (mounted) {
        _fetchRouteEta(r, silent: true);
      }
    });

    // Trigger an immediate refresh (silent if already loaded)
    _fetchRouteEta(r, silent: _hasLoadedEtaOnce);
  }

  void _stopEtaAutoRefresh() {
    _etaRefreshTimer?.cancel();
    _etaRefreshTimer = null;
  }

  void _restartEtaAutoRefresh({Duration? interval}) {
    if (!_enablePageLevelEtaAutoRefresh) {
      _stopEtaAutoRefresh();
      return;
    }
    if (interval != null) {
      _etaRefreshInterval = interval;
    }
    _stopEtaAutoRefresh();
    _maybeStartEtaAutoRefresh();
  }

  void _maybeAdjustEtaTimer() {
    // Simple backoff: after 2+ consecutive errors, double interval up to 60s
    final base = const Duration(seconds: 15);
    final max = const Duration(seconds: 60);
    if (_etaConsecutiveErrors >= 2) {
      final doubled = Duration(seconds: (_etaRefreshInterval.inSeconds * 2).clamp(base.inSeconds, max.inSeconds));
      if (doubled != _etaRefreshInterval) {
        _restartEtaAutoRefresh(interval: doubled);
      }
    } else if (_etaConsecutiveErrors == 0 && _etaRefreshInterval != base) {
      // Recover back to base when errors cleared
      _restartEtaAutoRefresh(interval: base);
    }
  }

  // State for variant-specific route stops
  List<Map<dynamic, dynamic>>? _variantStops;
  bool _variantStopsLoading = false;
  String? _variantStopsError;

  /// Fetch route-stops for a specific route/direction/service_type combination using the Route-Stop API
  Future<void> _fetchRouteStopsForVariant(String route, String direction) async {
    setState(() {
      _variantStopsLoading = true;
      _variantStopsError = null;
      _variantStops = null;
    });
    
    try {
      final directionFull = direction.toUpperCase().startsWith('O') ? 'outbound' : 'inbound';
      final stops = await Citybus.fetchRouteStops(route, directionFull, /*serviceType*/);

      // Enrich with stop metadata
      final stopMap = await Citybus.buildStopMap();
      final enriched = stops.map((stopEntry) {
        final stopId = stopEntry['stop'] as String?;
        final stopInfo = stopId != null ? stopMap[stopId] : null;
        
        return {
          ...stopEntry,
          if (stopInfo != null) ...{
            'name_en': stopInfo['name_en'],
            'name_tc': stopInfo['name_tc'],
            'name_sc': stopInfo['name_sc'],
            'lat': stopInfo['lat'],
            'long': stopInfo['long'],
          }
        };
      }).toList();
      
      setState(() { _variantStops = enriched; });
    } catch (e) {
      setState(() { _variantStopsError = e.toString(); });
    } finally {
      setState(() { _variantStopsLoading = false; });
    }
  }

  Widget _buildRouteInfoList(List<Map<String, dynamic>> list) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('Route info (${list.length})'),
        children: list.map((item) {
          final route = item['route'] ?? '';
          final co = item['co'] ?? '';
          final bound = item['bound'] ?? '';
          final service = item['servicetype'] ?? '';
          final origin = item['orig_en'] ?? item['origen'] ?? item['origtc'] ?? '';
          final dest = item['dest_en'] ?? item['desten'] ?? item['desttc'] ?? '';
          return ListTile(
            title: Text('$route ($co)'),
            subtitle: Text('bound: $bound · service: $service\n$origin → $dest'),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStopsList(List<Map<String, dynamic>> list) {
    // Sort by seq
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('Stops (${sorted.length})'),
        children: sorted.map((stop) {
          final seq = stop['seq']?.toString() ?? '';
          final stopId = stop['stop'] ?? '';
          final nameen = stop['nameen'] ?? stop['nametc'] ?? '';
          final lat = stop['lat'] ?? '';
          final lng = stop['long'] ?? stop['lng'] ?? '';
          return ExpansionTile(
            title: Text('$seq · $stopId'),
            subtitle: Text('$nameen\nlat: $lat, long: $lng'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingM),
                child: StopEtaTile(stopId: stopId),
              )
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEtaList(List<Map<String, dynamic>> list) {
    // Group by stop id
    final Map<String, List<Map<String, dynamic>>> byStop = {};
    for (final item in list) {
      final stop = item['stop']?.toString() ?? 'unknown';
      byStop.putIfAbsent(stop, () => []).add(item);
    }

    final tiles = byStop.entries.map((e) {
      final stopId = e.key;
      final entries = e.value;
      entries.sort((a, b) {
        final ai = int.tryParse((a['etaseq'] ?? a['eta_seq'])?.toString() ?? '') ?? 0;
        final bi = int.tryParse((b['etaseq'] ?? b['eta_seq'])?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });

      return ExpansionTile(
        title: Text('Stop $stopId (${entries.length})'),
        children: entries.map((entry) {
          final etaseq = entry['etaseq']?.toString() ?? '';
          final eta = _formatEtaWithRelative(context, entry['eta'] ?? entry['eta_time']);
          final dest = entry['desten'] ?? entry['desttc'] ?? '';
          final remark = entry['rmken'] ?? entry['rmktc'] ?? '';
          final etatime = entry['eta_time'] != null ? 'time: ${entry['eta_time']}' : '';
          return ListTile(
            title: Text('ETA #$etaseq · $dest'),
            subtitle: Text('eta: $eta\n$remark\n$etatime'),
          );
        }).toList(),
      );
    }).toList();

    return Card(
      child: Column(children: tiles),
    );
  }

  Widget _buildKeyValueCard(String title, Map<String, dynamic> map) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(title),
        children: map.entries.map((e) {
          final label = citybus.lookup(e.key) ?? e.key;
          return ListTile(
            title: Text(label),
            subtitle: Text(e.value.toString()),
          );
        }).toList(),
      ),
    );
  }

  /// Get user location and find nearest stop index
  Future<void> _getUserLocationAndScrollToNearest(List<Map<dynamic, dynamic>> stops) async {
    if (_locationLoading || _userPosition != null) return; // Already loading or loaded
    
    setState(() => _locationLoading = true);
    
    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() => _locationLoading = false);
        return;
      }
      
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      setState(() => _userPosition = pos);
      
      // Find nearest stop
      double minDistance = double.infinity;
      int nearestIndex = -1;
      
      for (int i = 0; i < stops.length; i++) {
        final s = stops[i];
        final latRaw = s['lat'] ?? s['latitude'];
        final lngRaw = s['long'] ?? s['lng'] ?? s['longitude'];
        
        if (latRaw == null || lngRaw == null) continue;
        
        final lat = double.tryParse(latRaw.toString());
        final lng = double.tryParse(lngRaw.toString());
        
        if (lat == null || lng == null) continue;
        
        final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }
      
      // Scroll to nearest stop with context-aware ensureVisible (works for ListView or SingleChildScrollView)
      if (nearestIndex >= 0) {
        //await Future.delayed(Duration(milliseconds: 50)); // Wait for list to build
        try {
          final seqStr = stops[nearestIndex]['seq']?.toString() ?? '';
          final key = _stopKeys[seqStr];
          final ctx = key?.currentContext;
          if (ctx != null) {
            await Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              alignment: 0.2,
            );
          } else if (_scrollController.hasClients) {
            // Fallback to index-based approximation
            final position = nearestIndex * 120.0;
            _scrollController.animateTo(
              position,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            );
          }
        } catch (_) {}
      }
    } catch (e) {
      // Silently fail - location is optional
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  /// Build station list for a specific route variant using Route-Stop API data
  Widget _buildVariantStationList(List<Map<dynamic, dynamic>> stops) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    // Helper to normalize bound
    String? normChar(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim().toUpperCase();
      if (s.isEmpty) return null;
      final c = s[0];
      if (c == 'I' || c == 'O') return c;
      return null;
    }
    
    // 🔴 去重 - 按 bound + seq 去除重複項目（處理同一 seq 在不同 bound 的情況）
    
    final uniqueStopsMap = <String, Map<dynamic, dynamic>>{};
    for (final stop in stops) {
      final seq = stop['seq']?.toString() ?? '';
      if (seq.isEmpty) {
        debugPrint('⚠️  Warning: Variant stop with no seq field found: ${stop['stop']}');
        continue;
      }
      // ✅ CRITICAL: Ensure bound is correctly extracted from stop data
      final boundKey = normChar(stop['bound'] ?? stop['dir'] ?? stop['direction']);
      if (boundKey == null || boundKey.isEmpty) {
        debugPrint('⚠️  Warning: Variant stop seq=$seq has no bound information: ${stop['stop']}');
        continue; // Skip stops with missing bound to maintain consistency
      }
      // Use composite key: bound + seq to handle same seq in different bounds
      final compositeKey = '${boundKey}_$seq';
      if (!uniqueStopsMap.containsKey(compositeKey)) {
        uniqueStopsMap[compositeKey] = stop;
      }
    }
    
    // Sort by sequence
    final sortedStops = uniqueStopsMap.values.toList();
    // Sort by bound first (I before O), then by seq within each bound
    sortedStops.sort((a, b) {
      // First compare by bound (I comes before O)
      final aBound = (a['bound'] ?? a['dir'] ?? a['direction'])?.toString().trim().toUpperCase() ?? '';
      final bBound = (b['bound'] ?? b['dir'] ?? b['direction'])?.toString().trim().toUpperCase() ?? '';
      final aBoundChar = aBound.isNotEmpty ? aBound[0] : '';
      final bBoundChar = bBound.isNotEmpty ? bBound[0] : '';
      
      if (aBoundChar != bBoundChar) {
        // I comes before O
        if (aBoundChar == 'I') return -1;
        if (bBoundChar == 'I') return 1;
        // If neither is I, maintain order
        return aBoundChar.compareTo(bBoundChar);
      }
      
      // Same bound, sort by seq
      final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });

    // 🔴 調試信息
    print('🚌 Variant stops count: ${stops.length} -> unique: ${sortedStops.length}');

    // Use cached ETA HashMap for O(1) lookup
    final etaByStop = _etaBySeqCache ?? <String, List<Map<String, dynamic>>>{};
    
    // 🔴 簡化 loading 狀態 - 移除 AnimatedSwitcher
    if (_routeEtaLoading) {
      return Center(
        key: const ValueKey('variant_loading'),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CircularProgressIndicator(
            strokeWidth: 3.0,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    // Auto-scroll logic
    final variantKey = '${widget.route}_${_selectedDirection}_${_selectedServiceType}_variant';
    if (_lastAutoScrollVariantKey != variantKey) {
      _lastAutoScrollVariantKey = variantKey;
      if (_userPosition != null && !_locationLoading && sortedStops.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _getUserLocationAndScrollToNearest(sortedStops);
        });
      }
    }
    
    return ListView.builder(  // 🔴 直接返回 ListView，不需要 Column + Expanded
      key: ValueKey('kmb_${widget.route}_${_selectedDirection}_$_selectedServiceType'),
      controller: _scrollController,
      padding: EdgeInsets.only(
        bottom: context.watch<DeveloperSettingsProvider>().useFloatingRouteToggles ? 96.0 : 12.0,
      ),
      itemCount: sortedStops.length,
      itemBuilder: (context, index) {
        final s = sortedStops[index];
        final seq = s['seq']?.toString() ?? '';
        final stopId = s['stop']?.toString() ?? '';
        
        final nameEn = (s['name_en'] ?? s['nameen'] ?? '')?.toString() ?? '';
        final nameTc = (s['name_tc'] ?? s['nametc'] ?? '')?.toString() ?? '';
        final displayName = isEnglish
            ? (nameEn.isNotEmpty ? nameEn : (nameTc.isNotEmpty ? nameTc : stopId))
            : (nameTc.isNotEmpty ? nameTc : (nameEn.isNotEmpty ? nameEn : stopId));
        
        final lat = (s['lat'] ?? s['latitude'])?.toString();
        final lng = (s['long'] ?? s['lng'] ?? s['longitude'])?.toString();
        
        final List<Map<String, dynamic>> etas = etaByStop[seq] ?? [];
        
        final isNearby = _userPosition != null && lat != null && lng != null
          ? _isNearbyStop(lat, lng)
          : false;

        return _buildCompactStopCard(
          context: context,
          seq: seq,
          stopId: stopId,
          displayName: displayName,
          nameEn: nameEn,
          nameTc: nameTc,
          etas: etas,
          isEnglish: isEnglish,
          latitude: lat,
          longitude: lng,
          isNearby: isNearby,
        );
      },
    );
  }

  
  bool _isNearbyStop(String? latStr, String? lngStr) {
    if (_userPosition == null || latStr == null || lngStr == null) return false;
    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    if (lat == null || lng == null) return false;
    final distance = Geolocator.distanceBetween(_userPosition!.latitude, _userPosition!.longitude, lat, lng);
    return distance <= 150.0; // Changed from 200.0 to 150.0
  }


  Widget _buildOptimizedStationList() {
    // If we have variant-specific stops (from Route-Stop API), use those instead of cached data
    if (_variantStops != null && _selectedDirection != null && _selectedServiceType != null) {
      return _buildVariantStationList(_variantStops!);
    }
        
  
    if (_variantStopsLoading) {
      return const Card(child: Padding(padding: EdgeInsets.all(12.0), child: Center(child: CircularProgressIndicator(year2023: false,))));
    }
    
    if (_variantStopsError != null) {
      return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('Error loading route stops: $_variantStopsError', style: TextStyle(color: Theme.of(context).colorScheme.error))));
    }
    
    // Fallback to cached route-stop data (from Route-Stop List API)
    // Use the cached/compute helpers in Citybus to get both route->stops and stop metadata maps.
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([Citybus.buildRouteToStopsMap(), Citybus.buildStopMap()]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Card(child: Padding(padding: EdgeInsets.all(12.0), child: Center(child: CircularProgressIndicator(year2023: false,))));
        if (snap.hasError) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('Error loading maps: ${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.error))));

        // Process cached data - handle null data safely
        if (snap.data == null || snap.data!.length < 2) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('No data available'),
            ),
          );
        }
        
        // Safely cast with null checks
        final routeMapData = snap.data![0];
        final stopMapData = snap.data![1];
        
        final routeMap = (routeMapData is Map<String, List<Map<String, dynamic>>>)
            ? routeMapData
            : <String, List<Map<String, dynamic>>>{};
        final stopMap = (stopMapData is Map<String, Map>)
            ? stopMapData.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)))
            : <String, Map<String, dynamic>>{};

        final r = widget.route.trim().toUpperCase();
        final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
        final entries = routeMap[r] ?? routeMap[base] ?? [];
        if (entries.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('No stop data for route'),
            ),
          );
        }

        // Language preference
        final lang = context.watch<LanguageProvider>();
        final isEnglish = lang.isEnglish;

        // Helper: normalize direction/bound values to a single char 'I' or 'O'
        String? normChar(dynamic v) {
          if (v == null) return null;
          final s = v.toString().trim().toUpperCase();
          if (s.isEmpty) return null;
          // Accept values starting with I or O (covers 'I','O','IN','OUT','INBOUND','OUTBOUND')
          final c = s[0];
          if (c == 'I' || c == 'O') return c;
          return null;
        }

        // Determine selected bound char from state (if any). If null, keep both directions.
        final selectedBoundChar = normChar(_selectedDirection);
        final selectedService = _selectedServiceType;

        // Filter by bound O/I AND service_type (keep all if not selected), then sort by seq
        // Filter and deduplicate stops
        final uniqueStopsMap = <String, Map<String, dynamic>>{};
        for (final e in entries) {
          if (!e.containsKey('seq')) continue;

          // [Fix 1] 加入嚴格過濾：檢查站點資料中的 route 是否與當前 route 匹配
          // 許多 KMB API 資料會包含 'route': '44' 這樣的欄位
          // 如果資料是混雜的，這個檢查能過濾掉不屬於本線的站點
          final entryRoute = e['route']?.toString().trim().toUpperCase();
          final currentRoute = widget.route.trim().toUpperCase();
          // 如果 entry 裡有 route 欄位且不等於當前路線，則跳過 (防鬼站)
          if (entryRoute != null && entryRoute.isNotEmpty && entryRoute != currentRoute) {
            continue;
          }
          
          final seq = e['seq']?.toString() ?? '';
          if (seq.isEmpty) continue;
          
          // Filter by bound/direction if selected
          // Check both 'bound' and 'dir' fields, normalize to 'I' or 'O'
          if (selectedBoundChar != null) {
            final boundValue = e['bound'] ?? e['dir'] ?? e['direction'];
            final entryBoundChar = normChar(boundValue);
            if (entryBoundChar != selectedBoundChar) continue;
          }
          // Filter by service_type if selected
          if (selectedService != null) {
            final entryServiceType = e['service_type']?.toString() ?? e['servicetype']?.toString() ?? '';
            if (entryServiceType != selectedService) continue;
          }
          
          // Only add if not already in map (deduplicate by seq)
          if (!uniqueStopsMap.containsKey(seq)) {
            uniqueStopsMap[seq] = e;
          }
        }

        final stops = uniqueStopsMap.values.toList();
        stops.sort((a, b) {
          final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });


        // Use cached ETA HashMap for O(1) lookup instead of FutureBuilder
        // Cache is already filtered by direction and sorted in _fetchRouteEta
        final etaByStop = _etaBySeqCache ?? <String, List<Map<String, dynamic>>>{};
        
        // Loading state with smooth animation
        if (_routeEtaLoading) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              );
            },
            child: Card(
              key: const ValueKey('optimized_loading'),
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3.0,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // Build optimized stop cards using cached data - no redundant API calls!
        // Auto-scroll to nearest stop when data first loads
        // Build optimized stop cards using cached data - no redundant API calls!
        // Auto-scroll to nearest stop when data first loads - check BEFORE registering callback
        final variantKey = '${r}_${selectedBoundChar}_${selectedService}_cached';
        if (_lastAutoScrollVariantKey != variantKey) {
          _lastAutoScrollVariantKey = variantKey;
          if (_userPosition != null && !_locationLoading && stops.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _getUserLocationAndScrollToNearest(stops);
            });
          }
        }
        
        return Column(
          children: [
            // Use shrinkWrap instead of Expanded since we're inside a SingleChildScrollView
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: ListView.builder(
                key: PageStorageKey<String>('kmb_list_${r}_${selectedBoundChar}_${selectedService}_cached'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: context.watch<DeveloperSettingsProvider>().useFloatingRouteToggles ? 200.0 : 12.0,
              ),
              itemCount: stops.length,
              itemBuilder: (context, index) {
                  final s = stops[index];
                  final seq = s['seq']?.toString() ?? '';
                  final stopId = s['stop']?.toString() ?? '';

                  // Get stop metadata
                  final meta = stopMap[stopId];
                  final nameEn = meta != null 
                      ? ((meta['name_en'] ?? meta['nameen'] ?? meta['name_en'] ?? '')?.toString() ?? '') 
                      : '';
                  final nameTc = meta != null 
                      ? ((meta['name_tc'] ?? meta['nametc'] ?? meta['name_tc'] ?? '')?.toString() ?? '') 
                      : '';
                  final displayName = isEnglish
                      ? (nameEn.isNotEmpty ? nameEn : (nameTc.isNotEmpty ? nameTc : stopId))
                      : (nameTc.isNotEmpty ? nameTc : (nameEn.isNotEmpty ? nameEn : stopId));

                  // Get coordinates from metadata
                  final lat = meta != null ? (meta['lat'] ?? meta['latitude'])?.toString() : null;
                  final lng = meta != null ? (meta['long'] ?? meta['lng'] ?? meta['longitude'])?.toString() : null;

                  // O(1) HashMap lookup - instant access to ETAs using composite key!
                  // Use composite key: bound_seq for lookup
                  String? getBoundChar(dynamic v) {
                    if (v == null) return null;
                    final s = v.toString().trim().toUpperCase();
                    if (s.isEmpty) return null;
                    final c = s[0];
                    if (c == 'I' || c == 'O') return c;
                    return null;
                  }
                  final boundKey = getBoundChar(s['bound'] ?? s['dir'] ?? s['direction']) ?? '';
                  final compositeKey = boundKey.isNotEmpty ? '${boundKey}_$seq' : '';
                  final List<Map<String, dynamic>> etas = compositeKey.isNotEmpty 
                    ? (etaByStop[compositeKey] ?? [])
                    : [];
                  
                  // Highlight nearby stops
                  final isNearby = _userPosition != null && lat != null && lng != null
                    ? _isNearbyStop(lat, lng)
                    : false;

                  // ✅ 添加 nameEn 和 nameTc 參數，並加入空值檢查
                  if (seq.isEmpty || stopId.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _buildCompactStopCard(
                    context: context,
                    seq: seq,
                    stopId: stopId,
                    displayName: displayName,
                    nameEn: nameEn,  // ✅ 添加
                    nameTc: nameTc,  // ✅ 添加
                    etas: etas,
                    isEnglish: isEnglish,
                    latitude: lat,
                    longitude: lng,
                    isNearby: isNearby,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRawJsonCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('Raw JSON'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SelectableText(const JsonEncoder.withIndent('  ').convert(data)),
          )
        ],
      ),
    );
  }

  /// Build compact route header showing origin → destination
  Widget _buildCompactRouteHeader() {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    final routeData = _routeDetails!.containsKey('data') 
      ? (_routeDetails!['data'] as Map<String, dynamic>?)
      : _routeDetails!;
    
    if (routeData == null) return const SizedBox.shrink();

    final orig = isEnglish 
      ? (routeData['orig_en'] ?? routeData['orig_tc'] ?? '')
      : (routeData['orig_tc'] ?? routeData['orig_en'] ?? '');
    final dest = isEnglish
      ? (routeData['dest_en'] ?? routeData['dest_tc'] ?? '')
      : (routeData['dest_tc'] ?? routeData['dest_en'] ?? '');
    
    final bound = routeData['bound'] as String?;
    final serviceType = routeData['service_type'] as String?;
    
    // Direction icon
    IconData dirIcon = Icons.arrow_forward;
    final cs = Theme.of(context).colorScheme;
    Color dirColor = cs.secondary;
    if (bound == 'O') {
      dirIcon = Icons.arrow_circle_right;
      dirColor = cs.primary;
    } else if (bound == 'I') {
      dirIcon = Icons.arrow_circle_left;
      dirColor = cs.tertiary;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 3,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(dirIcon, color: dirColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$orig → $dest',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (serviceType != null && serviceType != '1')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${lang.type} $serviceType',
                  style: TextStyle(fontSize: 11, color: cs.secondary.withOpacity(0.85)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build compact stop card without destination (shown in header)
  Widget _buildCompactStopCard({
    required BuildContext context,
    required String seq,
    required String stopId,
    required String displayName,
    String? nameEn,
    String? nameTc,
    required List<Map<String, dynamic>> etas,
    required bool isEnglish,
    String? latitude,
    String? longitude,
    bool isNearby = false,
  }) {
    // Get destination from route details for fallback display
    String? destEn;
    String? destTc;
    
    if (_routeDetails != null) {
      final routeData = _routeDetails!.containsKey('data') 
        ? (_routeDetails!['data'] as Map<String, dynamic>?)
        : _routeDetails!;
      
      if (routeData != null) {
        destEn = routeData['dest_en'];
        destTc = routeData['dest_tc'];
      }
    }
    
    // Check if this stop should be auto-expanded
    final shouldAutoExpand = (widget.autoExpandSeq != null && seq == widget.autoExpandSeq) ||
        (widget.autoExpandStopId != null && stopId == widget.autoExpandStopId);
    
    return ExpandableStopCard(
      key: ValueKey('${widget.route}_${_selectedDirection}_${_selectedServiceType}_$seq'),
      seq: seq,
      stopId: stopId, // Passed to enable per-stop fetching
      displayName: displayName,
      nameEn: nameEn,
      nameTc: nameTc,
      etas: etas, // Initial ETAs from parent (if any)
      isEnglish: isEnglish,
      route: widget.route, // Passed to optimize fetch scope
      selectedServiceType: _selectedServiceType,
      latitude: latitude,
      longitude: longitude,
      destEn: destEn,
      destTc: destTc,
      direction: _selectedDirection,
      isNearby: isNearby,
      autoExpand: shouldAutoExpand,
      onJumpToMap: (lat, lng) => _jumpToMapLocation(lat, lng, stopId: stopId),
    );
  }
  
  /// Build OpenStreetMap view showing all route stops
  Widget _buildMapView() {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([Citybus.buildRouteToStopsMap(), Citybus.buildStopMap()]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              /*RouteDestinationWidget(
                route: widget.route,
                direction: _selectedDirection,
                serviceType: _selectedServiceType,
                cachedRouteData: _routeDetails,
              ),*/
              const SizedBox(height: 8),
              const Expanded(
                child: Center(child: CircularProgressIndicator(year2023: false,)),
              ),
            ],
          );
        }
        if (snap.hasError) {
          return Column(
            children: [
                  RouteDestinationWidget(
                    route: widget.route,
                    direction: _selectedDirection,
                    serviceType: _selectedServiceType,
                    cachedRouteData: _routeDetails,
                  ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(child: Text('Error: ${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ),
            ],
          );
        }

        // Process cached data - handle null data safely
        if (snap.data == null || snap.data!.length < 2) {
          return Column(
            children: [
              RouteDestinationWidget(
                route: widget.route,
                direction: _selectedDirection,
                serviceType: _selectedServiceType,
                cachedRouteData: _routeDetails,
              ),
              const SizedBox(height: 8),
              const Expanded(
                child: Center(child: Text('No data available')),
              ),
            ],
          );
        }
        
        // Safely cast with null checks
        final routeMapData = snap.data![0];
        final stopMapData = snap.data![1];
        
        final routeMap = (routeMapData is Map<String, List<Map<String, dynamic>>>)
            ? routeMapData
            : <String, List<Map<String, dynamic>>>{};
        final stopMap = (stopMapData is Map<String, Map>)
            ? stopMapData.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)))
            : <String, Map<String, dynamic>>{};

        final r = widget.route.trim().toUpperCase();
        final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
        var entries = routeMap[r] ?? routeMap[base] ?? [];

        if (entries.isEmpty) {
          return Column(
            children: [
              RouteDestinationWidget(
                route: widget.route,
                direction: _selectedDirection,
                serviceType: _selectedServiceType,
                cachedRouteData: _routeDetails,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(child: Text(isEnglish ? 'No stop data available' : '無站點資料')),
              ),
            ],
          );
        }

        // Filter by selected direction and service type
        entries = List<Map<String, dynamic>>.from(
          entries.where((e) {
            if (!e.containsKey('seq')) return false;
            if (_selectedDirection != null) {
              final bound = e['bound']?.toString().trim().toUpperCase() ?? '';
              if (bound.isNotEmpty && _selectedDirection!.isNotEmpty && bound[0] != _selectedDirection![0]) return false;
            }
            if (_selectedServiceType != null) {
              final st = e['service_type']?.toString() ?? e['servicetype']?.toString() ?? '';
              if (st != _selectedServiceType) return false;
            }
            return true;
          }),
        );

        // ADD DEDUPLICATION HERE - before sorting
        final uniqueStopsMap = <String, Map<String, dynamic>>{};
        for (final e in entries) {
          final seq = e['seq']?.toString() ?? '';
          if (seq.isNotEmpty && !uniqueStopsMap.containsKey(seq)) {
            uniqueStopsMap[seq] = e;
          }
        }
        entries = uniqueStopsMap.values.toList();
        
        // Sort after deduplication
        entries.sort((a, b) {
          final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        // Build markers for stops
        final List<Marker> markers = [];
        final List<LatLng> polylinePoints = [];

        for (final entry in entries) {
          final stopId = entry['stop']?.toString() ?? '';
          final meta = stopMap[stopId];
          
          if (meta == null) continue;
          
          final latStr = meta['lat']?.toString() ?? meta['latitude']?.toString() ?? '';
          final lngStr = meta['long']?.toString() ?? meta['lng']?.toString() ?? meta['longitude']?.toString() ?? '';
          
          final lat = double.tryParse(latStr);
          final lng = double.tryParse(lngStr);
          
          if (lat == null || lng == null) continue;
          
          final latLng = LatLng(lat, lng);
          polylinePoints.add(latLng);

          final nameEn = meta['name_en']?.toString().toTitleCase() ?? '';
          final nameTc = meta['name_tc']?.toString() ?? '';
          final displayName = isEnglish ? (nameEn.isNotEmpty ? nameEn : nameTc) : (nameTc.isNotEmpty ? nameTc : nameEn);
          final seq = entry['seq']?.toString() ?? '';
          final isHighlighted = _highlightedStopId == stopId;

          markers.add(
            Marker(
              point: latLng,
              width: 80,
              height: 80,
              child: KeyedSubtree(
                key: ValueKey('marker_$seq'),
                child: GestureDetector(
                onTap: () {
                  // Show stop details in a bottom sheet
                  showModalBottomSheet(
                    showDragHandle: true,
                    enableDrag: true,
                    requestFocus: true,
                    context: context,
                    builder: (context) => Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$seq. $displayName',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('Stop ID: $stopId'),
                          const SizedBox(height: 8),
                          Text('${isEnglish ? "Coordinates" : "座標"}: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.list),
                            label: Text(isEnglish ? 'View in list' : '在列表中查看'),
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() {
                                _showMapView = false;
                                _autoExpandSeq = seq;  // ✅ 標記要展開的 seq
                              });
                              _saveMapViewPreference(false);
                              
                              // Scroll to this stop card
                              WidgetsBinding.instance.addPostFrameCallback((_) async {
                                await Future.delayed(const Duration(milliseconds: 300));
                                final key = _stopKeys[seq];
                                final ctx = key?.currentContext;
                                if (ctx != null && mounted) {
                                  await Scrollable.ensureVisible(
                                    ctx,
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeOutCubic,
                                    alignment: 0.2,
                                  );
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Animated pulsing ring for highlighted stop
                    if (isHighlighted)
                      _PulsingRing(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    // Main marker circle
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isHighlighted 
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface, 
                          width: isHighlighted ? 3 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isHighlighted
                              ? Theme.of(context).colorScheme.tertiary.withOpacity(0.5)
                              : Theme.of(context).colorScheme.shadow.withOpacity(0.3),
                            blurRadius: isHighlighted ? 8 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        seq,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: isHighlighted ? 14 : 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),            
          ),
          );
        }

        // Calculate center and zoom level
        LatLng center;
        double zoom = 13.0;
        
        // Prefer user location if available, otherwise use route center
        if (_userPosition != null) {
          // Center on user's current location
          center = LatLng(_userPosition!.latitude, _userPosition!.longitude);
          zoom = 14.0; // Closer zoom when centered on user
        } else if (polylinePoints.isNotEmpty) {
          // Calculate bounding box for route
          double minLat = polylinePoints.first.latitude;
          double maxLat = polylinePoints.first.latitude;
          double minLng = polylinePoints.first.longitude;
          double maxLng = polylinePoints.first.longitude;
          
          for (final point in polylinePoints) {
            if (point.latitude < minLat) minLat = point.latitude;
            if (point.latitude > maxLat) maxLat = point.latitude;
            if (point.longitude < minLng) minLng = point.longitude;
            if (point.longitude > maxLng) maxLng = point.longitude;
          }
          
          center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
          
          // Adjust zoom based on distance
          final latDiff = maxLat - minLat;
          final lngDiff = maxLng - minLng;
          final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
          
          if (maxDiff > 0.1) {
            zoom = 11.0;
          } else if (maxDiff > 0.05) zoom = 12.0;
          else if (maxDiff > 0.02) zoom = 13.0;
          else zoom = 14.0;
        } else {
          // Default to Hong Kong
          center = const LatLng(22.3193, 114.1694);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Route destination header removed - already shown in list view
            // Map
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
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
                          
                          // Performance optimizations
                          maxZoom: 19,
                          minZoom: 10, // Prevent over-zooming out (saves bandwidth)
                          maxNativeZoom: 18, // Tile server's actual max zoom
                          panBuffer: 2, // Increased for smoother panning (was 1)
                          
                          tileSize: 256,
                          retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5, // Dynamic based on device

                          
                          tileProvider: NetworkTileProvider(), // Explicit (has built-in caching)
                          
                          // Error handling
                          errorImage: const AssetImage('assets/map_error_tile.png'), // Optional fallback
                          
                          // Keep alive for better scrolling performance
                          keepBuffer: 5, // Keep 5 extra tiles in memory
                        ),
                        // Polyline showing route path
                        if (polylinePoints.length > 1)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: polylinePoints,
                                strokeWidth: 6.0,
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                                borderStrokeWidth: 1.0,
                                borderColor: Theme.of(context).colorScheme.surface.withOpacity(0.1),
                              ),
                            ],
                          ),
                        // Markers for stops
                        MarkerLayer(markers: markers),
                        // Current location layer with live updates
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
                            headingSectorColor: Theme.of(context).colorScheme.error.withOpacity(0.2),
                            headingSectorRadius: 60,
                            accuracyCircleColor: Theme.of(context).colorScheme.error.withOpacity(0.1),
                            showAccuracyCircle: true,
                            showHeadingSector: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Recenter button
                  if (_userPosition != null)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter_map',
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        foregroundColor: Theme.of(context).colorScheme.error,
                        onPressed: () {
                          _mapController.move(
                            LatLng(_userPosition!.latitude, _userPosition!.longitude),
                            14.0,
                          );
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                ],
              ),
            ),
            // Legend - Hidden per user request
            // Container(
            //   margin: const EdgeInsets.only(top: 8),
            //   padding: const EdgeInsets.all(12),
            //   decoration: BoxDecoration(
            //     color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
            //     borderRadius: BorderRadius.circular(20),
            //     boxShadow: [
            //       BoxShadow(
            //         color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
            //         blurRadius: 6,
            //         offset: const Offset(0, 2),
            //       ),
            //     ],
            //   ),
            //   child: Row(
            //     mainAxisAlignment: MainAxisAlignment.spaceAround,
            //     children: [
            //       Row(
            //         children: [
            //           Container(
            //             width: 20,
            //             height: 20,
            //             decoration: BoxDecoration(
            //               color: Theme.of(context).colorScheme.primary,
            //               shape: BoxShape.circle,
            //             ),
            //           ),
            //           const SizedBox(width: 8),
            //           Text(isEnglish ? 'Bus Stop' : '巴士站'),
            //         ],
            //       ),
            //       if (_userPosition != null)
            //         Row(
            //           children: [
            //             Icon(Icons.my_location, color: Theme.of(context).colorScheme.error, size: 20),
            //             const SizedBox(width: 8),
            //             Text(isEnglish ? 'Your Location' : '您的位置'),
            //           ],
            //         ),
            //     ],
            //   ),
            // ),
          ],
        );
      },
    );
  }

// Compute helper to enrich entries with stop metadata off the main isolate.
// Arg must be a Map with keys 'entries' (List) and 'stopMap' (Map).
List<Map<String, dynamic>> _enrichEntriesForStopMap(Map<String, dynamic> arg) {
  final rawEntries = arg['entries'] as List<dynamic>? ?? [];
  final rawStopMap = arg['stopMap'] as Map<dynamic, dynamic>? ?? {};
  final stopMap = <String, Map<String, dynamic>>{};
  
  // Use for-loop instead of forEach to avoid concurrent modification
  for (final entry in rawStopMap.entries) {
    try {
      stopMap[entry.key.toString()] = Map<String, dynamic>.from(entry.value as Map);
    } catch (_) {}
  }

  final out = <Map<String, dynamic>>[];
  for (final re in rawEntries) {
    try {
      final e = Map<String, dynamic>.from(re as Map);
      final sid = e['stop']?.toString() ?? '';
      e['stopInfo'] = stopMap[sid];
      out.add(e);
    } catch (_) {}
  }
  return out;
}
}

// Expandable Stop Card with Auto-Refresh
class ExpandableStopCard extends StatefulWidget {
  final String seq;
  final String displayName;
  final String? nameEn;
  final String? nameTc;
  final List<Map<String, dynamic>> etas;
  final bool isEnglish;
  final String route;
  final String? selectedServiceType;
  final String? stopId;
  final String? latitude;
  final String? longitude;
  final String? destEn;
  final String? destTc;
  final String? direction;
  final bool isNearby;
  final bool autoExpand;
  final void Function(double lat, double lng)? onJumpToMap;

  const ExpandableStopCard({
    super.key,
    required this.seq,
    required this.displayName,
    this.nameEn,
    this.nameTc,
    required this.etas,
    required this.isEnglish,
    required this.route,
    this.selectedServiceType,
    this.stopId,
    this.latitude,
    this.longitude,
    this.destEn,
    this.destTc,
    this.direction,
    this.isNearby = false,
    this.autoExpand = false,
    this.onJumpToMap,
  });

  @override
  State<ExpandableStopCard> createState() => _ExpandableStopCardState();
}

class _ExpandableStopCardState extends State<ExpandableStopCard> with AutomaticKeepAliveClientMixin {
  bool _isExpanded = false;
  bool _etaRefreshing = false;
  bool _shouldShowRefreshAnimation = false;
  bool _autoRefreshEnabled = false;
  Timer? _autoRefreshTimer;
  bool _autoFetchRunning = false;
  bool _autoEnabledByNearby = false;

  @override
  bool get wantKeepAlive => true;

  Timer? _clockTimer;
  final Map<String, DateTime> _departedEtaTimestamps = {};
  Timer? _etaCleanupTimer;
  bool _departedRefetchScheduled = false;
  Timer? _departedRefetchTimer;
  List<Map<String, dynamic>>? _localEtas;
  
  List<Map<String, dynamic>> get _displayEtas => _localEtas ?? widget.etas;

  @override
  void initState() {
    super.initState();
    if (widget.isNearby || widget.autoExpand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _isExpanded = true;
          _autoRefreshEnabled = true;
          if (widget.isNearby) _autoEnabledByNearby = true;
        });
        // 🆕 Trigger immediate fetch for the specific route
        _autoRefetchOnExpand(); 
        _startAutoRefreshTimer();
      });
    }
  }

  void _startEtaCleanupTimer() {
    _etaCleanupTimer?.cancel();
    _etaCleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      
      final now = DateTime.now();
      final originalSize = _departedEtaTimestamps.length;
      _departedEtaTimestamps.removeWhere((key, timestamp) {
        return now.difference(timestamp).inSeconds >= 10;
      });
      
      if (originalSize != _departedEtaTimestamps.length && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _departedRefetchTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _clockTimer?.cancel();
    _etaCleanupTimer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterEtas(List<Map<String, dynamic>> etas) {
    return etas.where((e) {
      final eRoute = e['route']?.toString().trim().toUpperCase() ?? '';
      if (eRoute != widget.route.toUpperCase()) return false;
      
      if (widget.direction?.isNotEmpty ?? false) {
        final eDir = e['dir']?.toString().trim().toUpperCase() ?? '';
        final dirChar = widget.direction!.trim().toUpperCase()[0];
        if (eDir.isEmpty || eDir[0] != dirChar) return false;
      }
      
      if (widget.selectedServiceType != null) {
        final eSvc = e['service_type']?.toString() ?? '';
        if (eSvc != widget.selectedServiceType) return false;
      }
      
      return true;
    }).toList();
  }

  /// Auto-refetch when the card is expanded
  Future<void> _autoRefetchOnExpand() async {
    if (widget.stopId?.isEmpty ?? true) return;
    if (!mounted) return;

    setState(() => _shouldShowRefreshAnimation = true);
    
    try {
      // ✅ OPTIMIZED: Fetch ETA only for this specific stop and route
      // This maps to Citybus.fetchStopEta(stopId, route: route)
      final allStopEtas = await Citybus.fetchStopEta(
        widget.stopId!, 
        route: widget.route
      );
      
      // Filter locally to ensure strict safety (double-check direction/service type)
      final filteredEtas = _filterEtas(allStopEtas);
      
      if (mounted) {
        setState(() => _localEtas = filteredEtas);
      }
      
      // Keep loading animation visible briefly for user feedback
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      debugPrint('Error auto-fetching stop ETA: $e');
      // On error, keep the animation briefly so it doesn't just flash
      await Future.delayed(const Duration(milliseconds: 1000));
    } finally {
      if (mounted) setState(() => _shouldShowRefreshAnimation = false);
    }
  }

  /// Manual refresh triggered by the user tapping the "Refresh" button
  Future<void> _manualRefetchStopEta() async {
    if (widget.stopId?.isEmpty ?? true) return;
    if (!mounted) return;

    setState(() => _etaRefreshing = true);
    try {
      // ✅ OPTIMIZED: Direct API call for specific route/stop
      final allStopEtas = await Citybus.fetchStopEta(
        widget.stopId!, 
        route: widget.route
      );
      
      final filteredEtas = _filterEtas(allStopEtas);
      
      if (mounted) {
        setState(() => _localEtas = filteredEtas);
      }
      
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      debugPrint('Error manually fetching stop ETA: $e');
      await Future.delayed(const Duration(milliseconds: 800));
    } finally {
      if (mounted) setState(() => _etaRefreshing = false);
    }
  }

  /// Auto-refresh timer logic (e.g., for "Nearby" stops or "Auto" mode)
  void _startAutoRefreshTimer({Duration? interval}) {
    if (widget.stopId?.isEmpty ?? true) return;
    // Prevent duplicate timers
    if (_autoRefreshTimer?.isActive ?? false) return;

    final refreshInterval = interval ?? const Duration(seconds: 15);

    _autoRefreshTimer = Timer.periodic(refreshInterval, (_) async {
      // Skip if widget unmounted or a fetch is already in progress
      if (!mounted || _autoFetchRunning) return;
      
      _autoFetchRunning = true;
      try {
        // ✅ OPTIMIZED: Silent background update
        final allStopEtas = await Citybus.fetchStopEta(
          widget.stopId!, 
          route: widget.route
        );
        
        final filteredEtas = _filterEtas(allStopEtas);
        
        if (mounted) setState(() => _localEtas = filteredEtas);
      } catch (e) {
        debugPrint('Error in auto-refresh timer: $e');
      } finally {
        _autoFetchRunning = false;
      }
    });
  }

  Future<void> scrollIntoView() async {
    try {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }
  
  @override
  void didUpdateWidget(ExpandableStopCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isNearby && widget.isNearby) {
      if (!_autoRefreshEnabled) {
        setState(() {
          _autoRefreshEnabled = true;
          _autoEnabledByNearby = true;
        });
      }
      setState(() => _isExpanded = true);
      Future.delayed(const Duration(milliseconds: 100), scrollIntoView);
      _startAutoRefreshTimer();
    }

    if (oldWidget.isNearby && !widget.isNearby) {
      if (_autoEnabledByNearby) {
        setState(() {
          _autoRefreshEnabled = false;
          _autoEnabledByNearby = false;
        });
      }
      if (!_autoRefreshEnabled) _stopAutoRefreshTimer();
    }
    
    // Handle auto-expand when widget updates (e.g., data loads)
    if (!oldWidget.autoExpand && widget.autoExpand && !_isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _isExpanded = true;
          _autoRefreshEnabled = true;
        });
        _startAutoRefreshTimer();
        Future.delayed(const Duration(milliseconds: 100), scrollIntoView);
      });
    }
  }

  void _toggleExpanded() {
    final wasExpanded = _isExpanded;
    setState(() => _isExpanded = !_isExpanded);
    
    if (!wasExpanded && _isExpanded) {
      _autoRefetchOnExpand();
      if (_autoRefreshEnabled) _startAutoRefreshTimer();
      _startClockTimer();
    }
    
    if (wasExpanded && !_isExpanded) {
      _stopAutoRefreshTimer();
      _stopClockTimer();
    }
  }

  void _startClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }


  void _stopAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _autoFetchRunning = false;
    _autoEnabledByNearby = false;
  }

  Future<void> _pinStop(BuildContext context) async {
    try {
      await Citybus.pinStop(
        route: widget.route,
        stopId: widget.stopId ?? '',
        seq: widget.seq,
        stopName: widget.displayName,
        stopNameEn: widget.nameEn,
        stopNameTc: widget.nameTc,
        latitude: widget.latitude,
        longitude: widget.longitude,
        direction: widget.direction,
        serviceType: widget.selectedServiceType,
        destEn: widget.destEn,
        destTc: widget.destTc,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEnglish 
                ? 'Stop pinned: ${widget.displayName}' 
                : '已釘選站點: ${widget.displayName}'
              ,
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEnglish 
                ? 'Failed to pin stop: $e' 
                : '釘選失敗: $e'
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Extracted: ETA state calculation
  ({String text, bool isDeparted, bool isNearlyArrived}) _calculateEtaState(Duration diff, int mins) {
    final seconds = diff.inSeconds;

    if (seconds < -10) {
      return (
        text: widget.isEnglish ? '- min' : '- 分鐘',
        isDeparted: true,
        isNearlyArrived: false,
      );
    }
    
    if (seconds <= 0) {
      return (
        text: widget.isEnglish ? 'NOW' : '而家',
        isDeparted: false,
        isNearlyArrived: true,
      );
    }
    
    if (mins < 1) {
      return (
        text: widget.isEnglish ? 'NOW' : '即將',
        isDeparted: false,
        isNearlyArrived: true,
      );
    }
    
    return (
      text: widget.isEnglish ? '$mins min' : '$mins分鐘',
      isDeparted: false,
      isNearlyArrived: false,
    );
  }

  // Extracted: Build single ETA item widget
  Widget _buildEtaItem({
    required String etaText,
    required bool isDeparted,
    required bool isNearlyArrived,
    required String remark,
    required String absoluteTime,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10.0, top: 0.0, bottom: 8.0, left: 2.0),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etaText,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDeparted 
                    ? colorScheme.onSurface.withOpacity(0.6)
                    : (isNearlyArrived ? colorScheme.secondary : colorScheme.primary),
                fontSize: 24,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            _buildEtaSubtitle(remark, absoluteTime, theme, colorScheme),
          ],
        ),
      ),
    );
  }

  // Extracted: Build ETA subtitle
  Widget _buildEtaSubtitle(String remark, String abs, ThemeData theme, ColorScheme colorScheme) {
    final hasRemark = remark.isNotEmpty;
    
    return hasRemark
    ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            remark,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '($abs)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              fontSize: 10,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      )
    : Text(
        abs,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withOpacity(0.7),
          fontSize: 10,
          height: 1.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  }

  // Extracted: Build ETA items list
  List<Widget> _buildEtaItems(ThemeData theme, ColorScheme colorScheme) {
    return _displayEtas.take(3).map((eta) {
      final etaRaw = eta['eta'] ?? eta['eta_time'];
      if (etaRaw == null) return const SizedBox.shrink();

      try {
        final dt = DateTime.parse(etaRaw.toString()).toLocal();
        final diff = dt.difference(DateTime.now());
        final mins = diff.inMinutes;
        
        final state = _calculateEtaState(diff, mins);
        
        //final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
        final abs = DateFormat.Hm().format(dt);//use24 ?  : DateFormat.jm().format(dt);
        
        final rmkEn = eta['rmk_en']?.toString() ?? eta['rmken']?.toString() ?? '';
        final rmkTc = eta['rmk_tc']?.toString() ?? eta['rmktc']?.toString() ?? '';
        final remark = widget.isEnglish ? rmkEn : rmkTc;

        return _buildEtaItem(
          etaText: state.text,
          isDeparted: state.isDeparted,
          isNearlyArrived: state.isNearlyArrived,
          remark: remark,
          absoluteTime: abs,
          theme: theme,
          colorScheme: colorScheme,
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }).toList();
  }

  Widget _buildStatusSection(ThemeData theme, ColorScheme colorScheme, Color? nearbyTextSecondary) {
  final statusStyle = theme.textTheme.bodySmall!.copyWith(
    color: widget.isNearby ? nearbyTextSecondary : colorScheme.onSurfaceVariant,
    height: 1.2, // Consistent line-height is key for stability
  );

   // 取得第一班車的 raw 資料來判斷是否為 null
  final firstEta = _displayEtas.isNotEmpty ? _displayEtas.first : null;
  final etaRaw = firstEta != null ? (firstEta['eta'] ?? firstEta['eta_time']) : null;

  // [新增] 計算無 ETA 時的備註
  String? noEtaRemark;
  if (firstEta != null && etaRaw == null) {
      final rmkEn = firstEta['rmk_en']?.toString() ?? firstEta['rmken']?.toString() ?? '';
      final rmkTc = firstEta['rmk_tc']?.toString() ?? firstEta['rmktc']?.toString() ?? '';
      final r = widget.isEnglish ? rmkEn : (rmkTc.isNotEmpty ? rmkTc : rmkEn);
      if (r.isNotEmpty) noEtaRemark = r;
  }


  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 300),
    switchInCurve: Curves.easeOutCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: child),
    ),
    child: _isExpanded 
      ? (_shouldShowRefreshAnimation 
          ? Row(
              key: const ValueKey('loading'),
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, strokeAlign: BorderSide.strokeAlignInside, color: colorScheme.primary)),
                const SizedBox(width: 8),
                Text(widget.isEnglish ? 'Loading...' : '更新中...', style: statusStyle.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600)),
              ],
            )
           : (etaRaw == null
                  // [修改] 改為 Column 以同時顯示提示文字與備註
                  ? Column(
                      key: const ValueKey('empty'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            widget.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士',
                            style: statusStyle),
                        // [新增] 如果有備註則顯示 (例如: 服務暫停)
                        if (noEtaRemark != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
                            child: Text(
                              noEtaRemark, 
                              style: statusStyle.copyWith(
                                color: colorScheme.error, 
                                fontSize: 11
                              )
                            ),
                          ),
                      ],
                    )
                  : Row(key: const ValueKey('etas'), children: _buildEtaItems(theme, colorScheme))))
      : Text(
          key: const ValueKey('collapsed'),
          widget.isEnglish ? 'Hidden' : '班次隱藏',
          style: statusStyle,
        ),
  );
}


  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Modern 2025 M3 Surface logic
    final isActive = _isExpanded || widget.isNearby;

    // Refined Tertiary colors for Nearby state
    // 使用 TertiaryFixedVariant 或 TertiaryContainer 搭配較高的不透明度值
    // Fixed 色票在深淺模式下保持一致，因此更有活力。
    final nearbyBgColor = isDark 
        ? colorScheme.tertiaryContainer.withAlpha(80)  // 深色模式下提供明亮的底色
        : colorScheme.tertiaryContainer.withAlpha(150); // 淺色模式下更飽和

    // 邊框使用主題色 Tertiary 且透明度更高，使其更顯眼
    final nearbyBorderColor = colorScheme.tertiary.withOpacity(isDark ? 0.8 : 0.6);

    // 文字顏色使用 onTertiaryContainer 確保高對比度
    final nearbyTextPrimary = colorScheme.onTertiaryContainer;
    final nearbyTextSecondary = colorScheme.onTertiaryContainer.withOpacity(0.85); // 副標題顏色較淡，但依然清晰

    // Active state base colors
    final activeSurface = widget.isNearby ? nearbyBgColor : colorScheme.surfaceContainerHigh;
    final inactiveSurface = colorScheme.surfaceContainerLow;
    
    final isNear = widget.isNearby;

    // Dynamic Border Color
    final currentBorderColor = isActive
        ? (widget.isNearby ? nearbyBorderColor : colorScheme.primary.withOpacity(0.3))
        : colorScheme.outlineVariant.withOpacity(0.3);

    final now = DateTime.now();
    final hasDeparted = _displayEtas.any((e) {
      final etaRaw = e['eta'] ?? e['eta_time'];
      if (etaRaw == null) return false;
      try {
        final dt = DateTime.parse(etaRaw.toString()).toLocal();
        return dt.difference(now).inMinutes < -1;
      } catch (_) {
        return false;
      }
    });

    if (hasDeparted && !_departedRefetchScheduled && (widget.stopId?.isNotEmpty ?? false)) {
      _departedRefetchScheduled = true;
      _departedRefetchTimer?.cancel();
      _departedRefetchTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        _autoRefetchOnExpand();
        _departedRefetchScheduled = false;
      });
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 6.0),
      child: Card(
        elevation: isActive ? 1 : 0,
        margin: EdgeInsets.zero,
        color: isActive ? activeSurface : inactiveSurface, 
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            // REPLACED: Logic moved to currentBorderColor variable
            color: currentBorderColor, 
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _toggleExpanded,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              if (isActive && isNear)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(16.0, 2.0, 0.0, 2.0), // left, top, right, bottom
                              decoration: BoxDecoration(
                                color: nearbyTextSecondary.withOpacity(0.1),
                                border: Border(
                                  bottom: BorderSide(color: nearbyBorderColor, width: 1.5),
                                ),
                              ),
                              child: Text(
                                widget.isEnglish ? 'Nearby Stop' : '附近站點',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: nearbyTextSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),

                          

              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? (widget.isNearby ? nearbyBorderColor : colorScheme.primary)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.seq,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isActive 
                              ? (widget.isNearby ? colorScheme.onTertiary : colorScheme.onPrimary)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    

                  
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          //const SizedBox(height: 2),
                          // Animated Status Area
                          _buildStatusSection(theme, colorScheme, nearbyTextSecondary),
                          
                          const SizedBox(height: 0), // Tighter grouping for better visual hierarchy

                          OptionalMarquee(
                            text: widget.displayName.toTitleCase(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                              color: widget.isNearby ? nearbyTextPrimary : colorScheme.onSurface,
                              letterSpacing: -0.2,
                            ) ?? const TextStyle(),
                          )


                        ],
                      ),
                    ),

                    // Modernized Animated Icon Button
                    IconButton(
                      visualDensity: VisualDensity.compact, // Cleaner look inside cards
                      onPressed: _toggleExpanded, // Use existing toggle logic
                      icon: AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300), // Matched to switcher
                        curve: Curves.easeInOutBack, // Adds a tiny "spring" to the arrow
                        child: Icon(
                          Icons.keyboard_arrow_down, // Sleeker modern chevron
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                  ],
                ),
              ),

              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: _isExpanded
                    ? Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          border: Border(
                            top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2)),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: _etaRefreshing ? null : _manualRefetchStopEta,
                              icon: _etaRefreshing
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(colorScheme.secondary),
                                      ),
                                    )
                                  : const Icon(Icons.refresh, size: 20),
                              label: Text(widget.isEnglish ? 'Refresh' : '刷新'),
                              style: TextButton.styleFrom(foregroundColor: colorScheme.secondary),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final newState = !_autoRefreshEnabled;
                                setState(() {
                                  _autoRefreshEnabled = newState;
                                  _autoEnabledByNearby = false;
                                });

                                if (_isExpanded) {
                                  _startAutoRefreshTimer();
                                  if (!_autoFetchRunning && (widget.stopId?.isNotEmpty ?? false)) {
                                    _autoFetchRunning = true;
                                    try {
                                      await Citybus.fetchStopEta(widget.stopId!);
                                    } catch (_) {}
                                    _autoFetchRunning = false;
                                  }
                                } else if (!newState) {
                                  _stopAutoRefreshTimer();
                                }
                              },
                              icon: Icon(
                                _autoRefreshEnabled ? Icons.autorenew : Icons.autorenew_outlined,
                                size: 20,
                                color: _autoRefreshEnabled ? colorScheme.secondary : null,
                              ),
                              label: Text(widget.isEnglish ? 'Auto' : '自動'),
                              style: TextButton.styleFrom(
                                foregroundColor: _autoRefreshEnabled ? colorScheme.secondary : colorScheme.onSurfaceVariant
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _pinStop(context),
                              icon: const Icon(Icons.push_pin_outlined, size: 20),
                              label: Text(widget.isEnglish ? 'Pin' : '釘選'),
                              style: TextButton.styleFrom(foregroundColor: colorScheme.secondary),
                            ),
                            if (widget.latitude != null && widget.longitude != null)
                              TextButton.icon(
                                onPressed: () {
                                  widget.onJumpToMap?.call(
                                    double.tryParse(widget.latitude!) ?? 0,
                                    double.tryParse(widget.longitude!) ?? 0,
                                  );
                                },
                                icon: const Icon(Icons.map_outlined, size: 20),
                                label: Text(widget.isEnglish ? 'Map' : '地圖'),
                                style: TextButton.styleFrom(foregroundColor: colorScheme.secondary),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class StopEtaTile extends StatefulWidget {
  final String stopId;
  const StopEtaTile({super.key, required this.stopId});

  @override
  State<StopEtaTile> createState() => _StopEtaTileState();
}

class _StopEtaTileState extends State<StopEtaTile> {
  bool loading = false;
  String? error;
  List<Map<String, dynamic>>? etas;

  String _formatEtaLocal(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
      // compute relative
      final now = DateTime.now();
      final diff = dt.difference(now);
      String relative;
      if (diff.inSeconds.abs() < 30) {
        relative = 'Due';
      } else if (diff.isNegative) {
        final mins = diff.abs().inMinutes;
        if (mins < 1) {
          relative = 'Departed';
        } else if (mins < 60) {
          relative = '$mins min ago';
        } else {
          final h = diff.abs().inHours;
          final m = diff.abs().inMinutes % 60;
          relative = '${h}h${m > 0 ? ' ${m}m' : ''} ago';
        }
      } else {
        final mins = diff.inMinutes;
        if (mins < 1) {
          relative = 'Due';
        } else if (mins < 60) {
          relative = '$mins min';
        } else {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          relative = '${h}h${m > 0 ? ' ${m}m' : ''}';
        }
      }
      final locale = Localizations.localeOf(context).toString();
      final abs = use24 ? DateFormat.Hm().format(dt) : DateFormat.jm(locale).format(dt);
      if (relative == 'Departed') return 'Departed ($abs)';
      return '$relative ($abs)';
    } catch (_) {
      return raw?.toString() ?? '—';
    }
  }

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await Citybus.fetchStopEta(widget.stopId);
      setState(() {
        etas = list;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator(year2023: false,)));
    if (error != null) return Padding(padding: const EdgeInsets.all(8.0), child: Text('Error: $error', style: TextStyle(color: Theme.of(context).colorScheme.error)));
    if (etas == null || etas!.isEmpty) return const Padding(padding: EdgeInsets.all(8.0), child: Text('No ETA data'));

    return Column(
      children: etas!.map((e) {
        final route = e['route'] ?? '';
        final eta = _formatEtaLocal(e['eta']);
        final dest = e['desten'] ?? e['desttc'] ?? '';
        final remark = e['rmken'] ?? e['rmktc'] ?? '';
        final etatime = e['eta_time'] != null ? 'time: ${e['eta_time']}' : '';
        return ListTile(
          title: Text('$route → $dest'),
          subtitle: Text('eta: $eta\n$remark\n$etatime'),
        );
      }).toList(),
    );
  }
}

// Independent Route Destination Widget - fetches from Route API
class RouteDestinationWidget extends StatefulWidget {
  final String route;
  final String? direction;
  final String? serviceType;
  /// Optional pre-fetched route data from parent to avoid duplicate API calls
  final Map<String, dynamic>? cachedRouteData;

  const RouteDestinationWidget({
    super.key,
    required this.route,
    this.direction,
    this.serviceType,
    this.cachedRouteData,
  });

  @override
  State<RouteDestinationWidget> createState() => _RouteDestinationWidgetState();
}

class _RouteDestinationWidgetState extends State<RouteDestinationWidget> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _routeData;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(RouteDestinationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh if route or cached data changes
    if (oldWidget.route != widget.route || 
        oldWidget.cachedRouteData != widget.cachedRouteData) {
      _loadData();
    }
    // If direction changes, we just need to rebuild to update the swap logic, 
    // but no new fetch is required if we already have the base route info.
    if (oldWidget.direction != widget.direction && _routeData != null) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadData() async {
    // 1. Use cached data if provided (Fastest)
    if (widget.cachedRouteData != null) {
      final data = widget.cachedRouteData!.containsKey('data')
          ? (widget.cachedRouteData!['data'] as Map<String, dynamic>?)
          : widget.cachedRouteData!;
      
      if (data != null && mounted) {
        setState(() {
          _routeData = data;
          _loading = false;
          _error = null;
        });
        return;
      }
    }
    

    // 2. Fetch from Official API if no cache
    await _fetchRouteData();
  }

  Future<void> _fetchRouteData() async {
    if (widget.route.isEmpty) return;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Official CTB Route API
      final url = Uri.parse('https://rt.data.gov.hk/v2/transport/citybus/route/CTB/${widget.route}');
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final jsonResponse = json.decode(jsonString);
        
        if (jsonResponse is Map<String, dynamic> && jsonResponse['data'] is List) {
          final list = jsonResponse['data'] as List;
          if (list.isNotEmpty) {
            // Usually the API returns one entry defining the route (Orig->Dest).
            // We take the first matching entry.
            final routeInfo = list.firstWhere(
              (e) => e['route'] == widget.route,
              orElse: () => list.first,
            );

            if (mounted) {
              setState(() {
                _routeData = routeInfo;
                _loading = false;
              });
              return;
            }
          }
        }
      }
      throw Exception('Route data not found');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    // Loading State
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Error State
    if (_error != null || _routeData == null) {
      // Fallback: show just the route number if loading fails
      //return const SizedBox.shrink(); 
    }

    // --- Data Extraction & Direction Logic ---
    // ✅ MODIFIED SECTION: Fallback instead of shrinking
    // If we have an error or no data, show the container with just the Route Number
    // instead of disappearing.
    Map<String, dynamic> safeRouteData = _routeData ?? {};
    
    // 1. Get Base Info (Safely)
    String rawOrig = '';
    String rawDest = '';
    
    if (safeRouteData.isNotEmpty) {
      rawOrig = isEnglish
          ? (safeRouteData['orig_en'] ?? safeRouteData['origen'] ?? '')
          : (safeRouteData['orig_tc'] ?? safeRouteData['origtc'] ?? '');

      rawDest = isEnglish
          ? (safeRouteData['dest_en'] ?? safeRouteData['desten'] ?? '')
          : (safeRouteData['dest_tc'] ?? safeRouteData['desttc'] ?? '');
    }

    // 2. Determine User Selected Direction
    final selectedDir = widget.direction?.trim().toUpperCase();
    final isInbound = selectedDir != null && selectedDir.startsWith('I');
    
    // 3. Apply Swapping Logic
    final displayFrom = isInbound ? rawDest : rawOrig;
    final displayTo   = isInbound ? rawOrig : rawDest;

    // 4. Styling Variables
    IconData dirIcon = Icons.arrow_circle_right;
    final cs = Theme.of(context).colorScheme;
    Color dirColor = cs.primary; 

    if (isInbound) {
      dirIcon = Icons.arrow_circle_left;
      dirColor = cs.tertiary; 
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      child: Padding(
        key: ValueKey('${widget.route}-${widget.direction}'),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                  width: 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    // Route Number Badge
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: AutoSizeText(
                              widget.route,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: dirColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              dirIcon,
                              color: dirColor,
                              size: 20,
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    
                    // Origin and Destination Text (Only show if we have data)
                    Expanded(
                      child: displayFrom.isEmpty && displayTo.isEmpty 
                      ? Text(
                          isEnglish ? 'Details unavailable' : '暫無路線資料',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        )
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // "From" Line
                          if (displayFrom.isNotEmpty) ...[
                             // ... existing From logic ...
                             Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${isEnglish ? 'From' : '由'}:  ',
                                  style: TextStyle(
                                    letterSpacing: -0.05,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                    height: 1,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.88),
                                  ),
                                ),
                                Expanded(
                                  child: OptionalMarquee(
                                    text: displayFrom.toTitleCase(),
                                    style: TextStyle(
                                      letterSpacing: -0.05,
                                      fontSize: 10,
                                      height: 1,
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.88),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                          ],
                          
                          // "To" Line
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const SizedBox(height: 4,),
                              Text(
                                '${isEnglish ? 'To' : '往'}:  ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Expanded(
                                child: OptionalMarquee(
                                  text: displayTo.toTitleCase(),
                                  style: TextStyle(
                                    letterSpacing: -0.05,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulsing ring animation widget for highlighted map markers
class _PulsingRing extends StatefulWidget {
  final Color color;
  
  const _PulsingRing({required this.color});
  
  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
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
          width: 40 + (_animation.value * 25),
          height: 40 + (_animation.value * 25),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withOpacity(1.0 - _animation.value),
              width: 3,
            ),
          ),
        );
      },
    );
  }
}
