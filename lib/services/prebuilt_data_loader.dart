import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Strategy interface for loading prebuilt data
abstract class DataLoadStrategy {
  /// Load data from this source
  Future<String?> load(String assetPath);
  
  /// Check if this strategy is available
  bool isAvailable();
}

/// Load data from bundled assets (fastest, always available on mobile)
class AssetLoadStrategy implements DataLoadStrategy {
  @override
  Future<String?> load(String assetPath) async {
    try {
      return await rootBundle.loadString(assetPath);
    } catch (e) {
      return null;
    }
  }
  
  @override
  bool isAvailable() => !kIsWeb;
}

/// Load data from app documents directory (for downloaded/updated data)
class DocumentsLoadStrategy implements DataLoadStrategy {
  @override
  Future<String?> load(String assetPath) async {
    if (!isAvailable()) return null;
    
    try {
      // Get documents directory
      // Note: This requires path_provider package
      // For now, return null as we can't import path_provider here
      // In production, this would be:
      // final doc = await getApplicationDocumentsDirectory();
      // final file = File('${doc.path}/prebuilt/${basename(assetPath)}');
      // if (file.existsSync()) return await file.readAsString();
      return null;
    } catch (e) {
      return null;
    }
  }
  
  @override
  bool isAvailable() => !kIsWeb;
}

/// Load data from HTTP API (fallback for missing assets)
class ApiLoadStrategy implements DataLoadStrategy {
  final String baseUrl;
  final Duration timeout;
  
  ApiLoadStrategy({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });
  
  @override
  Future<String?> load(String assetPath) async {
    if (!isAvailable()) return null;
    
    try {
      // Note: This requires http package
      // For now, return null as we can't import http here
      // In production, this would be:
      // final url = '$baseUrl/${basename(assetPath)}';
      // final response = await http.get(Uri.parse(url)).timeout(timeout);
      // if (response.statusCode == 200) return response.body;
      return null;
    } catch (e) {
      return null;
    }
  }
  
  @override
  bool isAvailable() => true; // HTTP is always available
}

/// Unified prebuilt data loader with strategy pattern
/// 
/// Provides:
/// - Multiple fallback strategies for loading data
/// - Cached results to avoid repeated loading
/// - JSON parsing with error handling
/// - Support for different data formats
/// 
/// Usage:
/// ```dart
/// final loader = PrebuiltDataLoader();
/// 
/// // Load with default strategies
/// final data = await loader.loadJson('assets/prebuilt/ctb_route_stops.json');
/// 
/// // Load with custom strategies
/// final strategies = [
///   AssetLoadStrategy(),
///   DocumentsLoadStrategy(),
///   ApiLoadStrategy(baseUrl: 'https://example.com/prebuilt'),
/// ];
/// final data = await loader.loadJson('assets/prebuilt/data.json', strategies: strategies);
/// ```
class PrebuiltDataLoader {
  /// Default strategies to try in order
  static final defaultStrategies = <DataLoadStrategy>[
    AssetLoadStrategy(),
    DocumentsLoadStrategy(),
    // ApiLoadStrategy(baseUrl: 'https://example.com/prebuilt'),
  ];
  
  /// Cache for loaded data
  final _cache = <String, dynamic>{};
  
  /// Enable/disable caching
  final bool useCache;
  
  /// Strategies to use for loading
  final List<DataLoadStrategy> strategies;
  
  PrebuiltDataLoader({
    List<DataLoadStrategy>? strategies,
    this.useCache = true,
  }) : strategies = strategies ?? defaultStrategies;
  
  /// Load data as raw string
  /// 
  /// Parameters:
  /// - assetPath: Path to the asset file
  /// - customStrategies: Optional custom strategies to use instead of default
  /// 
  /// Returns loaded data as string, or null if all strategies fail
  Future<String?> loadString(
    String assetPath, {
    List<DataLoadStrategy>? customStrategies,
  }) async {
    // Check cache first
    if (useCache && _cache.containsKey(assetPath)) {
      final cached = _cache[assetPath];
      if (cached is String) return cached;
    }
    
    // Try each strategy in order
    final strategiesToUse = customStrategies ?? strategies;
    for (final strategy in strategiesToUse) {
      if (!strategy.isAvailable()) continue;
      
      try {
        final data = await strategy.load(assetPath);
        if (data != null && data.isNotEmpty) {
          // Cache the result
          if (useCache) {
            _cache[assetPath] = data;
          }
          return data;
        }
      } catch (e) {
        // Try next strategy
        continue;
      }
    }
    
    return null;
  }
  
  /// Load data as JSON
  /// 
  /// Parameters:
  /// - assetPath: Path to the asset file
  /// - customStrategies: Optional custom strategies to use instead of default
  /// 
  /// Returns parsed JSON data, or null if loading or parsing fails
  Future<dynamic> loadJson(
    String assetPath, {
    List<DataLoadStrategy>? customStrategies,
  }) async {
    final data = await loadString(assetPath, customStrategies: customStrategies);
    if (data == null) return null;
    
    try {
      return jsonDecode(data);
    } catch (e) {
      return null;
    }
  }
  
  /// Load data as list
  /// 
  /// Parameters:
  /// - assetPath: Path to the asset file
  /// - customStrategies: Optional custom strategies to use instead of default
  /// 
  /// Returns parsed list, or empty list if loading or parsing fails
  Future<List<dynamic>> loadList(
    String assetPath, {
    List<DataLoadStrategy>? customStrategies,
  }) async {
    final data = await loadJson(assetPath, customStrategies: customStrategies);
    if (data is List) return data;
    return [];
  }
  
  /// Load data as map
  /// 
  /// Parameters:
  /// - assetPath: Path to the asset file
  /// - customStrategies: Optional custom strategies to use instead of default
  /// 
  /// Returns parsed map, or empty map if loading or parsing fails
  Future<Map<String, dynamic>> loadMap(
    String assetPath, {
    List<DataLoadStrategy>? customStrategies,
  }) async {
    final data = await loadJson(assetPath, customStrategies: customStrategies);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }
  
  /// Clear cache for specific asset or all assets
  void clearCache([String? assetPath]) {
    if (assetPath != null) {
      _cache.remove(assetPath);
    } else {
      _cache.clear();
    }
  }
  
  /// Check if data is cached
  bool isCached(String assetPath) {
    return _cache.containsKey(assetPath);
  }
  
  /// Get cache size (number of cached items)
  int get cacheSize => _cache.length;
}

/// Company-specific data loader helpers
class CompanyDataLoader {
  static final _loaders = <String, PrebuiltDataLoader>{};
  
  /// Get loader for specific company
  static PrebuiltDataLoader getLoader(String company) {
    return _loaders.putIfAbsent(
      company,
      () => PrebuiltDataLoader(),
    );
  }
  
  /// Load route stops for company
  static Future<Map<String, dynamic>> loadRouteStops(String company) async {
    final loader = getLoader(company);
    final assetPath = 'assets/prebuilt/${company.toLowerCase()}_route_stops.json';
    return await loader.loadMap(assetPath);
  }
  
  /// Load route metadata for company
  static Future<Map<String, dynamic>> loadRouteMetadata(String company) async {
    final loader = getLoader(company);
    final assetPath = 'assets/prebuilt/${company.toLowerCase()}_routes.json';
    return await loader.loadMap(assetPath);
  }
  
  /// Load stop metadata for company
  static Future<Map<String, dynamic>> loadStopMetadata(String company) async {
    final loader = getLoader(company);
    final assetPath = 'assets/prebuilt/${company.toLowerCase()}_stops.json';
    return await loader.loadMap(assetPath);
  }
  
  /// Clear cache for company
  static void clearCompanyCache(String company) {
    _loaders[company]?.clearCache();
  }
  
  /// Clear all caches
  static void clearAllCaches() {
    for (final loader in _loaders.values) {
      loader.clearCache();
    }
  }
}