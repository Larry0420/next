import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Global location provider that fetches location once on app startup
/// 
/// Benefits:
/// - Single location fetch on app startup
/// - Pre-fetched location available instantly for all pages
/// - No waiting for location when navigating to pages
/// - Handles permission states gracefully
class LocationProvider extends ChangeNotifier {
  Position? _currentPosition;
  Position? _lastKnownPosition;
  bool _isLoading = false;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  DateTime? _lastUpdateTime;
  
  // Consider location stale after 5 minutes
  static const Duration _staleThreshold = Duration(minutes: 5);
  // Location fetch timeout
  static const Duration _fetchTimeout = Duration(seconds: 5);
  
  Position? get currentPosition => _currentPosition;
  Position? get lastKnownPosition => _lastKnownPosition;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get permissionDenied => _permissionDenied;
  bool get hasLocation => _currentPosition != null;
  bool get isLocationStale {
    if (_lastUpdateTime == null) return true;
    return DateTime.now().difference(_lastUpdateTime!) > _staleThreshold;
  }
  
  /// Initialize location services on app startup
  /// 
  /// This method should be called once when the app starts
  /// Returns immediately if location has already been fetched recently
  Future<void> initialize() async {
    // Skip if already loading or recently fetched
    if (_isLoading || (hasLocation && !isLocationStale)) {
      return;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Check permission status using Geolocator
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        _permissionDenied = true;
        _hasPermission = false;
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      if (permission == LocationPermission.deniedForever) {
        _permissionDenied = true;
        _hasPermission = false;
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      _hasPermission = true;
      notifyListeners();
      
      // Step 1: Try to get last known position first (fast)
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          _lastKnownPosition = lastPos;
          _currentPosition = lastPos;
          _lastUpdateTime = DateTime.now();
          notifyListeners();
          debugPrint('✅ LocationProvider: Using last known position');
        }
      } catch (e) {
        debugPrint('⚠️ LocationProvider: Failed to get last known position: $e');
      }
      
      // Step 2: Get current position in background (accurate)
      // Don't await this - let it complete in background
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: _fetchTimeout,
        ),
      ).then((pos) {
        _currentPosition = pos;
        _lastUpdateTime = DateTime.now();
        _isLoading = false;
        notifyListeners();
        debugPrint('✅ LocationProvider: Got current position');
      }).catchError((e) {
        // Keep last known position if current fetch fails
        _isLoading = false;
        notifyListeners();
        debugPrint('⚠️ LocationProvider: Failed to get current position: $e');
      });
      
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('❌ LocationProvider: Error initializing: $e');
    }
  }
  
  /// Request location permission
  /// 
  /// Call this when user explicitly requests location access
  Future<bool> requestPermission() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _permissionDenied = false;
        _hasPermission = true;
        notifyListeners();
        // Re-fetch location after permission granted
        await initialize();
        return true;
      } else {
        _permissionDenied = true;
        _hasPermission = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ LocationProvider: Error requesting permission: $e');
      return false;
    }
  }
  
  /// Refresh location manually
  /// 
  /// Call this to force a location refresh
  Future<void> refreshLocation() async {
    if (!_hasPermission) {
      // Try to request permission first
      final granted = await requestPermission();
      if (!granted) return;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: _fetchTimeout,
        ),
      );
      
      _currentPosition = pos;
      _lastUpdateTime = DateTime.now();
      _isLoading = false;
      notifyListeners();
      debugPrint('✅ LocationProvider: Location refreshed');
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('❌ LocationProvider: Failed to refresh location: $e');
    }
  }
  
  /// Clear cached location (useful for testing or privacy)
  void clearLocation() {
    _currentPosition = null;
    _lastKnownPosition = null;
    _lastUpdateTime = null;
    notifyListeners();
  }
}