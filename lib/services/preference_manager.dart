import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified preference manager for route status pages
/// 
/// Provides:
/// - Map view preference storage and retrieval
/// - Language preference storage
/// - Theme preference storage
/// - Type-safe preference access with caching
class PreferenceManager {
  static const String _keyMapView = 'map_view_pref';
  static const String _keyLanguage = 'language_pref';
  static const String _keyTheme = 'theme_pref';
  
  SharedPreferences? _prefs;
  bool? _cachedMapViewPref;
  bool? _cachedThemePref;
  
  /// Initialize the preference manager
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get map view preference
  /// Returns true if map view is preferred, false otherwise
  /// Defaults to true if not set
  Future<bool> getMapViewPreference() async {
    if (_prefs == null) await initialize();
    return _cachedMapViewPref ??= _prefs?.getBool(_keyMapView) ?? true;
  }
  
  /// Set map view preference
  Future<void> setMapViewPreference(bool value) async {
    if (_prefs == null) await initialize();
    _cachedMapViewPref = value;
    await _prefs?.setBool(_keyMapView, value);
  }
  
  /// Get language preference
  /// Returns true if English is preferred, false for Traditional Chinese
  /// Defaults to true if not set
  Future<bool> getLanguagePreference() async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool(_keyLanguage) ?? true;
  }
  
  /// Set language preference
  Future<void> setLanguagePreference(bool isEnglish) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool(_keyLanguage, isEnglish);
  }
  
  /// Get theme preference
  /// Returns true if dark mode is preferred, false for light mode
  /// Defaults to false if not set
  Future<bool> getThemePreference() async {
    if (_prefs == null) await initialize();
    return _cachedThemePref ??= _prefs?.getBool(_keyTheme) ?? false;
  }
  
  /// Set theme preference
  Future<void> setThemePreference(bool isDark) async {
    if (_prefs == null) await initialize();
    _cachedThemePref = isDark;
    await _prefs?.setBool(_keyTheme, isDark);
  }
  
  /// Clear all cached preferences
  void clearCache() {
    _cachedMapViewPref = null;
    _cachedThemePref = null;
  }
  
  /// Clear all preferences
  Future<void> clearAll() async {
    if (_prefs == null) await initialize();
    await _prefs?.clear();
    clearCache();
  }
}