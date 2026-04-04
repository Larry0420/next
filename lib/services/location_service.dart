import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unified location service for route status pages
/// 
/// Provides:
/// - Permission handling for location access
/// - Last known position caching for instant availability
/// - Current position fetching with timeout
/// - User location banner state management
class LocationService {
  LocationService({required this.mounted});
  
  final bool mounted;
  
  Position? _lastPosition;
  Position? _currentPosition;
  bool _showLocationBanner = false;
  
  /// Get the last known position (cached)
  Position? get lastPosition => _lastPosition;
  
  /// Get the current position (if available)
  Position? get currentPosition => _currentPosition;
  
  /// Whether to show location banner
  bool get showLocationBanner => _showLocationBanner;
  
  /// Initialize location services
  /// 
  /// Returns true if location permission is granted, false otherwise
  Future<bool> initialize() async {
    try {
      final status = await Permission.location.status;
      if (!status.isGranted) return false;
      
      // FAST: Get last known position first
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted) {
          _lastPosition = lastPos;
          _currentPosition = lastPos;
        }
      } catch (_) {
        // Ignore failures, continue to current position fetch
      }
      
      // Show banner only if no position yet
      if (_currentPosition == null && mounted) {
        _showLocationBanner = true;
      }
      
      // ACCURATE: Get current position in background
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 5),
        ),
      );
      
      if (mounted) {
        _currentPosition = pos;
        _showLocationBanner = false;
        return true;
      }
    } catch (e) {
      if (mounted) {
        _showLocationButton = false;
      }
    }
    
    return false;
  }
  
  bool _showLocationButton = false;
  bool get showLocationButton => _showLocationButton;
  
  /// Update UI state via setState from parent
  void updateState({
    Position? currentPosition,
    Position? lastPosition,
    bool? showLocationBanner,
    bool? showLocationButton,
  }) {
    if (!mounted) return;
    
    if (currentPosition != null) _currentPosition = currentPosition;
    if (lastPosition != null) _lastPosition = lastPosition;
    if (showLocationBanner != null) _showLocationBanner = showLocationBanner!;
    if (showLocationButton != null) _showLocationButton = showLocationButton!;
  }
}