import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// MTR Bus API Client
/// 
/// Provides access to MTR Bus ETA data from the official MTR Bus API
/// API Endpoint: https://rt.data.gov.hk/v1/transport/mtr/bus/getSchedule
/// Method: POST
/// 
/// Note: MTR Bus API returns all stops for a route in a single response
/// unlike other bus APIs that require per-stop queries
class MtrBus {
  static const String _baseUrl = 'https://rt.data.gov.hk/v1/transport/mtr/bus/getSchedule';
  static const String _cacheKeyPrefix = 'mtr_bus_cache_';
  static const Duration _cacheDuration = Duration(hours: 24);
  
  /// List of official MTR Bus routes
  static const List<String> _mtrBusRoutes = [
    '506', 'K12', 'K14', 'K17', 'K18', 'K51', 'K51A', 'K52', 'K52A', 
    'K53', 'K54', 'K58', 'K65', 'K65A', 'K66', 'K68', 'K73', 'K74', 
    'K75A', 'K75P', 'K76'
  ];
  
  /// Check if a route number is an MTR Bus route
  static bool isMtrBusRoute(String route) {
    return _mtrBusRoutes.contains(route.toUpperCase());
  }
  
  /// Fetch schedule for a specific route
  /// 
  /// Returns a map containing:
  /// - 'busStop': Array of bus stops with ETA data
  /// - 'routeName': Route number
  /// - 'routeStatus': Route status
  /// - 'footerRemarks': Footer remarks
  static Future<Map<String, dynamic>> fetchSchedule(
    String route,
    String language, {
    bool useCache = true,
  }) async {
    // Check cache first
    if (useCache) {
      final cached = await _getCachedSchedule(route, language);
      if (cached != null) {
        return cached;
      }
    }
    
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'language': language,
          'routeName': route.toUpperCase(),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Cache the response
        await _cacheSchedule(route, language, data);
        
        return data;
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit exceeded for MTR Bus API');
      } else if (response.statusCode == 500) {
        throw Exception('MTR Bus API server error');
      } else {
        throw Exception('MTR Bus API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch MTR Bus schedule: $e');
    }
  }
  
  /// Extract stops from schedule response
  static List<Map<String, dynamic>> extractStops(Map<String, dynamic> schedule) {
    if (!schedule.containsKey('busStop')) {
      return [];
    }
    
    final busStops = schedule['busStop'];
    if (busStops is! List) {
      return [];
    }
    
    return busStops.cast<Map<String, dynamic>>();
  }
  
  /// Get stop sequence from stop ID
  /// 
  /// Stop ID format: {route}-{direction}{sequence}
  /// Example: K12-D010 → direction=D, sequence=010 → seq=10
  static int getStopSequence(String stopId) {
    final parts = stopId.split('-');
    if (parts.length < 2) return 0;
    
    final directionAndSeq = parts[1];
    if (directionAndSeq.isEmpty) return 0;
    
    // Remove direction prefix (D or U)
    final seqStr = directionAndSeq.substring(1);
    return int.tryParse(seqStr) ?? 0;
  }
  
  /// Get direction from stop ID
  /// 
  /// Returns: 'O' for downbound (D), 'I' for upbound (U)
  static String getDirectionFromStopId(String stopId) {
    final parts = stopId.split('-');
    if (parts.length < 2) return 'O';
    
    final directionAndSeq = parts[1];
    if (directionAndSeq.isEmpty) return 'O';
    
    final direction = directionAndSeq[0].toUpperCase();
    return direction == 'D' ? 'O' : 'I'; // D=downbound=O, U=upbound=I
  }
  
  /// Cache schedule data
  static Future<void> _cacheSchedule(
    String route,
    String language,
    Map<String, dynamic> data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix${route}_$language';
      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      };
      await prefs.setString(cacheKey, jsonEncode(cacheData));
    } catch (e) {
      // Silently fail on cache error
    }
  }
  
  /// Get cached schedule data
  static Future<Map<String, dynamic>?> _getCachedSchedule(
    String route,
    String language,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix${route}_$language';
      final cacheString = prefs.getString(cacheKey);
      
      if (cacheString == null) return null;
      
      final cacheData = jsonDecode(cacheString) as Map<String, dynamic>;
      final timestamp = cacheData['timestamp'] as int;
      final data = cacheData['data'] as Map<String, dynamic>;
      
      // Check if cache is still valid
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (cacheAge > _cacheDuration.inMilliseconds) {
        // Cache expired, remove it
        await prefs.remove(cacheKey);
        return null;
      }
      
      return data;
    } catch (e) {
      // Silently fail on cache error
      return null;
    }
  }
  
  /// Clear all MTR Bus cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      // Silently fail on cache error
    }
  }
  
  /// Get list of all MTR Bus routes
  static List<String> getMtrBusRoutes() {
    return List.from(_mtrBusRoutes);
  }
}