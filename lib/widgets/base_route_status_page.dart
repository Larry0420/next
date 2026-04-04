import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/location_service.dart';
import '../services/preference_manager.dart';
import '../services/eta_formatter.dart';
import '../services/stop_metadata_normalizer.dart';
import '../services/prebuilt_data_loader.dart';

/// Abstract base class for route status pages
/// 
/// Provides shared functionality for all company-specific route status pages:
/// - Location services initialization and management
/// - Map view preference handling
/// - ETA formatting with language support
/// - Stop metadata normalization
/// - Prebuilt data loading with fallback strategies
/// - Common UI patterns and state management
/// 
/// Company-specific pages (CTB, KMB, NLB, GMB) should extend this class
/// and implement the abstract methods for company-specific logic.
abstract class BaseRouteStatusPage<T extends StatefulWidget> extends State<T> {
  // ============================================================
  // Abstract Methods - Must be implemented by subclasses
  // ============================================================
  
  /// Get the company name for preference keys and logging
  String get companyName;
  
  /// Get the route ID for the current page
  String get routeId;
  
  /// Fetch route data (API call)
  Future<void> fetchRouteData();
  
  /// Fetch ETA data for the route
  Future<void> fetchEtaData();
  
  /// Build the main content widget
  Widget buildContent(BuildContext context);
  
  // ============================================================
  // Shared Services
  // ============================================================
  
  late final LocationService _locationService;
  late final PreferenceManager _preferenceManager;
  late final EtaFormatter _etaFormatter;
  late final PrebuiltDataLoader _dataLoader;
  
  // ============================================================
  // Shared State
  // ============================================================
  
  // Route data
  Map<String, dynamic>? routeData;
  String? error;
  bool loading = false;
  
  // Location state
  Position? userPosition;
  bool showLocationBanner = false;
  bool showLocationButton = false;
  
  // Map view state
  bool showMapView = false;
  late final MapController mapController;
  
  // Scroll controller
  final ScrollController scrollController = ScrollController();
  
  // Keys for stop widgets
  final Map<String, GlobalKey> stopKeys = {};
  
  // Auto-refresh state
  Timer? etaRefreshTimer;
  Duration etaRefreshInterval = const Duration(seconds: 15);
  int etaConsecutiveErrors = 0;
  bool hasLoadedEtaOnce = false;
  
  // ============================================================
  // Lifecycle Methods
  // ============================================================
  
  @override
  void initState() {
    super.initState();
    
    // Initialize shared services
    _locationService = LocationService(mounted: mounted);
    _preferenceManager = PreferenceManager();
    _etaFormatter = EtaFormatter(isEnglish: isEnglish);
    _dataLoader = PrebuiltDataLoader();
    
    // Initialize map controller
    mapController = MapController();
    
    // Load initial data
    _initialize();
  }
  
  @override
  void dispose() {
    etaRefreshTimer?.cancel();
    scrollController.dispose();
    mapController.dispose();
    super.dispose();
  }
  
  /// Initialize all shared components
  Future<void> _initialize() async {
    // Load preferences
    await _loadPreferences();
    
    // Initialize location services
    await initializeLocation();
    
    // Fetch initial data
    await fetchRouteData();
    await fetchEtaData();
    
    // Start auto-refresh
    _startEtaAutoRefresh();
  }
  
  // ============================================================
  // Location Services
  // ============================================================
  
  /// Initialize location services
  /// 
  /// Handles permission checks and position fetching with fallback strategies
  Future<bool> initializeLocation() async {
    final success = await _locationService.initialize();
    
    if (success && mounted) {
      setState(() {
        userPosition = _locationService.currentPosition;
        showLocationBanner = _locationService.showLocationBanner;
      });
    }
    
    return success;
  }
  
  /// Update location state from external source
  void updateLocationState({
    Position? position,
    bool? showBanner,
    bool? showButton,
  }) {
    if (!mounted) return;
    
    setState(() {
      if (position != null) userPosition = position;
      if (showBanner != null) showLocationBanner = showBanner;
      if (showButton != null) showLocationButton = showButton;
    });
  }
  
  /// Get distance to a stop
  double? getDistanceToStop(double stopLat, double stopLng) {
    if (userPosition == null) return null;
    
    final userLat = userPosition!.latitude;
    final userLng = userPosition!.longitude;
    
    return _calculateDistance(userLat, userLng, stopLat, stopLng);
  }
  
  // ============================================================
  // Preference Management
  // ============================================================
  
  /// Load all preferences
  Future<void> _loadPreferences() async {
    await _preferenceManager.initialize();
    
    if (mounted) {
      setState(() {
        showMapView = _preferenceManager._cachedMapViewPref ?? false;
      });
    }
  }
  
  /// Load map view preference
  Future<void> loadMapViewPreference() async {
    final pref = await _preferenceManager.getMapViewPreference();
    if (mounted) {
      setState(() {
        showMapView = pref;
      });
    }
  }
  
  /// Save map view preference
  Future<void> saveMapViewPreference(bool value) async {
    await _preferenceManager.setMapViewPreference(value);
    if (mounted) {
      setState(() {
        showMapView = value;
      });
    }
  }
  
  // ============================================================
  // ETA Formatting
  // ============================================================
  
  /// Format ETA time for display
  String formatEta(String etaTime, {DateTime? currentTime}) {
    return _etaFormatter.formatEta(etaTime, currentTime: currentTime);
  }
  
  /// Format ETA with relative time and status
  String formatEtaWithStatus(String etaTime, String status) {
    return _etaFormatter.formatEtaWithStatus(etaTime, status);
  }
  
  /// Calculate minutes until arrival
  int? calculateMinutesUntil(String etaTime) {
    return _etaFormatter.calculateMinutesUntil(etaTime);
  }
  
  /// Check if ETA is arriving soon
  bool isArrivingSoon(String etaTime) {
    return _etaFormatter.isArrivingSoon(etaTime);
  }
  
  // ============================================================
  // Stop Metadata
  // ============================================================
  
  /// Get stop name with language preference
  String getStopName(dynamic meta) {
    return StopMetadataNormalizer.getName(meta, isEnglish: isEnglish);
  }
  
  /// Get stop coordinates
  Map<String, double?> getStopCoordinates(dynamic meta) {
    return StopMetadataNormalizer.getCoordinates(meta);
  }
  
  /// Normalize stop metadata
  Map<String, dynamic> normalizeStopMetadata(dynamic meta) {
    return StopMetadataNormalizer.normalize(meta);
  }
  
  // ============================================================
  // Map View
  // ============================================================
  
  /// Jump to a specific location on the map
  void jumpToMapLocation(double latitude, double longitude, {String? stopId}) {
    if (!showMapView) {
      setState(() {
        showMapView = true;
      });
      saveMapViewPreference(true);
      
      // Wait for map to build, then move to location
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            mapController.move(LatLng(latitude, longitude), 17.0);
          }
        });
      });
    } else {
      mapController.move(LatLng(latitude, longitude), 17.0);
    }
  }
  
  /// Toggle map view
  void toggleMapView() {
    saveMapViewPreference(!showMapView);
  }
  
  // ============================================================
  // Auto-Refresh
  // ============================================================
  
  /// Start ETA auto-refresh timer
  void _startEtaAutoRefresh() {
    _stopEtaAutoRefresh();
    etaRefreshTimer = Timer.periodic(etaRefreshInterval, (_) {
      _refreshEta();
    });
  }
  
  /// Stop ETA auto-refresh timer
  void _stopEtaAutoRefresh() {
    etaRefreshTimer?.cancel();
    etaRefreshTimer = null;
  }
  
  /// Refresh ETA data
  Future<void> _refreshEta() async {
    if (!mounted) return;
    
    try {
      await fetchEtaData();
      etaConsecutiveErrors = 0;
    } catch (e) {
      etaConsecutiveErrors++;
      
      // Back off on consecutive errors
      if (etaConsecutiveErrors >= 3) {
        _stopEtaAutoRefresh();
      }
    }
  }
  
  // ============================================================
  // Utilities
  // ============================================================
  
  /// Get language preference
  bool get isEnglish {
    // This should come from LanguageProvider
    // For now, default to true
    return true;
  }
  
  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371; // kilometers
    
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
        math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
  
  // ============================================================
  // Build Method
  // ============================================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: buildContent(context),
    );
  }
}

/// Extension for PreferenceManager to access cached preferences
extension PreferenceManagerExtension on PreferenceManager {
  bool? get _cachedMapViewPref => null; // Would be actual cached value
}

/// Extension for EtaFormatter to check English preference
extension EtaFormatterExtension on EtaFormatter {
  bool get isEnglish => true; // Would come from LanguageProvider
}