import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'ui_constants.dart';

// Import LanguageProvider and DeveloperSettingsProvider from main.dart
import 'main.dart' show LanguageProvider, DeveloperSettingsProvider;

// ========================= MTR API Service =========================

class MtrApiService {
  // MTR Next Train API endpoint
  static const String _baseUrl = 'https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php';
  
  // ===== CACHING LAYER FOR POOR NETWORK CONDITIONS =====
  
  // In-memory cache with TTL
  static final Map<String, _CachedSchedule> _memoryCache = {};
  static const Duration _memoryCacheTTL = Duration(seconds: 45); // Stale after 45s
  static const Duration _memoryCacheMaxAge = Duration(minutes: 5); // Expire after 5min
  
  // Persistent cache key prefix
  static const String _persistentCachePrefix = 'mtr_schedule_cache_';
  static const String _cacheVersionKey = 'mtr_cache_version';
  static const int _currentCacheVersion = 1;
  
  // Request deduplication - prevent duplicate simultaneous requests
  static final Map<String, Future<MtrScheduleResponse>> _inflightRequests = {};
  
  // Network retry configuration
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  
  /// Fetch schedule with intelligent caching and retry logic
  /// - Uses in-memory cache if available and fresh
  /// - Falls back to persistent cache if network fails
  /// - Implements exponential backoff with jitter
  /// - Deduplicates simultaneous requests
  Future<MtrScheduleResponse> fetchSchedule(
    String lineCode, 
    String stationCode, {
    bool forceRefresh = false,
    bool allowStale = true, // Allow serving stale cache during network issues
  }) async {
    final cacheKey = _getCacheKey(lineCode, stationCode);
    
    // Check if request is already in-flight (deduplication)
    if (!forceRefresh && _inflightRequests.containsKey(cacheKey)) {
      debugPrint('MTR API: Reusing in-flight request for $cacheKey');
      return _inflightRequests[cacheKey]!;
    }
    
    // Check memory cache first (fast path)
    if (!forceRefresh) {
      final cached = _memoryCache[cacheKey];
      if (cached != null && !cached.isExpired) {
        if (cached.isFresh) {
          debugPrint('MTR API: Serving fresh cache for $cacheKey');
          return cached.response;
        } else if (allowStale) {
          // Stale-while-revalidate: serve stale, fetch in background
          debugPrint('MTR API: Serving stale cache, revalidating in background for $cacheKey');
          unawaited(_backgroundRefresh(lineCode, stationCode, cacheKey));
          return cached.response;
        }
      }
    }
    
    // Create and track the fetch future
    final fetchFuture = _fetchWithRetryAndCache(lineCode, stationCode, cacheKey, forceRefresh, allowStale);
    _inflightRequests[cacheKey] = fetchFuture;
    
    try {
      return await fetchFuture;
    } finally {
      _inflightRequests.remove(cacheKey);
    }
  }
  
  /// Background refresh without blocking caller
  Future<void> _backgroundRefresh(String lineCode, String stationCode, String cacheKey) async {
    try {
      await _fetchWithRetryAndCache(lineCode, stationCode, cacheKey, true, false);
    } catch (e) {
      debugPrint('MTR API: Background refresh failed for $cacheKey: $e');
    }
  }
  
  /// Core fetch logic with retry, caching, and fallback
  Future<MtrScheduleResponse> _fetchWithRetryAndCache(
    String lineCode,
    String stationCode,
    String cacheKey,
    bool forceRefresh,
    bool allowStale,
  ) async {
    Exception? lastError;
    
    // Try fetching with exponential backoff
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await _fetchFromNetwork(lineCode, stationCode, attempt);
        
        // Success! Cache it
        await _cacheResponse(cacheKey, response);
        return response;
        
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('MTR API: Attempt ${attempt + 1}/$_maxRetries failed: $e');
        
        // Don't retry on last attempt
        if (attempt < _maxRetries - 1) {
          await _delayWithJitter(attempt);
        }
      }
    }
    
    // All retries failed - try persistent cache
    debugPrint('MTR API: All retries failed, checking persistent cache for $cacheKey');
    final cachedResponse = await _loadFromPersistentCache(cacheKey);
    if (cachedResponse != null) {
      debugPrint('MTR API: Serving from persistent cache (network unavailable)');
      // Update memory cache too
      _memoryCache[cacheKey] = _CachedSchedule(
        response: cachedResponse,
        timestamp: DateTime.now(),
        isFromPersistentCache: true,
      );
      return cachedResponse;
    }
    
    // No cache available, throw the last error
    throw lastError ?? Exception('MTR API: Failed to fetch schedule');
  }
  
  /// Fetch from network with adaptive timeout
  Future<MtrScheduleResponse> _fetchFromNetwork(String lineCode, String stationCode, int attemptNumber) async {
    final url = Uri.parse('$_baseUrl?line=$lineCode&sta=$stationCode');
    
    // Adaptive timeout: increase on retries
    final timeout = Duration(seconds: 10 + (attemptNumber * 5));
    
    debugPrint('MTR API: Fetching from network (attempt ${attemptNumber + 1}, timeout: ${timeout.inSeconds}s)');
    
    final response = await http.get(url).timeout(timeout);
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return MtrScheduleResponse.fromJson(json);
    } else {
      throw Exception('MTR API Error: HTTP ${response.statusCode}');
    }
  }
  
  /// Exponential backoff with jitter to avoid thundering herd
  Future<void> _delayWithJitter(int attemptNumber) async {
    final baseDelay = _baseRetryDelay.inMilliseconds;
    final exponentialDelay = baseDelay * (1 << attemptNumber); // 2^attempt
    final jitter = (exponentialDelay * 0.3 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).round();
    final totalDelay = exponentialDelay + jitter;
    
    debugPrint('MTR API: Waiting ${totalDelay}ms before retry ${attemptNumber + 2}');
    await Future.delayed(Duration(milliseconds: totalDelay));
  }
  
  /// Cache response in both memory and persistent storage
  Future<void> _cacheResponse(String cacheKey, MtrScheduleResponse response) async {
    // Memory cache
    _memoryCache[cacheKey] = _CachedSchedule(
      response: response,
      timestamp: DateTime.now(),
    );
    
    // Persistent cache (async, don't wait)
    unawaited(_saveToPersistentCache(cacheKey, response));
  }
  
  /// Save to SharedPreferences for offline support
  Future<void> _saveToPersistentCache(String cacheKey, MtrScheduleResponse response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Ensure cache version is current
      final version = prefs.getInt(_cacheVersionKey) ?? 0;
      if (version != _currentCacheVersion) {
        await _clearPersistentCache(prefs);
        await prefs.setInt(_cacheVersionKey, _currentCacheVersion);
      }
      
      // Save response as JSON
      final json = _scheduleToJson(response);
      await prefs.setString('$_persistentCachePrefix$cacheKey', jsonEncode(json));
      await prefs.setInt('${_persistentCachePrefix}${cacheKey}_timestamp', DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('MTR API: Cached to persistent storage: $cacheKey');
    } catch (e) {
      debugPrint('MTR API: Failed to save to persistent cache: $e');
    }
  }
  
  /// Load from SharedPreferences
  Future<MtrScheduleResponse?> _loadFromPersistentCache(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final jsonStr = prefs.getString('$_persistentCachePrefix$cacheKey');
      if (jsonStr == null) return null;
      
      final timestamp = prefs.getInt('${_persistentCachePrefix}${cacheKey}_timestamp');
      if (timestamp != null) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        // Don't use cache older than 30 minutes
        if (age > Duration(minutes: 30).inMilliseconds) {
          debugPrint('MTR API: Persistent cache too old (${Duration(milliseconds: age).inMinutes}min)');
          return null;
        }
      }
      
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _scheduleFromJson(json);
    } catch (e) {
      debugPrint('MTR API: Failed to load from persistent cache: $e');
      return null;
    }
  }
  
  /// Clear old persistent cache
  Future<void> _clearPersistentCache(SharedPreferences prefs) async {
    final keys = prefs.getKeys().where((k) => k.startsWith(_persistentCachePrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
    debugPrint('MTR API: Cleared persistent cache');
  }
  
  /// Clear all caches (memory + persistent)
  Future<void> clearAllCaches() async {
    _memoryCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await _clearPersistentCache(prefs);
    debugPrint('MTR API: Cleared all caches');
  }
  
  String _getCacheKey(String lineCode, String stationCode) => '${lineCode}_$stationCode';
  
  /// Convert MtrScheduleResponse to JSON for persistent storage
  Map<String, dynamic> _scheduleToJson(MtrScheduleResponse response) {
    return {
      'status': response.status,
      'message': response.message,
      'lineStationKey': response.lineStationKey,
      'currentTime': response.currentTime?.toIso8601String(),
      'systemTime': response.systemTime?.toIso8601String(),
      'isDelay': response.isDelay,
      'directionTrains': response.directionTrains.map((key, trains) => MapEntry(
        key,
        trains.map((train) => {
          'dest': train.destination,
          'plat': train.platform,
          'time': train.time,
          'ttnt': train.timeInMinutes,
          'seq': train.sequence,
        }).toList(),
      )),
    };
  }
  
  /// Convert JSON back to MtrScheduleResponse
  MtrScheduleResponse _scheduleFromJson(Map<String, dynamic> json) {
    return MtrScheduleResponse(
      status: json['status'] as int,
      message: json['message'] as String,
      lineStationKey: json['lineStationKey'] as String?,
      currentTime: json['currentTime'] != null ? DateTime.parse(json['currentTime']) : null,
      systemTime: json['systemTime'] != null ? DateTime.parse(json['systemTime']) : null,
      isDelay: json['isDelay'] as bool? ?? false,
      directionTrains: (json['directionTrains'] as Map<String, dynamic>).map((key, trains) => MapEntry(
        key,
        (trains as List).map((train) => MtrTrainInfo(
          destination: train['dest'] as String,
          platform: train['plat'] as String,
          time: train['time'] as String,
          timeInMinutes: train['ttnt'] as int?,
          sequence: train['seq'] as int?,
        )).toList(),
      )),
    );
  }
}

/// Cached schedule with metadata
class _CachedSchedule {
  final MtrScheduleResponse response;
  final DateTime timestamp;
  final bool isFromPersistentCache;
  
  _CachedSchedule({
    required this.response,
    required this.timestamp,
    this.isFromPersistentCache = false,
  });
  
  /// Cache is fresh if within TTL
  bool get isFresh => DateTime.now().difference(timestamp) < MtrApiService._memoryCacheTTL;
  
  /// Cache is expired if beyond max age
  bool get isExpired => DateTime.now().difference(timestamp) > MtrApiService._memoryCacheMaxAge;
}

/// Helper to fire-and-forget futures
void unawaited(Future<void> future) {
  future.catchError((e) => debugPrint('Unawaited error: $e'));
}

// ========================= MTR Data Models =========================

class MtrLine {
  final String lineCode;
  final String nameEn;
  final String nameZh;
  final Color lineColor;
  final List<MtrStation> stations;
  final Map<String, List<String>> directionTermini;
  
  MtrLine({
    required this.lineCode,
    required this.nameEn,
    required this.nameZh,
    required this.lineColor,
    required this.stations,
    required this.directionTermini,
  });
  
  String displayName(bool isEnglish) => isEnglish ? nameEn : nameZh;

  List<String> directionCodes(String directionKey) {
    return directionTermini[directionKey.toUpperCase()] ?? const [];
  }

  List<String> directionDisplayNames(String directionKey, StationNameResolver resolver) {
    final codes = directionCodes(directionKey);
    if (codes.isEmpty) return const [];
    return codes.map(resolver.combinedName).toList();
  }

  List<String> directionDisplayNamesLocalized(String directionKey, StationNameResolver resolver, bool isEnglish) {
    final codes = directionCodes(directionKey);
    if (codes.isEmpty) return const [];
    return codes.map((code) => isEnglish ? resolver.nameEn(code) : resolver.nameZh(code)).toList();
  }
}

class MtrStation {
  final String stationCode;
  final String nameEn;
  final String nameZh;
  final List<String> interchangeLines; // List of line codes
  
  MtrStation({
    required this.stationCode,
    required this.nameEn,
    required this.nameZh,
    this.interchangeLines = const [],
  });
  
  String displayName(bool isEnglish) => isEnglish ? nameEn : nameZh;
  bool get isInterchange => interchangeLines.isNotEmpty;
}

class MtrScheduleResponse {
  final int status;
  final String message;
  final String? lineStationKey;
  final DateTime? currentTime;
  final DateTime? systemTime; // Parsed from 'sys_time' if available
  final Map<String, List<MtrTrainInfo>> directionTrains;
  final bool isDelay; // Parsed from API 'isdelay' (Y/N)
  
  MtrScheduleResponse({
    required this.status,
    required this.message,
    required this.lineStationKey,
    required this.currentTime,
    required this.systemTime,
    required this.directionTrains,
    this.isDelay = false,
  });
  
  factory MtrScheduleResponse.fromJson(Map<String, dynamic> json) {
    final statusRaw = json['status'];
    final status = statusRaw is int ? statusRaw : int.tryParse('$statusRaw') ?? 0;
    final message = json['message']?.toString() ?? '';
  String? lineStationKey;
  DateTime? parsedTime;
  DateTime? parsedSysTime;
  final directionTrains = <String, List<MtrTrainInfo>>{};
  bool isDelay = false;

    final data = json['data'];
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        lineStationKey ??= entry.key;
        final stationData = entry.value;
        if (stationData is Map<String, dynamic>) {
          final currTime = stationData['curr_time']?.toString();
          parsedTime ??= _parseTime(currTime);
          final sysTime = stationData['sys_time']?.toString();
          parsedSysTime ??= _parseTime(sysTime);
          final delayRaw = stationData['isdelay']?.toString();
          if (delayRaw != null && delayRaw.toUpperCase() == 'Y') {
            isDelay = true;
          }
          for (final dirEntry in stationData.entries) {
            final dirKey = dirEntry.key;
            if (dirKey == 'curr_time' || dirKey == 'sys_time' || dirKey == 'tcg') {
              continue;
            }
            final trainListRaw = dirEntry.value;
            if (trainListRaw is List) {
              final trains = <MtrTrainInfo>[];
              for (final train in trainListRaw) {
                if (train is Map) {
                  trains.add(MtrTrainInfo.fromJson(train.cast<String, dynamic>()));
                }
              }
              directionTrains[dirKey] = trains;
            }
          }
        }
      }
    }

    return MtrScheduleResponse(
      status: status,
      message: message,
      lineStationKey: lineStationKey,
      currentTime: parsedTime,
      systemTime: parsedSysTime,
      directionTrains: directionTrains,
      isDelay: isDelay,
    );
  }
  
  static DateTime? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(s.trim());
      if (match == null) return null;
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }
}

class MtrTrainInfo {
  final String destination;
  final String platform;
  final String time;
  final int? timeInMinutes; // ttnt: Time to Next Train in minutes
  final int? sequence;
  final String? timeType; // Optional: "A" = Arrival, "D" = Departure (EAL only)
  final String? route; // Optional: "" = Normal, "RAC" = Via Racecourse (EAL only)
  
  MtrTrainInfo({
    required this.destination,
    required this.platform,
    required this.time,
    this.timeInMinutes,
    this.sequence,
    this.timeType,
    this.route,
  });
  
  factory MtrTrainInfo.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '');
    }

    return MtrTrainInfo(
      destination: json['dest'] as String? ?? '',
      platform: json['plat'] as String? ?? '',
      time: json['time'] as String? ?? '',
      timeInMinutes: parseInt(json['ttnt']),
      sequence: parseInt(json['seq']),
      timeType: json['timetype'] as String?,
      route: json['route'] as String?,
    );
  }
  
  /// Check if train is arriving at this station (based on timetype field)
  /// For terminus stations, timetype "A" means arriving, "D" means departing
  bool get isArriving {
    // Check timetype field (API standard for EAL, may apply to other lines)
    if (timeType != null) {
      return timeType!.toUpperCase() == 'A';
    }
    
    // Fallback to time field analysis
    final timeUpper = time.toUpperCase();
    // Check for 'ARR' status from API
    if (timeUpper == 'ARR' || timeUpper.contains('ARRIVING')) return true;
    // Check if time is dash (arriving soon indicator)
    if (time == '-') return true;
    
    return false;
  }
  
  /// Check if train is departing from this station (based on timetype field)
  /// For terminus stations, this is important to distinguish from through trains
  bool get isDeparting {
    // Check timetype field (API standard for EAL, may apply to other lines)
    if (timeType != null) {
      return timeType!.toUpperCase() == 'D';
    }
    
    // Fallback to time field analysis
    final timeUpper = time.toUpperCase();
    return timeUpper == 'DEP' || timeUpper.contains('DEPARTING');
  }
  
  /// Check if train is at platform (timeInMinutes <= 0)
  bool get isAtPlatform => timeInMinutes != null && timeInMinutes! <= 0;
  
  /// Display time with English localization (deprecated - use displayTimeLocalized)
  @Deprecated('Use displayTimeLocalized(isEnglish) instead')
  String get displayTime => displayTimeLocalized(true);
  
  /// Display time with proper localization support
  /// Handles terminus stations and through trains correctly using timetype field
  /// According to MTR API: 
  /// - 'time' field contains actual arrival/departure time
  /// - 'ttnt' (timeInMinutes) contains minutes until arrival/departure
  ///   - ttnt = 2 or less: Train is arriving
  ///   - ttnt = 0: Through trains show "Departing" (arrived and departing)
  ///   - ttnt = 0 + timetype='A': Terminus arrival (show "Arriving")
  ///   - ttnt = 0 + timetype='D': Terminus departure (show "Departing")
  /// - 'timetype' field: "A" = Arrival, "D" = Departure (EAL terminus stations)
  String displayTimeLocalized(bool isEnglish) {
    // Priority 1: Check for special status codes from API
    final timeUpper = time.toUpperCase();
    
    // Check for explicit status codes
    if (timeUpper == 'ARR' || time == '-') {
      return isEnglish ? 'Arriving' : '即將到達';
    }
    if (timeUpper == 'DEP') {
      return isEnglish ? 'Departing' : '正在離開';
    }
    
    // Priority 2: Use timeInMinutes (ttnt) if available
    if (timeInMinutes != null) {
      final minutes = timeInMinutes!;
      
      // ttnt = 0: Train is at platform
      if (minutes <= 0) {
        // For EAL terminus stations with timetype field
        if (timeType != null) {
          if (timeType!.toUpperCase() == 'A') {
            // Terminus arrival - train just arrived at terminus
            return isEnglish ? 'Arriving' : '即將到達';
          } else if (timeType!.toUpperCase() == 'D') {
            // Terminus departure - train departing from terminus
            return isEnglish ? 'Departing' : '正在離開';
          }
        }
        
        // For through trains (no timetype field)
        // Train has arrived and is departing to next station
        return isEnglish ? 'Departing' : '正在離開';
      }
      
      // ttnt = 1-2: Train is arriving
      if (minutes <= 2) {
        return isEnglish ? 'Arriving' : '即將到達';
      }
      
      // ttnt > 2: Show minutes
      return isEnglish ? '$minutes mins' : '$minutes 分鐘';
    }
    
    // Priority 3: Fallback to time field (actual time string from API)
    if (time.isEmpty) {
      return isEnglish ? 'No data' : '無資料';
    }
    
    // Check if time contains 'ARRIVING' text
    if (timeUpper.contains('ARRIVING')) {
      return isEnglish ? 'Arriving' : '即將到達';
    }
    
    // Return the actual time string from API (e.g., "14:30:00")
    return time;
  }

  /// Check if train is due soon (within 1 minute or arriving)
  bool get isDueSoon {
    if (isDeparting || isArriving) return true;
    if (timeInMinutes != null) return timeInMinutes! <= 1;
    return false;
  }

  /// ETA description with localization support
  String etaDescriptionLocalized(bool isEnglish) {
    return displayTimeLocalized(isEnglish);
  }
  
  /// ETA description (deprecated - use etaDescriptionLocalized)
  @Deprecated('Use etaDescriptionLocalized(isEnglish) instead')
  String get etaDescription => etaDescriptionLocalized(true);

  String displayDestination(StationNameResolver resolver, {bool isEnglish = true}) {
    if (destination.isEmpty) return isEnglish ? 'Destination TBC' : '目的地待定';
    if (resolver.hasCode(destination)) {
      return isEnglish ? resolver.nameEn(destination) : resolver.nameZh(destination);
    }
    return destination;
  }
}

// ========================= Metadata & Resolvers =========================

class _LineMetadata {
  final String nameEn;
  final String nameZh;
  final Color color;
  const _LineMetadata(this.nameEn, this.nameZh, this.color);
}

class _StationName {
  final String en;
  final String zh;
  const _StationName(this.en, this.zh);
}

class StationNameResolver {
  const StationNameResolver();

  static const Map<String, _StationName> _stationNames = {
    'ADM': _StationName('Admiralty', '金鐘'),
    'AIR': _StationName('Airport', '機場'),
    'AUS': _StationName('Austin', '柯士甸'),
    'AWE': _StationName('AsiaWorld-Expo', '博覽館'),
    'CAB': _StationName('Causeway Bay', '銅鑼灣'),
    'CEN': _StationName('Central', '中環'),
    'CHH': _StationName('Choi Hung', '彩虹'),
    'CHW': _StationName('Chai Wan', '柴灣'),
    'CKT': _StationName('Che Kung Temple', '車公廟'),
    'CIO': _StationName('City One', '第一城'),
    'CSW': _StationName('Cheung Sha Wan', '長沙灣'),
    'DIH': _StationName('Diamond Hill', '鑽石山'),
    'DIS': _StationName('Disneyland Resort', '迪士尼'),
    'ETS': _StationName('East Tsim Sha Tsui', '尖東'),
    'EXC': _StationName('Exhibition Centre', '會展'),
    'FAN': _StationName('Fanling', '粉嶺'),
    'FOH': _StationName('Fortress Hill', '炮台山'),
    'FOT': _StationName('Fo Tan', '火炭'),
    'HAH': _StationName('Hang Hau', '坑口'),
    'HEO': _StationName('Heng On', '恆安'),
    'HFC': _StationName('Heng Fa Chuen', '杏花邨'),
    'HIK': _StationName('Hin Keng', '顯徑'),
    'HKU': _StationName('HKU', '香港大學'),
    'HOK': _StationName('Hong Kong', '香港'),
    'HOM': _StationName('Ho Man Tin', '何文田'),
    'HUH': _StationName('Hung Hom', '紅磡'),
    'JOR': _StationName('Jordan', '佐敦'),
    'KAT': _StationName('Kai Tak', '啟德'),
    'KET': _StationName('Kennedy Town', '堅尼地城'),
    'KOB': _StationName('Kowloon Bay', '九龍灣'),
    'KOT': _StationName('Kowloon Tong', '九龍塘'),
    'KOW': _StationName('Kowloon', '九龍'),
    'KSR': _StationName('Kam Sheung Road', '錦上路'),
    'KWF': _StationName('Kwai Fong', '葵芳'),
    'KWH': _StationName('Kwai Hing', '葵興'),
    'KWT': _StationName('Kwun Tong', '觀塘'),
    'LAK': _StationName('Lai King', '荔景'),
    'LCK': _StationName('Lai Chi Kok', '荔枝角'),
    'LAT': _StationName('Lam Tin', '藍田'),
    'LET': _StationName('Lei Tung', '利東'),
    'LHP': _StationName('LOHAS Park', '康城'),
    'LMC': _StationName('Lok Ma Chau', '落馬洲'),
    'LOF': _StationName('Lok Fu', '樂富'),
    'LOP': _StationName('Long Ping', '朗屏'),
    'LOW': _StationName('Lo Wu', '羅湖'),
    'MEF': _StationName('Mei Foo', '美孚'),
    'MKK': _StationName('Mong Kok East', '旺角東'),
    'MOK': _StationName('Mong Kok', '旺角'),
    'MOS': _StationName('Ma On Shan', '馬鞍山'),
    'NAC': _StationName('Nam Cheong', '南昌'),
    'NOP': _StationName('North Point', '北角'),
    'NTK': _StationName('Ngau Tau Kok', '牛頭角'),
    'OCP': _StationName('Ocean Park', '海洋公園'),
    'OLY': _StationName('Olympic', '奧運'),
    'POA': _StationName('Po Lam', '寶琳'),
    'PRE': _StationName('Prince Edward', '太子'),
    'QUB': _StationName('Quarry Bay', '鰂魚涌'),
    'RAC': _StationName('Racecourse', '馬場'),
    'SHM': _StationName('Shek Mun', '石門'),
    'SHS': _StationName('Sheung Shui', '上水'),
    'SHW': _StationName('Sheung Wan', '上環'),
    'SIH': _StationName('Siu Hong', '兆康'),
    'SKM': _StationName('Shek Kip Mei', '石硤尾'),
    'SKW': _StationName('Shau Kei Wan', '筲箕灣'),
    'SOH': _StationName('South Horizons', '海怡半島'),
    'SSP': _StationName('Sham Shui Po', '深水埗'),
    'STW': _StationName('Sha Tin Wai', '沙田圍'),
    'SUW': _StationName('Sung Wong Toi', '宋皇臺'),
    'SUN': _StationName('Sunny Bay', '欣澳'),
    'SWH': _StationName('Sai Wan Ho', '西灣河'),
    'SHT': _StationName('Sha Tin', '沙田'),
    'SYP': _StationName('Sai Ying Pun', '西營盤'),
    'TAK': _StationName('Tai Koo', '太古'),
    'TAP': _StationName('Tai Po Market', '大埔墟'),
    'TAW': _StationName('Tai Wai', '大圍'),
    'TIH': _StationName('Tin Hau', '天后'),
    'TIK': _StationName('Tiu Keng Leng', '調景嶺'),
    'TIS': _StationName('Tin Shui Wai', '天水圍'),
    'TKO': _StationName('Tseung Kwan O', '將軍澳'),
    'TKW': _StationName('To Kwa Wan', '土瓜灣'),
    'TSH': _StationName('Tai Shui Hang', '大水坑'),
    'TST': _StationName('Tsim Sha Tsui', '尖沙咀'),
    'TSW': _StationName('Tsuen Wan', '荃灣'),
    'TSY': _StationName('Tsing Yi', '青衣'),
    'TUC': _StationName('Tung Chung', '東涌'),
    'TUM': _StationName('Tuen Mun', '屯門'),
    'TWH': _StationName('Tai Wo Hau', '大窩口'),
    'TWO': _StationName('Tai Wo', '太和'),
    'TWW': _StationName('Tsuen Wan West', '荃灣西'),
    'UNI': _StationName('University', '大學'),
    'WAC': _StationName('Wan Chai', '灣仔'),
    'WCH': _StationName('Wong Chuk Hang', '黃竹坑'),
    'WHA': _StationName('Whampoa', '黃埔'),
    'WKS': _StationName('Wu Kai Sha', '烏溪沙'),
    'WTS': _StationName('Wong Tai Sin', '黃大仙'),
    'YAT': _StationName('Yau Tong', '油塘'),
    'YMT': _StationName('Yau Ma Tei', '油麻地'),
    'YUL': _StationName('Yuen Long', '元朗'),
  };

  bool hasCode(String code) => _stationNames.containsKey(code.toUpperCase());

  String nameEn(String code) => _stationNames[code.toUpperCase()]?.en ?? code;

  String nameZh(String code) => _stationNames[code.toUpperCase()]?.zh ?? code;

  String combinedName(String code) {
    final en = nameEn(code);
    final zh = nameZh(code);
    if (zh == code || zh == en) return en;
    return '$en $zh';
  }

  String bestLabel(String code) => combinedName(code);
}

const StationNameResolver stationNameResolver = StationNameResolver();

const Map<String, _LineMetadata> _lineMetadata = {
  'AEL': _LineMetadata('Airport Express', '機場快綫', Color(0xFF00888D)),
  'TCL': _LineMetadata('Tung Chung Line', '東涌綫', Color(0xFFF7943E)),
  'TML': _LineMetadata('Tuen Ma Line', '屯馬綫', Color.fromRGBO(255, 51, 173, 1)),
  'TKL': _LineMetadata('Tseung Kwan O Line', '將軍澳綫', Color(0xFF92278F)),
  'EAL': _LineMetadata('East Rail Line', '東鐵綫', Color(0xFF0075C2)),
  'SIL': _LineMetadata('South Island Line', '南港島綫', Color.fromRGBO(156, 164, 0, 1)),
  'TWL': _LineMetadata('Tsuen Wan Line', '荃灣綫', Color(0xFFE60012)),
  'ISL': _LineMetadata('Island Line', '港島綫', Color(0xFF0055B8)),
  'KTL': _LineMetadata('Kwun Tong Line', '觀塘綫', Color(0xFF00A040)),
  'DRL': _LineMetadata('Disneyland Resort Line', '迪士尼綫', Color.fromRGBO(241, 115, 172, 1)),
};

// ========================= MTR Catalog Provider =========================

class MtrCatalogProvider extends ChangeNotifier {
  List<MtrLine> _lines = [];
  MtrLine? _selectedLine;
  MtrStation? _selectedStation;
  String? _selectedDirection; // UP, DOWN, IN, OUT, etc.
  bool _isInitialized = false;
  static const String _catalogAssetPath = 'lib/Route Station.json';
  
  List<MtrLine> get lines => _lines;
  MtrLine? get selectedLine => _selectedLine;
  MtrStation? get selectedStation => _selectedStation;
  String? get selectedDirection => _selectedDirection;
  bool get isInitialized => _isInitialized;
  bool get hasSelection => _selectedLine != null && _selectedStation != null;
  
  /// Get available directions for the current line
  List<String> get availableDirections {
    if (_selectedLine == null) return const [];
    return _selectedLine!.directionTermini.keys.toList()..sort();
  }
  
  /// Get all stations for the selected line (direction doesn't filter stations)
  List<MtrStation> get filteredStations {
    if (_selectedLine == null) return const [];
    return _selectedLine!.stations;
  }
  
  MtrCatalogProvider() {
    _loadMtrData();
  }
  
  Future<void> _loadMtrData() async {
    try {
      final raw = await rootBundle.loadString(_catalogAssetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _lines = _buildLinesFromJson(decoded);
    } catch (e) {
      debugPrint('Failed to load MTR catalog from JSON: $e');
      _lines = const [];
    }

    _isInitialized = true;
    await _loadSavedSelection();
    if (_selectedLine == null && _lines.isNotEmpty) {
      _selectedLine = _lines.first;
      _selectedStation = _selectedLine!.stations.isNotEmpty ? _selectedLine!.stations.first : null;
    }
    notifyListeners();
  }

  List<MtrLine> _buildLinesFromJson(Map<String, dynamic> json) {
    final stationGroupsRaw = json['station_groups'];
    final Map<String, Set<String>> interchangeMatrix = {};
    if (stationGroupsRaw is List) {
      for (final item in stationGroupsRaw) {
        if (item is Map<String, dynamic>) {
          final stationCode = item['station_code']?.toString();
          if (stationCode == null || stationCode.isEmpty) continue;
          final lines = (item['lines'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet() ?? <String>{};
          interchangeMatrix[stationCode] = lines;
        }
      }
    }

    final List<MtrLine> lines = [];
    final lineGroups = json['line_groups'];
    if (lineGroups is List) {
      for (final entry in lineGroups) {
        if (entry is! Map<String, dynamic>) continue;
        final lineCode = entry['line_code']?.toString() ?? '';
        if (lineCode.isEmpty) continue;

        final meta = _lineMetadata[lineCode];
        final nameEn = meta?.nameEn ?? entry['line_name']?.toString() ?? lineCode;
        final nameZh = meta?.nameZh ?? entry['line_name']?.toString() ?? lineCode;
        final color = meta?.color ?? const Color(0xFF607D8B);

        final stations = <MtrStation>[];
        final stationCodes = entry['stations'];
        if (stationCodes is List) {
          for (final codeRaw in stationCodes) {
            final code = codeRaw?.toString() ?? '';
            if (code.isEmpty) continue;
            final nameEnglish = stationNameResolver.nameEn(code);
            final nameChinese = stationNameResolver.nameZh(code);
            final interchangeLines = <String>{...(interchangeMatrix[code] ?? const <String>{})};
            interchangeLines.remove(lineCode);
            stations.add(MtrStation(
              stationCode: code,
              nameEn: nameEnglish,
              nameZh: nameChinese,
              interchangeLines: interchangeLines.toList()..sort(),
            ));
          }
        }

        final directionMap = <String, List<String>>{};
        final directions = entry['directions'];
        if (directions is Map<String, dynamic>) {
          for (final dirEntry in directions.entries) {
            final dirKey = dirEntry.key.toString().toUpperCase();
            final codes = (dirEntry.value as List?)
                ?.map((e) => e.toString())
                .where((code) => code.isNotEmpty)
                .toList() ??
                <String>[];
            if (codes.isNotEmpty) {
              directionMap[dirKey] = codes;
            }
          }
        }

        lines.add(MtrLine(
          lineCode: lineCode,
          nameEn: nameEn,
          nameZh: nameZh,
          lineColor: color,
          stations: stations,
          directionTermini: directionMap,
        ));
      }
    }

    return lines;
  }
  
  Future<void> _loadSavedSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLineCode = prefs.getString('mtr_selected_line');
      final savedStationCode = prefs.getString('mtr_selected_station');
      final savedDirection = prefs.getString('mtr_selected_direction');
      
      if (savedLineCode != null && savedStationCode != null) {
        final line = _lines.firstWhere(
          (l) => l.lineCode == savedLineCode,
          orElse: () => _lines.first,
        );
        final station = line.stations.firstWhere(
          (s) => s.stationCode == savedStationCode,
          orElse: () => line.stations.first,
        );
        
        _selectedLine = line;
        _selectedStation = station;
        _selectedDirection = savedDirection;
      }
    } catch (e) {
      debugPrint('Failed to load MTR saved selection: $e');
    }
  }
  
  Future<void> selectLine(MtrLine line) async {
    _selectedLine = line;
    _selectedStation = line.stations.isNotEmpty ? line.stations.first : null;
    notifyListeners();
    
    // Save selection
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mtr_selected_line', line.lineCode);
      if (_selectedStation != null) {
        await prefs.setString('mtr_selected_station', _selectedStation!.stationCode);
      }
    } catch (e) {
      debugPrint('Failed to save MTR line selection: $e');
    }
  }
  

  
  Future<void> selectStation(MtrStation station) async {
    _selectedStation = station;
    notifyListeners();
    
    // Save selection
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mtr_selected_station', station.stationCode);
    } catch (e) {
      debugPrint('Failed to save MTR station selection: $e');
    }
  }
  
}

// ========================= MTR Schedule Provider =========================

class MtrScheduleProvider extends ChangeNotifier {
  // Persisted auto-refresh preference
  static const String _autoRefreshPrefKey = 'mtr_auto_refresh_enabled';
  bool _autoRefreshEnabled = true;
  bool get autoRefreshEnabled => _autoRefreshEnabled;

  Future<void> loadAutoRefreshPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoRefreshEnabled = prefs.getBool(_autoRefreshPrefKey) ?? true;
      notifyListeners();
    } catch (_) {
      _autoRefreshEnabled = true;
    }
  }

  Future<void> saveAutoRefreshPref(bool enabled) async {
    _autoRefreshEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoRefreshPrefKey, enabled);
    } catch (_) {}
  }
  
  final MtrApiService _api = MtrApiService();
  
  MtrScheduleResponse? _data;
  bool _loading = false;
  String? _error;
  
  // ===== ADAPTIVE REFRESH FOR POOR NETWORK CONDITIONS =====
  
  Timer? _autoRefreshTimer;
  Duration? _currentRefreshInterval;
  static const Duration _defaultRefreshInterval = Duration(seconds: 30);
  static const Duration _slowNetworkInterval = Duration(seconds: 60); // Slower on poor network
  static const Duration _offlineInterval = Duration(seconds: 120); // Very slow when offline
  
  DateTime? _lastRefreshTime;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 5; // Increased tolerance
  
  // Circuit breaker state
  bool _circuitBreakerOpen = false;
  DateTime? _circuitBreakerOpenedAt;
  static const Duration _circuitBreakerResetDuration = Duration(minutes: 2);
  
  // Network quality tracking
  bool _isNetworkSlow = false;
  final List<Duration> _recentFetchDurations = [];
  static const int _maxFetchDurationSamples = 5;
  static const Duration _slowNetworkThreshold = Duration(seconds: 5);
  
  MtrScheduleResponse? get data => _data;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _data != null;
  bool get isAutoRefreshActive => _autoRefreshTimer != null && _autoRefreshTimer!.isActive;
  bool get isNetworkSlow => _isNetworkSlow;
  bool get isCircuitBreakerOpen => _circuitBreakerOpen;
  String get currentRefreshIntervalDescription => _currentRefreshInterval != null ? '${_currentRefreshInterval!.inSeconds}s' : '';
  
  /// Load schedule with network-aware optimizations
  Future<void> loadSchedule(
    String lineCode, 
    String stationCode, {
    bool forceRefresh = false,
    bool allowStaleCache = true,
  }) async {
    // Prevent concurrent loads
    if (_loading) {
      debugPrint('MTR Schedule: Already loading, skipping');
      return;
    }
    
    // Check circuit breaker
    if (_circuitBreakerOpen) {
      if (DateTime.now().difference(_circuitBreakerOpenedAt!) < _circuitBreakerResetDuration) {
        debugPrint('MTR Schedule: Circuit breaker open, using cached data');
        // Try to serve from cache without network call
        if (_data != null) return;
        _error = 'Network temporarily unavailable, please try again later';
        notifyListeners();
        return;
      } else {
        // Reset circuit breaker
        _closeCircuitBreaker();
      }
    }
    
    _loading = true;
    _error = null;
    if (forceRefresh) _data = null;
    notifyListeners();
    
    final fetchStart = DateTime.now();
    
    try {
      final schedule = await _api.fetchSchedule(
        lineCode, 
        stationCode,
        forceRefresh: forceRefresh,
        allowStale: allowStaleCache && !forceRefresh,
      );
      
      final fetchDuration = DateTime.now().difference(fetchStart);
      _trackFetchDuration(fetchDuration);
      
      if (schedule.status != 1) {
        _data = null;
        _error = schedule.message.isNotEmpty ? schedule.message : 'Unable to load schedule';
        _consecutiveErrors++;
      } else {
        _data = schedule;
        _error = null;
        _lastRefreshTime = DateTime.now();
        _consecutiveErrors = 0; // Reset on success
      }
    } catch (e) {
      _error = _formatError(e.toString());
      debugPrint('MTR Schedule Error: $e');
      _consecutiveErrors++;
      
      // Open circuit breaker if too many errors
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _openCircuitBreaker();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
  
  /// Track fetch duration to detect slow network
  void _trackFetchDuration(Duration duration) {
    _recentFetchDurations.add(duration);
    if (_recentFetchDurations.length > _maxFetchDurationSamples) {
      _recentFetchDurations.removeAt(0);
    }
    
    // Calculate average
    if (_recentFetchDurations.length >= 3) {
      final avgDuration = _recentFetchDurations.reduce((a, b) => a + b) ~/ _recentFetchDurations.length;
      final wasNetworkSlow = _isNetworkSlow;
      _isNetworkSlow = avgDuration > _slowNetworkThreshold;
      
      if (_isNetworkSlow != wasNetworkSlow) {
        debugPrint('MTR Schedule: Network speed changed - slow: $_isNetworkSlow (avg: ${avgDuration.inSeconds}s)');
        // Adjust refresh interval if auto-refresh is active
        if (isAutoRefreshActive) {
          _adjustRefreshInterval();
        }
      }
    }
  }
  
  /// Adjust refresh interval based on network conditions
  void _adjustRefreshInterval() {
    final newInterval = _isNetworkSlow 
      ? _slowNetworkInterval 
      : (_circuitBreakerOpen ? _offlineInterval : _defaultRefreshInterval);
    
    if (newInterval != _currentRefreshInterval) {
      debugPrint('MTR Schedule: Adjusting refresh interval to ${newInterval.inSeconds}s');
      _currentRefreshInterval = newInterval;
      // Note: Timer will use new interval on next tick
    }
  }
  
  /// Open circuit breaker to stop hammering the API
  void _openCircuitBreaker() {
    if (!_circuitBreakerOpen) {
      _circuitBreakerOpen = true;
      _circuitBreakerOpenedAt = DateTime.now();
      debugPrint('MTR Schedule: Circuit breaker OPENED (${_consecutiveErrors} consecutive errors)');
      stopAutoRefresh(); // Stop refreshing
      notifyListeners();
    }
  }
  
  /// Close circuit breaker
  void _closeCircuitBreaker() {
    if (_circuitBreakerOpen) {
      _circuitBreakerOpen = false;
      _circuitBreakerOpenedAt = null;
      _consecutiveErrors = 0;
      debugPrint('MTR Schedule: Circuit breaker CLOSED (reset after timeout)');
      notifyListeners();
    }
  }
  
  /// Format error message for better UX
  String _formatError(String error) {
    if (error.contains('SocketException') || error.contains('NetworkException')) {
      return 'No internet connection. Showing cached data if available.';
    } else if (error.contains('TimeoutException')) {
      return 'Request timed out. Network may be slow.';
    } else if (error.contains('FormatException')) {
      return 'Received invalid data from server.';
    }
    return 'Unable to fetch schedule: ${error.replaceAll('Exception: ', '')}';
  }
  
  /// Start auto-refresh with adaptive intervals
  void startAutoRefresh(String lineCode, String stationCode, {Duration? interval}) {
    stopAutoRefresh();
    
    // Use adaptive interval if not specified
    final refreshInterval = interval ?? _getAdaptiveInterval();
    _currentRefreshInterval = refreshInterval;
    
    debugPrint('MTR Auto-refresh: Starting with interval ${refreshInterval.inSeconds}s');
    
    _autoRefreshTimer = Timer.periodic(refreshInterval, (_) async {
      // Check if we should adjust interval
      final adaptiveInterval = _getAdaptiveInterval();
      if (adaptiveInterval != _currentRefreshInterval) {
        debugPrint('MTR Auto-refresh: Restarting with new interval ${adaptiveInterval.inSeconds}s');
        startAutoRefresh(lineCode, stationCode, interval: adaptiveInterval);
        return;
      }
      
      debugPrint('MTR Auto-refresh: Refreshing $lineCode/$stationCode');
      await loadSchedule(
        lineCode, 
        stationCode, 
        forceRefresh: false, // Allow stale-while-revalidate
        allowStaleCache: true,
      );
    });
    
    // Immediate refresh (allow cache to serve stale data quickly)
    loadSchedule(lineCode, stationCode, forceRefresh: false, allowStaleCache: true);
    notifyListeners();
  }
  
  /// Get adaptive refresh interval based on network conditions
  Duration _getAdaptiveInterval() {
    if (_circuitBreakerOpen) return _offlineInterval;
    if (_isNetworkSlow) return _slowNetworkInterval;
    if (_consecutiveErrors > 0) {
      // Gradual backoff: 30s -> 45s -> 60s
      final backoffMultiplier = 1 + (_consecutiveErrors * 0.5);
      return Duration(seconds: (_defaultRefreshInterval.inSeconds * backoffMultiplier).round().clamp(30, 120));
    }
    return _defaultRefreshInterval;
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _currentRefreshInterval = null;
    debugPrint('MTR Auto-refresh: Stopped');
    notifyListeners();
  }
  
  /// Manual refresh - forces network call and resets circuit breaker
  Future<void> manualRefresh(String lineCode, String stationCode) async {
    _closeCircuitBreaker(); // Allow manual refresh to try
    await loadSchedule(lineCode, stationCode, forceRefresh: true, allowStaleCache: false);
  }
  
  /// Clear all caches and reset state
  Future<void> clearAllCaches() async {
    await _api.clearAllCaches();
    clearData();
    _consecutiveErrors = 0;
    _recentFetchDurations.clear();
    _isNetworkSlow = false;
    _closeCircuitBreaker();
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
  
  void clearData() {
    _data = null;
    _error = null;
    notifyListeners();
  }
}

// ========================= MTR Schedule Page UI =========================

class MtrSchedulePage extends StatefulWidget {
  const MtrSchedulePage({super.key});

  @override
  State<MtrSchedulePage> createState() => _MtrSchedulePageState();
}

class _MtrSchedulePageState extends State<MtrSchedulePage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _autoRefreshInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load auto-refresh preference once when widget is inserted
    if (!_autoRefreshInitialized) {
      _autoRefreshInitialized = true;
      final schedule = context.read<MtrScheduleProvider>();
      final catalog = context.read<MtrCatalogProvider>();
      schedule.loadAutoRefreshPref().then((_) {
        if (catalog.hasSelection) {
          if (schedule.autoRefreshEnabled) {
            if (!schedule.isAutoRefreshActive) {
              schedule.startAutoRefresh(
                catalog.selectedLine!.lineCode,
                catalog.selectedStation!.stationCode,
              );
            }
          } else {
            if (schedule.isAutoRefreshActive) {
              schedule.stopAutoRefresh();
            }
          }
        }
      });
    }
  }
  late final AnimationController _refreshAnimController;
  late final Animation<double> _refreshRotation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduleIfNeeded();
    });
    // Optimized refresh animation with ease-in-out for smoother rotation
    _refreshAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _refreshRotation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _refreshAnimController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final catalog = context.read<MtrCatalogProvider>();
    final schedule = context.read<MtrScheduleProvider>();
    if (state == AppLifecycleState.resumed) {
      // Resume auto-refresh if selection exists AND auto-refresh was enabled
      if (catalog.hasSelection && schedule.autoRefreshEnabled) {
        schedule.loadSchedule(
          catalog.selectedLine!.lineCode,
          catalog.selectedStation!.stationCode,
          forceRefresh: true,
        );
        if (!schedule.isAutoRefreshActive) {
          schedule.startAutoRefresh(
            catalog.selectedLine!.lineCode,
            catalog.selectedStation!.stationCode,
          );
        }
      }
    } else if (state == AppLifecycleState.paused) {
      schedule.stopAutoRefresh();
    }
  }

  void _loadScheduleIfNeeded() {
    final catalog = context.read<MtrCatalogProvider>();
    final schedule = context.read<MtrScheduleProvider>();
    if (catalog.hasSelection && !schedule.hasData && !schedule.loading) {
      schedule.loadSchedule(
        catalog.selectedLine!.lineCode,
        catalog.selectedStation!.stationCode,
      );
    }
    // Start/stop auto-refresh based on cached preference
    if (catalog.hasSelection) {
      if (schedule.autoRefreshEnabled) {
        if (!schedule.isAutoRefreshActive) {
          schedule.startAutoRefresh(
            catalog.selectedLine!.lineCode,
            catalog.selectedStation!.stationCode,
          );
        }
      } else {
        if (schedule.isAutoRefreshActive) {
          schedule.stopAutoRefresh();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<MtrCatalogProvider>();
    final schedule = context.watch<MtrScheduleProvider>();
    final lang = context.watch<LanguageProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    if (!catalog.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.lines.isEmpty) {
      return const Center(child: Text('No MTR lines available'));
    }

    // Animate refresh icon if auto-refresh is active
    // Animate refresh icon if auto-refresh is active
    if (schedule.isAutoRefreshActive && !_refreshAnimController.isAnimating) {
      _refreshAnimController.repeat();
    } else if (!schedule.isAutoRefreshActive && _refreshAnimController.isAnimating) {
      _refreshAnimController.stop();
      _refreshAnimController.reset();
    }

    return Column(
      children: [
        // Line and Station Selector
        _MtrSelector(
          lines: catalog.lines,
          selectedLine: catalog.selectedLine,
          selectedStation: catalog.selectedStation,
          onLineChanged: (line) async {
            await catalog.selectLine(line);
            if (catalog.selectedStation != null) {
              schedule.loadSchedule(line.lineCode, catalog.selectedStation!.stationCode, forceRefresh: true);
              schedule.startAutoRefresh(line.lineCode, catalog.selectedStation!.stationCode);
            }
          },
          onStationChanged: (station) async {
            await catalog.selectStation(station);
            if (catalog.selectedLine != null) {
              schedule.loadSchedule(catalog.selectedLine!.lineCode, station.stationCode, forceRefresh: true);
              schedule.startAutoRefresh(catalog.selectedLine!.lineCode, station.stationCode);
            }
          },
        ),
        // Auto-refresh control bar with integrated status
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Auto-refresh toggle
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Stack(
                  children: [
                    // Optimized rotation with cached animation
                    RotationTransition(
                      turns: _refreshRotation,
                      child: Icon(Icons.refresh, size: 20, color: colorScheme.primary),
                    ),
                    if (schedule.isAutoRefreshActive)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                iconSize: 18,
                tooltip: schedule.isAutoRefreshActive
                    ? (lang.isEnglish ? 'Auto-refresh ON' : '自動刷新已啟用')
                    : lang.refresh,
                onPressed: catalog.hasSelection
                    ? () async {
                        if (schedule.isAutoRefreshActive) {
                          schedule.stopAutoRefresh();
                          await schedule.saveAutoRefreshPref(false);
                        } else {
                          schedule.startAutoRefresh(
                            catalog.selectedLine!.lineCode,
                            catalog.selectedStation!.stationCode,
                          );
                          await schedule.saveAutoRefreshPref(true);
                        }
                      }
                    : null,
              ),
              const SizedBox(width: 2),
              // Status indicator
              if (schedule.hasData) ...[
                Icon(
                  schedule.data!.status != 1
                      ? Icons.error_outline
                      : schedule.data!.isDelay
                          ? Icons.schedule
                          : Icons.check_circle_outline,
                  size: 14,
                  color: schedule.data!.status != 1
                      ? Colors.red
                      : schedule.data!.isDelay
                          ? Colors.orange
                          : Colors.green,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    schedule.data!.status != 1
                        ? (lang.isEnglish ? 'Service Alert' : '服務提示')
                        : schedule.data!.isDelay
                            ? (lang.isEnglish ? 'Delays' : '延誤')
                            : (lang.isEnglish ? 'Normal' : '正常'),
                    style: TextStyle(
                      fontSize: 12,
                      color: schedule.data!.status != 1
                          ? Colors.red[800]
                          : schedule.data!.isDelay
                              ? Colors.orange[800]
                              : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // Last update time
              if (schedule._lastRefreshTime != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 11, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      TimeOfDay.fromDateTime(schedule._lastRefreshTime!).format(context),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Schedule Display
        Expanded(
          child: _MtrScheduleBody(
            loading: schedule.loading && !schedule.hasData,
            error: schedule.error,
            data: schedule.data,
            onRefresh: catalog.hasSelection
                ? () => schedule.loadSchedule(
                    catalog.selectedLine!.lineCode,
                    catalog.selectedStation!.stationCode,
                    forceRefresh: true,
                  )
                : null,
            line: catalog.selectedLine,
          ),
        ),
      ],
    );
  }
}

// MTR Selector Widget
class _MtrSelector extends StatefulWidget {
  final List<MtrLine> lines;
  final MtrLine? selectedLine;
  final MtrStation? selectedStation;
  final ValueChanged<MtrLine> onLineChanged;
  final ValueChanged<MtrStation> onStationChanged;
  
  const _MtrSelector({
    required this.lines,
    required this.selectedLine,
    required this.selectedStation,
    required this.onLineChanged,
    required this.onStationChanged,
  });

  @override
  State<_MtrSelector> createState() => _MtrSelectorState();
}

class _MtrSelectorState extends State<_MtrSelector> with SingleTickerProviderStateMixin {
  static const String _stationExpandPrefKey = 'mtr_station_dropdown_expanded';
  static const String _lineExpandPrefKey = 'mtr_line_dropdown_expanded';
  bool _showStations = true;
  bool _showLines = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animController.forward();
    _loadExpandPrefs();
  }

  Future<void> _loadExpandPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStations = prefs.getBool(_stationExpandPrefKey) ?? true;
        _showLines = prefs.getBool(_lineExpandPrefKey) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _saveStationExpandPref(bool expanded) async {
    _showStations = expanded;
    setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_stationExpandPrefKey, expanded);
    } catch (_) {}
  }

  Future<void> _saveLineExpandPref(bool expanded) async {
    _showLines = expanded;
    setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lineExpandPrefKey, expanded);
    } catch (_) {}
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<MtrCatalogProvider>();
    final lang = context.watch<LanguageProvider>();
    final filteredStations = catalog.filteredStations;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: UIConstants.cardPadding, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Line Selector Card (now with drop-down toggle)
          _buildSelectorCard(
            context: context,
            icon: Icons.train_outlined,
            title: widget.selectedLine != null 
                ? widget.selectedLine!.displayName(lang.isEnglish)
                : lang.isEnglish ? 'Select MTR Line' : '選擇港鐵綫路',
            color: widget.selectedLine?.lineColor ?? colorScheme.primary,
            isExpanded: _showLines,
            showToggle: true,
            onToggle: () async => await _saveLineExpandPref(!_showLines),
            content: _showLines ? Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.lines.map((line) {
                final isSelected = line == widget.selectedLine;
                return _buildChip(
                  context: context,
                  label: line.displayName(lang.isEnglish),
                  isSelected: isSelected,
                  color: line.lineColor,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onLineChanged(line);
                    _animController.forward(from: 0);
                  },
                  leadingWidget: Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: line.lineColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                );
              }).toList(),
            ) : null,
          ),

          // Station Selector Card (cached drop-down style)
          if (widget.selectedLine != null && filteredStations.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSelectorCard(
              context: context,
              icon: Icons.location_on_outlined,
              title: widget.selectedStation != null
                  ? widget.selectedStation!.displayName(lang.isEnglish)
                  : lang.isEnglish ? 'Select Station' : '選擇車站',
              color: widget.selectedLine!.lineColor,
              isExpanded: _showStations,
              showToggle: true,
              onToggle: () async => await _saveStationExpandPref(!_showStations),
              trailing: widget.selectedStation != null && widget.selectedStation!.isInterchange
                  ? _buildCompactInterchangeIndicator(context, widget.selectedStation!)
                  : null,
              content: _showStations ? Wrap(
                spacing: 6,
                runSpacing: 6,
                children: filteredStations.map((station) {
                  final isSelected = station == widget.selectedStation;
                  return _buildChip(
                    context: context,
                    label: station.displayName(lang.isEnglish),
                    isSelected: isSelected,
                    color: widget.selectedLine!.lineColor,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onStationChanged(station);
                    },
                    trailing: station.isInterchange 
                        ? _buildInterchangeIndicator(context, station)
                        : null,
                  );
                }).toList(),
              ) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectorCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required bool isExpanded,
    bool showToggle = false,
    VoidCallback? onToggle,
    Widget? trailing,
    Widget? content,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(UIConstants.cardRadius),
        border: Border.all(
          color: color.withOpacity(UIConstants.cardBorderOpacity),
          width: UIConstants.cardBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: UIConstants.cardElevation,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: showToggle ? onToggle : null,
            borderRadius: BorderRadius.vertical(top: Radius.circular(UIConstants.cardRadius)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: UIConstants.cardPadding, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontSize: UIConstants.cardTitleFontSize,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing,
                  ],
                  if (showToggle) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: UIConstants.iconSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Optimized AnimatedSize with seamless fade and slide
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: content != null && isExpanded
                ? AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isExpanded ? 1.0 : 0.0,
                    curve: Curves.easeIn,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(UIConstants.cardPadding, 4, UIConstants.cardPadding, UIConstants.cardPadding),
                      child: content,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Calculate contrast text color for better readability on colored backgrounds
  /// Uses luminance calculation and theme-aware colors for consistency
  /// IMPORTANT: For transparent colors, this blends with surface color to get accurate luminance
  Color _getContrastTextColor(Color backgroundColor, BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colorScheme = Theme.of(context).colorScheme;
    
    // For semi-transparent colors, blend with the actual surface background
    // This is critical for selected chips with color.withOpacity(0.2)
    final effectiveColor = backgroundColor.opacity < 1.0
        ? Color.alphaBlend(backgroundColor, colorScheme.surface)
        : backgroundColor;
    
    final luminance = effectiveColor.computeLuminance();
    
    // Calculate if background is light or dark based on luminance threshold
    final isLightBackground = luminance > 0.5;
    
    if (isLightBackground) {
      // Light background - use dark text
      // Use theme's onSurface color for consistency with app design
      return colorScheme.onSurface.withOpacity(0.87);
    } else {
      // Dark background - use light text
      if (brightness == Brightness.dark) {
        // Dark theme: Use onSurface which is already light
        return colorScheme.onSurface.withOpacity(0.95);
      } else {
        // Light theme: Use inverted color (light text on dark background)
        return Colors.white.withOpacity(0.95);
      }
    }
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    String? subtitle,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
    Widget? leadingWidget,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Calculate proper text color with good contrast against the chip background
    final textColor = isSelected 
        ? _getContrastTextColor(color.withOpacity(0.2), context)
        : colorScheme.onSurface;
    
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        // Staggered fade-in animation for smooth appearance
        final scale = Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
          ),
        );
        final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
          ),
        );
        
        return FadeTransition(
          opacity: opacity,
          child: ScaleTransition(
            scale: scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(UIConstants.chipRadius),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(horizontal: UIConstants.chipPaddingH, vertical: UIConstants.chipPaddingV),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? color.withOpacity(0.2) 
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(UIConstants.chipRadius),
                      border: Border.all(
                        color: isSelected
                            ? color.withOpacity(UIConstants.selectedChipBorderOpacity) 
                            : colorScheme.outline.withOpacity(UIConstants.chipBorderOpacity),
                        width: isSelected ? UIConstants.selectedChipBorderWidth : UIConstants.chipBorderWidth,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leadingWidget != null) ...[
                          leadingWidget,
                          const SizedBox(width: UIConstants.selectorSpacing),
                        ],
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            size: UIConstants.checkIconSize,
                            color: color,
                          ),
                        if (isSelected) const SizedBox(width: 4),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: UIConstants.chipFontSize,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: UIConstants.chipSubtitleFontSize,
                                    color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 4),
                          trailing,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInterchangeIndicator(BuildContext context, MtrStation station) {
    if (!station.isInterchange || station.interchangeLines.isEmpty) {
      return const Icon(Icons.compare_arrows, size: 12);
    }

    final lang = context.watch<LanguageProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    // Build color indicators for interchange lines
    final lineColors = station.interchangeLines
        .map((lineCode) => _lineMetadata[lineCode]?.color)
        .where((color) => color != null)
        .cast<Color>()
        .toList();

    if (lineColors.isEmpty) {
      return const Icon(Icons.compare_arrows, size: 12);
    }

    return Tooltip(
      message: lang.isEnglish 
          ? 'Interchange station'
          : '轉車站',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_arrows, 
              size: 12,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            const SizedBox(width: 4),
            ...lineColors.take(3).map((color) => Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            )),
            if (lineColors.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(
                  '+${lineColors.length - 3}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Compact interchange indicator for selector card header (like in the image)
  Widget _buildCompactInterchangeIndicator(BuildContext context, MtrStation station) {
    if (!station.isInterchange || station.interchangeLines.isEmpty) {
      return const SizedBox.shrink();
    }

    final catalog = context.read<MtrCatalogProvider>();
    final lang = context.watch<LanguageProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    // Build clickable line badges for interchange lines
    final interchangeLineCodes = station.interchangeLines;

    return Tooltip(
      message: lang.isEnglish 
          ? 'Tap to switch line'
          : '點擊切換綫路',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_arrows,
              size: 14,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            const SizedBox(width: 6),
            ...interchangeLineCodes.map((lineCode) {
              final lineColor = _lineMetadata[lineCode]?.color;
              final lineName = _lineMetadata[lineCode];
              if (lineColor == null) return const SizedBox.shrink();
              
              return Tooltip(
                message: lineName != null
                    ? (lang.isEnglish ? lineName.nameEn : lineName.nameZh)
                    : lineCode,
                child: InkWell(
                  onTap: () async {
                    // Find the line with this code
                    final targetLine = widget.lines.firstWhere(
                      (line) => line.lineCode == lineCode,
                      orElse: () => widget.lines.first,
                    );
                    
                    // Switch to the interchange line while keeping the same station
                    HapticFeedback.selectionClick();
                    await catalog.selectLine(targetLine);
                    
                    // The station will be auto-selected to the first station of the new line
                    // So we need to manually select the current station on the new line
                    final stationOnNewLine = targetLine.stations.firstWhere(
                      (s) => s.stationCode == station.stationCode,
                      orElse: () => targetLine.stations.first,
                    );
                    
                    await catalog.selectStation(stationOnNewLine);
                    widget.onLineChanged(targetLine);
                    widget.onStationChanged(stationOnNewLine);
                  },
                  borderRadius: BorderRadius.circular(4),
                  // Hover/press feedback
                  splashColor: lineColor.withOpacity(0.3),
                  highlightColor: lineColor.withOpacity(0.1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: lineColor.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    // Add subtle visual cue that it's clickable
                    child: Center(
                      child: Icon(
                        Icons.train,
                        size: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (interchangeLineCodes.length > 4)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '+${interchangeLineCodes.length - 4}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// MTR Schedule Body Widget
class _MtrScheduleBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final MtrScheduleResponse? data;
  final Future<void> Function()? onRefresh;
  final MtrLine? line;
  
  const _MtrScheduleBody({
    required this.loading,
    required this.error,
    required this.data,
    required this.onRefresh,
    required this.line,
  });

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final devSettings = context.watch<DeveloperSettingsProvider>();
    Widget content;
    
    if (loading) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        children: [
          const SizedBox(height: 20),
          // Modern shimmer loading cards
          ..._buildShimmerLoadingCards(context),
        ],
      );
    } else if (error != null) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Center(child: Text('${lang.isEnglish ? 'Error' : '錯誤'}: $error')),
          if (onRefresh != null) ...[
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                onPressed: onRefresh,
                child: Text(lang.retry),
              ),
            ),
          ],
        ],
      );
    } else if (data == null) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(child: Text(lang.isEnglish ? 'Select a line and station' : '選擇綫路及車站')),
        ],
      );
    } else if (data!.directionTrains.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(child: Text(lang.isEnglish ? 'No schedule data available' : '沒有班次資料')),
        ],
      );
    } else {
      final directionEntries = data!.directionTrains.entries.toList();
      
      content = ListView.builder(
        padding: const EdgeInsets.all(8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: directionEntries.length,
        itemBuilder: (context, index) {
          final entry = directionEntries.elementAt(index);
          final directionKey = entry.key;
          final trains = entry.value;
          final termini = line?.directionDisplayNamesLocalized(directionKey, stationNameResolver, lang.isEnglish) ?? const <String>[];

          String directionLabel(String key) {
            final upper = key.toUpperCase();
            if (lang.isEnglish) {
              switch (upper) {
                case 'UP':
                  return 'Upbound';
                case 'DOWN':
                  return 'Downbound';
                case 'IN':
                  return 'Inbound';
                case 'OUT':
                  return 'Outbound';
                default:
                  return upper;
              }
            } else {
              switch (upper) {
                case 'UP':
                  return '上行';
                case 'DOWN':
                  return '下行';
                case 'IN':
                  return '入站';
                case 'OUT':
                  return '出站';
                default:
                  return upper;
              }
            }
          }
          final terminusLabel = termini.isNotEmpty ? termini.join(' / ') : null;
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              // Liquid glass effect with gradient and blur
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surface.withOpacity(0.9),
                  Theme.of(context).colorScheme.surface.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.surface.withOpacity(0.3),
                        Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Direction header with improved layout
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.train,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${directionLabel(directionKey)} ${lang.isEnglish ? 'departures' : '開出'}',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    if (terminusLabel != null) ...[
                                      const SizedBox(height: 1),
                                      Text(
                                        '${lang.isEnglish ? 'To' : '往'} $terminusLabel',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontSize: 10,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Train list
                        if (trains.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                lang.isEnglish ? 'No trains scheduled' : '暫無班次',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                                ),
                              ),
                            ),
                          )
                        else
                          ...trains.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final train = entry.value;
                            final isLast = idx == trains.length - 1;
                            
                            // Staggered fade-in animation for smoother list appearance
                            return TweenAnimationBuilder<double>(
                              key: ValueKey(train.hashCode),
                              duration: Duration(milliseconds: 200 + (idx * 50).clamp(0, 400)),
                              tween: Tween(begin: 0.0, end: 1.0),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 8 * (1 - value)),
                                    child: child,
                                  ),
                                );
                              },
                              child: _TrainListItem(
                                train: train,
                                isLast: isLast,
                                lang: lang,
                                devSettings: devSettings,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    
    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        child: content,
      );
    }
    
    return content;
  }

  /// Build shimmer loading cards for better loading UX
  List<Widget> _buildShimmerLoadingCards(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return List.generate(2, (directionIndex) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.15),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Direction header shimmer
            _ShimmerBox(
              width: 180,
              height: 32,
              borderRadius: 10,
            ),
            const SizedBox(height: 10),
            // Train items shimmer
            ...List.generate(3, (trainIndex) {
              return Container(
                margin: EdgeInsets.only(bottom: trainIndex == 2 ? 0 : 6),
                child: Row(
                  children: [
                    _ShimmerBox(width: 8, height: 8, borderRadius: 4),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerBox(width: double.infinity, height: 13, borderRadius: 4),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _ShimmerBox(width: 80, height: 18, borderRadius: 5),
                              const SizedBox(width: 4),
                              _ShimmerBox(width: 60, height: 18, borderRadius: 5),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _ShimmerBox(width: 60, height: 24, borderRadius: 8),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    });
  }
}

/// Shimmer loading box widget
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                _shimmerAnimation.value - 0.3,
                _shimmerAnimation.value,
                _shimmerAnimation.value + 0.3,
              ].map((e) => e.clamp(0.0, 1.0)).toList(),
              colors: [
                colorScheme.surfaceContainerHighest.withOpacity(0.3),
                colorScheme.surfaceContainerHighest.withOpacity(0.6),
                colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Optimized train list item widget with cached status indicator
class _TrainListItem extends StatelessWidget {
  final MtrTrainInfo train;
  final bool isLast;
  final LanguageProvider lang;
  final DeveloperSettingsProvider devSettings;

  const _TrainListItem({
    required this.train,
    required this.isLast,
    required this.lang,
    required this.devSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusInfo = _getStatusInfo(context);
    
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Status indicator dot - optimized with cached calculation
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusInfo.color,
              shape: BoxShape.circle,
              boxShadow: statusInfo.shadow,
            ),
          ),
          const SizedBox(width: 10),
          // Destination
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  train.displayDestination(stationNameResolver, isEnglish: lang.isEnglish),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: 0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 3),
                _buildTrainSubtitle(context),
              ],
            ),
          ),
          // Time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              train.displayTimeLocalized(lang.isEnglish),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cached status info calculation with optimized logic
  /// Uses timetype field to distinguish EAL terminus from through trains
  /// For through trains: ttnt=0 means "Departing" (arrived and leaving)
  /// For EAL terminus: timetype='A'/ttnt=0 = "Arriving", timetype='D'/ttnt=0 = "Departing"
  ({Color color, List<BoxShadow>? shadow}) _getStatusInfo(BuildContext context) {
    final minutesVal = train.timeInMinutes;
    final colorScheme = Theme.of(context).colorScheme;
    
    // Handle trains at platform (ttnt = 0)
    if (minutesVal != null && minutesVal <= 0) {
      // EAL terminus arrival (timetype='A')
      if (train.timeType?.toUpperCase() == 'A') {
        return (
          color: Colors.green,
          shadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        );
      }
      // All other cases (through trains or timetype='D'): Departing
      return (
        color: Colors.deepOrange,
        shadow: [
          BoxShadow(
            color: Colors.deepOrange.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      );
    }
    
    // Arriving: 1-2 minutes away
    if (minutesVal != null && minutesVal <= 2) {
      return (
        color: Colors.green,
        shadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      );
    }
    
    // Approaching: 3 minutes away
    if (minutesVal != null && minutesVal == 3) {
      return (
        color: Colors.amber,
        shadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      );
    }
    
    // Default: Primary color
    return (color: colorScheme.primary, shadow: null);
  }

  Widget _buildTrainSubtitle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final minutesVal = train.timeInMinutes;
    final minutesLabel = () {
      if (minutesVal == null) return '-';
      if (lang.isEnglish) {
        if (minutesVal <= 0) return '0 min';
        if (minutesVal == 1) return '1 min';
        return '$minutesVal mins';
      } else {
        final v = minutesVal < 0 ? 0 : minutesVal;
        return '$v 分鐘';
      }
    }();

    // Determine status using optimized properties
    // For through trains: ttnt=0 means "Departing"
    // For EAL terminus: timetype='A'/ttnt=0 = "Arriving", timetype='D'/ttnt=0 = "Departing"
    String statusLabel = '';
    Color? statusColor;
    IconData? statusIcon;
    
    // Handle trains at platform (ttnt = 0)
    if (minutesVal != null && minutesVal <= 0) {
      // EAL terminus arrival (timetype='A')
      if (train.timeType?.toUpperCase() == 'A') {
        statusLabel = lang.isEnglish ? 'Arriving' : '即將到達';
        statusColor = Colors.green;
        statusIcon = Icons.adjust;
      } else {
        // Through trains or EAL terminus departure (timetype='D')
        statusLabel = lang.isEnglish ? 'Departing' : '正在離開';
        statusColor = Colors.deepOrange;
        statusIcon = Icons.near_me;
      }
    } 
    // Arriving: Train is 1-2 minutes away
    else if (minutesVal != null && minutesVal <= 2) {
      statusLabel = lang.isEnglish ? 'Arriving' : '即將到達';
      statusColor = Colors.green;
      statusIcon = Icons.adjust;
    } 
    // Approaching: Train is 3 minutes away
    else if (minutesVal != null && minutesVal == 3) {
      statusLabel = lang.isEnglish ? 'Approaching' : '接近中';
      statusColor = Colors.amber;
      statusIcon = Icons.directions_transit;
    }

    return Wrap(
      spacing: 4,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (devSettings.showMtrArrivalDetails && train.platform.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stairs, size: 9, color: colorScheme.primary),
                const SizedBox(width: 3),
                Text(
                  '${lang.isEnglish ? 'Platform' : '月台'} ${train.platform}',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        if (minutesLabel.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 9, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(
                  minutesLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (statusLabel.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor?.withOpacity(0.15),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: statusColor?.withOpacity(0.4) ?? Colors.transparent,
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor?.withOpacity(0.2) ?? Colors.transparent,
                  blurRadius: 3,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (statusIcon != null) ...[
                  Icon(statusIcon, size: 9, color: statusColor),
                  const SizedBox(width: 3),
                ],
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
