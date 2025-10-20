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
  
  /// Check if a station is a TRUE terminus station (first or last station on the line)
  /// This is different from a terminus CODE in the API which may represent services
  /// that terminate at intermediate stations (like Racecourse, Fo Tan, etc.)
  /// Only actual end-of-line terminus stations should return true
  bool isTerminusStation(String stationCode) {
    if (stations.isEmpty) return false;
    
    // A station is a true terminus only if it's the first or last station on the line
    final firstStation = stations.first.stationCode;
    final lastStation = stations.last.stationCode;
    
    return stationCode == firstStation || stationCode == lastStation;
  }
  
  /// Check if a station appears as a terminus code in the API data
  /// This may include intermediate stations where some services terminate
  /// (e.g., Racecourse on EAL, LOHAS Park on TKL)
  bool isTerminusCode(String stationCode) {
    for (final terminusList in directionTermini.values) {
      if (terminusList.contains(stationCode)) {
        return true;
      }
    }
    return false;
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
  bool _hasAppliedUserPreference = false; // Track if we've applied the auto-load preference
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
    // Load data without applying cached selection initially
    // The page will call initializeWithSettings() to apply user preference
    _loadMtrData(loadCachedSelection: false);
  }
  
  /// Initialize with user settings - call this after DeveloperSettingsProvider is ready
  Future<void> initializeWithSettings(bool shouldLoadCachedSelection) async {
    if (_hasAppliedUserPreference) {
      debugPrint('MTR Catalog: User preference already applied, skipping');
      return;
    }
    
    _hasAppliedUserPreference = true;
    
    if (shouldLoadCachedSelection) {
      debugPrint('MTR Catalog: Applying cached selection (user preference: enabled)');
      await _loadSavedSelection();
      notifyListeners();
    } else {
      debugPrint('MTR Catalog: Skipping cached selection (user preference: disabled)');
      // Reset to first line/station for manual selection
      if (_lines.isNotEmpty) {
        _selectedLine = _lines.first;
        _selectedStation = _selectedLine!.stations.isNotEmpty ? _selectedLine!.stations.first : null;
        notifyListeners();
      }
    }
  }
  
  Future<void> _loadMtrData({bool loadCachedSelection = true}) async {
    try {
      final raw = await rootBundle.loadString(_catalogAssetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _lines = _buildLinesFromJson(decoded);
    } catch (e) {
      debugPrint('Failed to load MTR catalog from JSON: $e');
      _lines = const [];
    }

    _isInitialized = true;
    
    // Only load saved selection if enabled in settings
    if (loadCachedSelection) {
      await _loadSavedSelection();
    }
    
    // If no selection after loading (either disabled or no cache), default to first line/station
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
        MtrLine? line;
        if (_lines.isNotEmpty) {
          line = _lines.firstWhere(
            (l) => l.lineCode == savedLineCode,
            orElse: () => _lines.first,
          );
        }
        MtrStation? station;
        if (line != null && line.stations.isNotEmpty) {
          station = line.stations.firstWhere(
            (s) => s.stationCode == savedStationCode,
            orElse: () => line!.stations.first,
          );
        }
        _selectedLine = line;
        _selectedStation = station;
        _selectedDirection = savedDirection;
      } else {
        _selectedLine = null;
        _selectedStation = null;
        _selectedDirection = null;
      }
    } catch (e) {
      debugPrint('Failed to load MTR saved selection: $e');
    }
  }
  
  /// Reload MTR data with option to apply cached selection
  /// Call this when the auto-load setting changes
  Future<void> reloadWithSettings(bool loadCachedSelection) async {
    _isInitialized = false;
    notifyListeners();
    await _loadMtrData(loadCachedSelection: loadCachedSelection);
  }
  
  /// Apply cached selection if available (call this when auto-load setting is enabled)
  Future<void> applyCachedSelection() async {
    await _loadSavedSelection();
    notifyListeners();
  }
  
  Future<void> selectLine(MtrLine line) async {
    _selectedLine = line;
    _selectedStation = line.stations.isNotEmpty ? line.stations.first : null;
    // Reset direction when changing line
    _selectedDirection = null;
    notifyListeners();
    
    // Save selection
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mtr_selected_line', line.lineCode);
      if (_selectedStation != null) {
        await prefs.setString('mtr_selected_station', _selectedStation!.stationCode);
      }
      // Clear saved direction when changing line
      await prefs.remove('mtr_selected_direction');
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
      // Also save line code to ensure consistency
      if (_selectedLine != null) {
        await prefs.setString('mtr_selected_line', _selectedLine!.lineCode);
      }
      // Keep current direction when changing station on same line
      if (_selectedDirection != null) {
        await prefs.setString('mtr_selected_direction', _selectedDirection!);
      }
    } catch (e) {
      debugPrint('Failed to save MTR station selection: $e');
    }
  }
  
  Future<void> selectDirection(String direction) async {
    _selectedDirection = direction;
    notifyListeners();
    
    // Save selection
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mtr_selected_direction', direction);
      // Also ensure line and station are saved
      if (_selectedLine != null) {
        await prefs.setString('mtr_selected_line', _selectedLine!.lineCode);
      }
      if (_selectedStation != null) {
        await prefs.setString('mtr_selected_station', _selectedStation!.stationCode);
      }
    } catch (e) {
      debugPrint('Failed to save MTR direction selection: $e');
    }
  }
  
  /// Atomically select both line and station (used for interchange switching)
  /// This prevents intermediate UI updates that would show the wrong station
  Future<void> selectLineAndStation(MtrLine line, MtrStation station) async {
    // Validate station belongs to line
    final stationExists = line.stations.any((s) => s.stationCode == station.stationCode);
    if (!stationExists) {
      debugPrint('MTR Catalog: Station ${station.stationCode} not found on line ${line.lineCode}');
      // Fallback to regular selectLine if station doesn't exist on target line
      await selectLine(line);
      return;
    }
    
    // Atomically update both line and station (single notifyListeners call)
    _selectedLine = line;
    _selectedStation = station;
    // Reset direction when changing line
    _selectedDirection = null;
    
    // Single notification prevents intermediate UI state
    notifyListeners();
    
    // Save selection
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mtr_selected_line', line.lineCode);
      await prefs.setString('mtr_selected_station', station.stationCode);
      // Clear saved direction when changing line
      await prefs.remove('mtr_selected_direction');
      debugPrint('MTR Catalog: Atomically switched to ${line.lineCode} / ${station.stationCode}');
    } catch (e) {
      debugPrint('Failed to save MTR line and station selection: $e');
    }
  }
  
}

// ========================= MTR Schedule Provider =========================

/// Pending operation for sequential execution
class _PendingOperation {
  final String lineCode;
  final String stationCode;
  final bool forceRefresh;
  final bool allowStaleCache;
  final bool silentRefresh;
  final int priority; // Higher priority operations replace lower priority pending operations
  
  _PendingOperation({
    required this.lineCode,
    required this.stationCode,
    required this.forceRefresh,
    required this.allowStaleCache,
    required this.silentRefresh,
    this.priority = 0,
  });
  
  // Priority levels for different operation types
  static const int priorityAutoRefresh = 0;   // Lowest - background auto-refresh
  static const int priorityUserAction = 10;   // Medium - user changed station/line
  static const int priorityManualRefresh = 20; // Highest - user pulled to refresh
}

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
  bool _backgroundRefreshing = false; // Silent background refresh flag
  String? _error;
  
  // ===== OPERATION QUEUE FOR O(1) COMPLEXITY =====
  
  // Single operation lock to prevent parallel execution
  bool _isOperationInProgress = false;
  
  // Pending operation (only store the most recent request)
  _PendingOperation? _pendingOperation;
  
  // ===== ADAPTIVE REFRESH FOR POOR NETWORK CONDITIONS =====
  
  Timer? _autoRefreshTimer;
  Duration? _currentRefreshInterval;
  static const Duration _defaultRefreshInterval = Duration(seconds: 30);
  static const Duration _slowNetworkInterval = Duration(seconds: 60); // Slower on poor network
  static const Duration _offlineInterval = Duration(seconds: 120); // Very slow when offline
  
  DateTime? _lastSuccessfulRefreshTime;
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
  bool get backgroundRefreshing => _backgroundRefreshing;
  String? get error => _error;
  bool get hasData => _data != null;
  bool get isAutoRefreshActive => _autoRefreshTimer != null && _autoRefreshTimer!.isActive;
  bool get isNetworkSlow => _isNetworkSlow;
  bool get isCircuitBreakerOpen => _circuitBreakerOpen;
  String get currentRefreshIntervalDescription => _currentRefreshInterval != null ? '${_currentRefreshInterval!.inSeconds}s' : '';
  DateTime? get lastRefreshTime => _lastSuccessfulRefreshTime;
  
  /// Load schedule with network-aware optimizations and seamless UI updates
  /// Uses background refresh to avoid jarring loading states
  /// OPTIMIZED: O(1) complexity with sequential execution (no parallel operations)
  /// 
  /// Priority levels (higher replaces lower in pending queue):
  /// - Auto-refresh (0): Background periodic updates
  /// - User action (10): Station/line selection changes
  /// - Manual refresh (20): Pull-to-refresh gesture
  Future<void> loadSchedule(
    String lineCode, 
    String stationCode, {
    bool forceRefresh = false,
    bool allowStaleCache = true,
    bool silentRefresh = false, // Don't show loading spinner if we have data
    int priority = 0, // Operation priority (0=auto-refresh, 10=user action, 20=manual refresh)
  }) async {
    // ===== SEQUENTIAL EXECUTION GUARD (O(1)) =====
    // If an operation is already in progress, store this as pending and return
    if (_isOperationInProgress) {
      debugPrint('MTR Schedule: Operation in progress, queuing request (priority: $priority)');
      
      // Only replace pending operation if new one has higher or equal priority
      if (_pendingOperation == null || priority >= _pendingOperation!.priority) {
        if (_pendingOperation != null) {
          debugPrint('MTR Schedule: Replacing pending operation (old priority: ${_pendingOperation!.priority}, new priority: $priority)');
        }
        
        // Store only the most recent highest-priority request
        _pendingOperation = _PendingOperation(
          lineCode: lineCode,
          stationCode: stationCode,
          forceRefresh: forceRefresh,
          allowStaleCache: allowStaleCache,
          silentRefresh: silentRefresh,
          priority: priority,
        );
      } else {
        debugPrint('MTR Schedule: Ignoring lower priority request (pending priority: ${_pendingOperation!.priority})');
      }
      return;
    }
    
    // Mark operation as in progress
    _isOperationInProgress = true;
    debugPrint('MTR Schedule: Starting operation (priority: $priority)');
    
    try {
      // Execute the actual load operation
      await _executeLoadSchedule(
        lineCode,
        stationCode,
        forceRefresh: forceRefresh,
        allowStaleCache: allowStaleCache,
        silentRefresh: silentRefresh,
      );
    } finally {
      // Mark operation as complete
      _isOperationInProgress = false;
      
      // Process pending operation if exists (O(1) - only one pending operation)
      if (_pendingOperation != null) {
        final pending = _pendingOperation!;
        _pendingOperation = null; // Clear pending before executing
        
        debugPrint('MTR Schedule: Processing pending operation (priority: ${pending.priority})');
        // Execute pending operation asynchronously (don't await to avoid recursion)
        unawaited(loadSchedule(
          pending.lineCode,
          pending.stationCode,
          forceRefresh: pending.forceRefresh,
          allowStaleCache: pending.allowStaleCache,
          silentRefresh: pending.silentRefresh,
          priority: pending.priority,
        ));
      }
    }
  }
  
  /// Internal method that executes the actual load logic
  /// Separated from loadSchedule() for sequential execution control
  Future<void> _executeLoadSchedule(
    String lineCode, 
    String stationCode, {
    required bool forceRefresh,
    required bool allowStaleCache,
    required bool silentRefresh,
  }) async {
    
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
    
    // Seamless refresh: Only show loading if we don't have data
    final hadData = _data != null;
    if (silentRefresh && hadData) {
      _backgroundRefreshing = true;
    } else {
      _loading = true;
      _error = null;
      // Don't clear data on force refresh to keep UI stable
    }
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
        // Only clear data if we don't have previous data
        if (!hadData || forceRefresh) {
          _data = null;
        }
        _error = schedule.message.isNotEmpty ? schedule.message : 'Unable to load schedule';
        _consecutiveErrors++;
      } else {
        _data = schedule;
        _error = null;
        _lastSuccessfulRefreshTime = DateTime.now();
        _consecutiveErrors = 0; // Reset on success
      }
    } catch (e) {
      final errorMessage = _formatError(e.toString());
      // Only show error if we don't have cached data
      if (!hadData || forceRefresh) {
        _error = errorMessage;
      } else {
        // Silent failure - keep showing old data
        debugPrint('MTR Schedule: Background refresh failed, keeping old data: $e');
      }
      debugPrint('MTR Schedule Error: $e');
      _consecutiveErrors++;
      
      // Open circuit breaker if too many errors
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _openCircuitBreaker();
      }
    } finally {
      _loading = false;
      _backgroundRefreshing = false;
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
  
  /// Start auto-refresh with adaptive intervals and seamless updates
  /// OPTIMIZED: Uses priority-based sequential execution (no parallel operations)
  void startAutoRefresh(String lineCode, String stationCode, {Duration? interval}) {
    stopAutoRefresh();
    
    // Use adaptive interval if not specified
    final refreshInterval = interval ?? _getAdaptiveInterval();
    _currentRefreshInterval = refreshInterval;
    
    debugPrint('MTR Auto-refresh: Starting with interval ${refreshInterval.inSeconds}s (priority: auto-refresh)');
    
    _autoRefreshTimer = Timer.periodic(refreshInterval, (_) async {
      // Check if we should adjust interval
      final adaptiveInterval = _getAdaptiveInterval();
      if (adaptiveInterval != _currentRefreshInterval) {
        debugPrint('MTR Auto-refresh: Restarting with new interval ${adaptiveInterval.inSeconds}s');
        startAutoRefresh(lineCode, stationCode, interval: adaptiveInterval);
        return;
      }
      
      debugPrint('MTR Auto-refresh: Background refresh $lineCode/$stationCode');
      // Use silent refresh with lowest priority (won't interrupt user actions)
      await loadSchedule(
        lineCode, 
        stationCode, 
        forceRefresh: false, // Allow stale-while-revalidate
        allowStaleCache: true,
        silentRefresh: true, // Don't show loading spinner during auto-refresh
        priority: _PendingOperation.priorityAutoRefresh, // Lowest priority
      );
    });
    
    // Immediate first load (can show loading indicator, medium priority)
    loadSchedule(
      lineCode, 
      stationCode, 
      forceRefresh: false, 
      allowStaleCache: true,
      silentRefresh: false, // Show loading on initial load
      priority: _PendingOperation.priorityUserAction, // Medium priority for initial load
    );
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
  /// Shows loading indicator but keeps old data visible during refresh
  /// OPTIMIZED: Uses highest priority to override auto-refresh operations
  Future<void> manualRefresh(String lineCode, String stationCode) async {
    _closeCircuitBreaker(); // Allow manual refresh to try
    await loadSchedule(
      lineCode, 
      stationCode, 
      forceRefresh: true, 
      allowStaleCache: false,
      silentRefresh: _data != null, // Silent if we have data, show loading if empty
      priority: _PendingOperation.priorityManualRefresh, // Highest priority - overrides everything
    );
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

class _MtrSchedulePageState extends State<MtrSchedulePage> with WidgetsBindingObserver, SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _autoRefreshInitialized = false;
  bool _isPageVisible = false; // Track if this page is currently visible to the user

  @override
  bool get wantKeepAlive => true; // Keep page state alive when switching tabs

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Detect if this page is currently visible in the PageView
    _checkPageVisibility();

    // Load auto-refresh preference and trigger auto-refresh on app start
    if (!_autoRefreshInitialized) {
      _autoRefreshInitialized = true;
      final schedule = context.read<MtrScheduleProvider>();
      final catalog = context.read<MtrCatalogProvider>();
      final devSettings = context.read<DeveloperSettingsProvider>();

      schedule.loadAutoRefreshPref().then((_) {
        // Auto-load selection if enabled
        catalog.initializeWithSettings(devSettings.mtrAutoLoadCachedSelection).then((_) {
          // After catalog is initialized, trigger auto-refresh if conditions are met
          if (_isPageVisible && catalog.hasSelection && schedule.autoRefreshEnabled) {
            if (!schedule.isAutoRefreshActive) {
              debugPrint('MTR Page: Auto-triggering auto-refresh on app start');
              schedule.startAutoRefresh(
                catalog.selectedLine!.lineCode,
                catalog.selectedStation!.stationCode,
              );
            }
          } else if (schedule.isAutoRefreshActive && (!catalog.hasSelection || !schedule.autoRefreshEnabled)) {
            schedule.stopAutoRefresh();
          }
        });
      });
    }
  }
  
  /// Check if this page is currently visible to the user
  /// This prevents auto-refresh from running when user is on a different tab
  void _checkPageVisibility() {
    final route = ModalRoute.of(context);
    final isCurrentRoute = route?.isCurrent ?? false;
    
    if (isCurrentRoute != _isPageVisible) {
      _isPageVisible = isCurrentRoute;
      _handleVisibilityChanged();
    }
  }
  
  /// Handle page visibility changes - start/stop auto-refresh accordingly
  void _handleVisibilityChanged() {
    final schedule = context.read<MtrScheduleProvider>();
    final catalog = context.read<MtrCatalogProvider>();
    
    if (_isPageVisible) {
      // Page became visible - resume auto-refresh if enabled and we have selection
      if (schedule.autoRefreshEnabled && catalog.hasSelection && !schedule.isAutoRefreshActive) {
        debugPrint('MTR Page: Resuming auto-refresh (page became visible)');
        schedule.startAutoRefresh(
          catalog.selectedLine!.lineCode,
          catalog.selectedStation!.stationCode,
        );
      }
    } else {
      // Page became hidden - stop auto-refresh to save resources
      if (schedule.isAutoRefreshActive) {
        debugPrint('MTR Page: Pausing auto-refresh (page is hidden)');
        schedule.stopAutoRefresh();
      }
    }
  }
  
  late final AnimationController _refreshAnimController;
  late final Animation<double> _refreshRotation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCatalogAndSchedule();
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
  
  /// Initialize catalog and schedule based on auto-load setting
  void _initializeCatalogAndSchedule() {
    final catalog = context.read<MtrCatalogProvider>();
    final devSettings = context.read<DeveloperSettingsProvider>();
    
    // Apply user preference for auto-loading cached selection
    catalog.initializeWithSettings(devSettings.mtrAutoLoadCachedSelection).then((_) {
      // After catalog is initialized with user preference, load schedule if appropriate
      if (devSettings.mtrAutoLoadCachedSelection && catalog.hasSelection) {
        _loadScheduleIfNeeded();
      }
    });
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
      // Resume auto-refresh only if page is visible AND auto-refresh is enabled
      if (_isPageVisible && catalog.hasSelection && schedule.autoRefreshEnabled) {
        debugPrint('MTR Page: App resumed, page is visible - refreshing data');
        // App resumed - use user action priority
        schedule.loadSchedule(
          catalog.selectedLine!.lineCode,
          catalog.selectedStation!.stationCode,
          forceRefresh: true,
          priority: _PendingOperation.priorityUserAction,
        );
        if (!schedule.isAutoRefreshActive) {
          schedule.startAutoRefresh(
            catalog.selectedLine!.lineCode,
            catalog.selectedStation!.stationCode,
          );
        }
      } else if (!_isPageVisible) {
        debugPrint('MTR Page: App resumed, but page is hidden - skipping refresh');
      }
    } else if (state == AppLifecycleState.paused) {
      // Always stop auto-refresh when app goes to background
      if (schedule.isAutoRefreshActive) {
        debugPrint('MTR Page: App paused - stopping auto-refresh');
        schedule.stopAutoRefresh();
      }
    }
  }

  void _loadScheduleIfNeeded() {
    final catalog = context.read<MtrCatalogProvider>();
    final schedule = context.read<MtrScheduleProvider>();
    final devSettings = context.read<DeveloperSettingsProvider>();
    
    // Only auto-load schedule if user has enabled auto-load AND we have a selection
    final shouldAutoLoad = devSettings.mtrAutoLoadCachedSelection && catalog.hasSelection;
    
    if (shouldAutoLoad && !schedule.hasData && !schedule.loading) {
      // Initial load from cached selection - use user action priority
      schedule.loadSchedule(
        catalog.selectedLine!.lineCode,
        catalog.selectedStation!.stationCode,
        priority: _PendingOperation.priorityUserAction,
      );
    }
    // Start/stop auto-refresh based on cached preference and page visibility
    // IMPORTANT: Only start auto-refresh if the MTR page is currently visible
    if (shouldAutoLoad && _isPageVisible) {
      if (schedule.autoRefreshEnabled) {
        if (!schedule.isAutoRefreshActive) {
          debugPrint('MTR Page: Starting auto-refresh (page is visible)');
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
    } else if (!_isPageVisible && schedule.isAutoRefreshActive) {
      // Stop auto-refresh if page is not visible
      debugPrint('MTR Page: Stopping auto-refresh (page is hidden)');
      schedule.stopAutoRefresh();
    }
  }

  /// Build compact, informative, full-bleed status banner
  Widget _buildStatusBanner(
    BuildContext context,
    MtrCatalogProvider catalog,
    MtrScheduleProvider schedule,
    LanguageProvider lang,
    ColorScheme colorScheme,
  ) {
    // Determine status
    final hasData = schedule.hasData;
    final isError = schedule.data?.status != 1;
    final isDelay = schedule.data?.isDelay ?? false;
    final isRefreshing = schedule.backgroundRefreshing;
    
    // Get train count for emphasis (count all trains across all directions)
    final totalTrains = schedule.data?.directionTrains.values
        .fold<int>(0, (sum, trains) => sum + trains.length) ?? 0;
    
    // Status colors and icons
    Color statusColor;
    Color bgColor;
    IconData statusIcon;
    String statusText;
    String statusDetail;
    
    if (!hasData) {
      statusColor = colorScheme.onSurfaceVariant;
      bgColor = colorScheme.surfaceContainerHighest;
      statusIcon = Icons.info_outline;
      statusText = lang.isEnglish ? 'No Station Selected' : '未選擇車站';
      statusDetail = lang.isEnglish ? 'Tap to select line & station' : '點擊選擇線路及車站';
    } else if (isError) {
      statusColor = const Color(0xFFD32F2F); // Red
      bgColor = const Color(0xFFFFEBEE); // Light red
      statusIcon = Icons.error_outline;
      statusText = lang.isEnglish ? 'Service Disrupted' : '服務受阻';
      statusDetail = lang.isEnglish ? 'Check MTR official updates' : '請查閱港鐵官方通告';
    } else if (isDelay) {
      statusColor = const Color(0xFFF57C00); // Orange
      bgColor = const Color(0xFFFFF3E0); // Light orange
      statusIcon = Icons.warning_amber_rounded;
      statusText = lang.isEnglish ? 'Service Delayed' : '服務延誤';
      statusDetail = lang.isEnglish 
          ? 'Trains running with delays'
          : '列車運行受到延誤';
    } else if (isRefreshing) {
      statusColor = colorScheme.primary;
      bgColor = colorScheme.primaryContainer.withOpacity(0.3);
      statusIcon = Icons.refresh_rounded;
      statusText = lang.isEnglish ? 'Updating Schedule...' : '正在更新班次';
      statusDetail = lang.isEnglish 
          ? 'Fetching latest train times'
          : '獲取最新列車時間';
    } else {
      statusColor = const Color(0xFF2E7D32); // Green
      bgColor = const Color(0xFFE8F5E9); // Light green
      statusIcon = Icons.check_circle_outline;
      statusText = lang.isEnglish ? 'Normal Service' : '服務正常';
      statusDetail = lang.isEnglish 
          ? '$totalTrains trains tracked'
          : '追蹤 $totalTrains 班列車';
    }
    
    // Display current date and time from API response
    String? updateTime;
    String? updateTimeDetail; // Full date/time for tooltip
    String? timeSource; // Indicator of data source
    DateTime? sourceTime;
    bool isSystemTime = false;
    
    // Prefer system time from API response (more accurate than local refresh time)
    if (hasData && schedule.data?.systemTime != null) {
      sourceTime = schedule.data!.systemTime;
      isSystemTime = true;
      timeSource = lang.isEnglish ? 'MTR System Time' : 'MTR系統時間';
    } else if (hasData && schedule.data?.currentTime != null) {
      sourceTime = schedule.data!.currentTime;
      isSystemTime = true;
      timeSource = lang.isEnglish ? 'Station Time' : '車站時間';
    } else if (schedule.lastRefreshTime != null) {
      sourceTime = schedule.lastRefreshTime;
      isSystemTime = false;
      timeSource = lang.isEnglish ? 'Last Refresh' : '上次更新';
    }
    
    if (sourceTime != null) {
      // Format current date and time (not relative time)
      // Show time in HH:MM format for compact display
      updateTime = '${sourceTime.hour.toString().padLeft(2, '0')}:${sourceTime.minute.toString().padLeft(2, '0')}';
      
      // Format full date/time for tooltip with source
      final dateTimeStr = lang.isEnglish
          ? '${sourceTime.year}-${sourceTime.month.toString().padLeft(2, '0')}-${sourceTime.day.toString().padLeft(2, '0')} '
            '${sourceTime.hour.toString().padLeft(2, '0')}:${sourceTime.minute.toString().padLeft(2, '0')}:${sourceTime.second.toString().padLeft(2, '0')}'
          : '${sourceTime.year}年${sourceTime.month}月${sourceTime.day}日 '
            '${sourceTime.hour.toString().padLeft(2, '0')}:${sourceTime.minute.toString().padLeft(2, '0')}:${sourceTime.second.toString().padLeft(2, '0')}';
      
      updateTimeDetail = lang.isEnglish
          ? '$timeSource\n$dateTimeStr'
          : '$timeSource\n$dateTimeStr';
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: statusColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Emphasized status indicator
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              statusIcon,
              size: 16,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          
          // Status text with detail
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  statusDetail,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: statusColor.withOpacity(0.75),
                    letterSpacing: 0.1,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Update time with detailed tooltip
          if (updateTime != null) ...[
            Tooltip(
              message: updateTimeDetail ?? updateTime,
              preferBelow: true,
              verticalOffset: 10,
              textStyle: const TextStyle(
                fontSize: 11,
                color: Colors.white,
              ),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon varies based on data source
                    Icon(
                      isSystemTime ? Icons.cloud_sync_rounded : Icons.schedule_rounded,
                      size: 13,
                      color: statusColor.withOpacity(0.9),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      updateTime,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          
          // Enhanced auto-refresh toggle with detailed state
          Tooltip(
            message: schedule.isAutoRefreshActive
                ? (lang.isEnglish 
                    ? 'Auto-refresh ON\nSchedule updates every 30s\nTap to disable'
                    : '自動更新：開啟\n每30秒更新班次\n點擊以關閉')
                : (lang.isEnglish
                    ? 'Auto-refresh OFF\nTap to enable automatic updates'
                    : '自動更新：關閉\n點擊以開啟自動更新'),
            preferBelow: true,
            verticalOffset: 10,
            textStyle: const TextStyle(fontSize: 11, color: Colors.white),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
            ),
            child: InkWell(
              onTap: catalog.hasSelection
                  ? () async {
                      HapticFeedback.lightImpact();
                      if (schedule.isAutoRefreshActive) {
                        await schedule.saveAutoRefreshPref(false); // Cache toggle state first
                        schedule.stopAutoRefresh();
                      } else {
                        await schedule.saveAutoRefreshPref(true); // Cache toggle state first
                        schedule.startAutoRefresh(
                          catalog.selectedLine!.lineCode,
                          catalog.selectedStation!.stationCode,
                        );
                      }
                    }
                  : null,
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: schedule.isAutoRefreshActive
                      ? statusColor.withOpacity(0.18)
                      : statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: schedule.isAutoRefreshActive
                        ? statusColor.withOpacity(0.5)
                        : statusColor.withOpacity(0.25),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated refresh icon
                    RotationTransition(
                      turns: _refreshRotation,
                      child: Icon(
                        Icons.autorenew_rounded,
                        size: 15,
                        color: schedule.isAutoRefreshActive
                            ? statusColor
                            : statusColor.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 5),
                    // Status text
                    Text(
                      schedule.isAutoRefreshActive
                          ? (lang.isEnglish ? 'AUTO' : '自動')
                          : (lang.isEnglish ? 'OFF' : '關閉'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: schedule.isAutoRefreshActive
                            ? statusColor
                            : statusColor.withOpacity(0.5),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Check page visibility on every rebuild
    _checkPageVisibility();
    
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
              // User changed line - use user action priority
              schedule.loadSchedule(
                line.lineCode,
                catalog.selectedStation!.stationCode,
                forceRefresh: true,
                priority: _PendingOperation.priorityUserAction,
              );
              if (schedule.autoRefreshEnabled) {
                schedule.startAutoRefresh(line.lineCode, catalog.selectedStation!.stationCode);
              } else if (schedule.isAutoRefreshActive) {
                schedule.stopAutoRefresh();
              }
            }
          },
          onStationChanged: (station) async {
            await catalog.selectStation(station);
            if (catalog.selectedLine != null) {
              // User changed station - use user action priority
              schedule.loadSchedule(
                catalog.selectedLine!.lineCode,
                station.stationCode,
                forceRefresh: true,
                priority: _PendingOperation.priorityUserAction,
              );
              if (schedule.autoRefreshEnabled) {
                schedule.startAutoRefresh(catalog.selectedLine!.lineCode, station.stationCode);
              } else if (schedule.isAutoRefreshActive) {
                schedule.stopAutoRefresh();
              }
            }
          },
        ),
        // Optimized full-bleed status banner with compact, informative design
        _buildStatusBanner(context, catalog, schedule, lang, colorScheme),
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

class _MtrSelectorState extends State<_MtrSelector> with TickerProviderStateMixin {
  static const String _stationExpandPrefKey = 'mtr_station_dropdown_expanded';
  static const String _lineExpandPrefKey = 'mtr_line_dropdown_expanded';
  bool _showStations = true;
  bool _showLines = true;
  late AnimationController _animController;
  late AnimationController _lineExpandController;
  late AnimationController _stationExpandController;
  late Animation<double> _lineExpandAnimation;
  late Animation<double> _stationExpandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animController.forward();

    // Line dropdown expand/collapse animation
    _lineExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _lineExpandAnimation = CurvedAnimation(
      parent: _lineExpandController,
      curve: Curves.easeInOut,
    );

    // Station dropdown expand/collapse animation
    _stationExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _stationExpandAnimation = CurvedAnimation(
      parent: _stationExpandController,
      curve: Curves.easeInOut,
    );

    _loadExpandPrefs();

    // Ensure cached selection is applied and chips are highlighted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final catalog = context.read<MtrCatalogProvider>();
      catalog.applyCachedSelection();
    });
  }

  Future<void> _loadExpandPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stationExpanded = prefs.getBool(_stationExpandPrefKey) ?? true;
      final lineExpanded = prefs.getBool(_lineExpandPrefKey) ?? true;
      
      setState(() {
        _showStations = stationExpanded;
        _showLines = lineExpanded;
      });
      
      // Initialize animation controllers to match saved state
      if (_showStations) {
        _stationExpandController.value = 1.0;
      }
      if (_showLines) {
        _lineExpandController.value = 1.0;
      }
    } catch (_) {}
  }

  Future<void> _saveStationExpandPref(bool expanded) async {
    setState(() {
      _showStations = expanded;
    });
    
    // Animate expand/collapse
    if (expanded) {
      _stationExpandController.forward();
    } else {
      _stationExpandController.reverse();
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_stationExpandPrefKey, expanded);
    } catch (_) {}
  }

  Future<void> _saveLineExpandPref(bool expanded) async {
    setState(() {
      _showLines = expanded;
    });
    
    // Animate expand/collapse
    if (expanded) {
      _lineExpandController.forward();
    } else {
      _lineExpandController.reverse();
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lineExpandPrefKey, expanded);
    } catch (_) {}
  }

  @override
  void dispose() {
    _animController.dispose();
    _lineExpandController.dispose();
    _stationExpandController.dispose();
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
            content: SizeTransition(
              sizeFactor: _lineExpandAnimation,
              axisAlignment: -1.0,
              child: FadeTransition(
                opacity: _lineExpandAnimation,
                child: Wrap(
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
                ),
              ),
            ),
          ),

          // Station Selector Card
          if (widget.selectedLine != null && filteredStations.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildStationSelectorWithDirections(
              context: context,
              catalog: catalog,
              lang: lang,
              filteredStations: filteredStations,
              colorScheme: colorScheme,
            ),
          ],
          
          // Direction Filter Card (separate container) - Only for through trains
          if (widget.selectedLine != null && widget.selectedStation != null) ...[
            const SizedBox(height: 8),
            _buildDirectionFilter(
              context: context,
              catalog: catalog,
              lang: lang,
              colorScheme: colorScheme,
            ),
          ],
        ],
      ),
    );
  }
  
  /// Build station selector
  Widget _buildStationSelectorWithDirections({
    required BuildContext context,
    required MtrCatalogProvider catalog,
    required LanguageProvider lang,
    required List<MtrStation> filteredStations,
    required ColorScheme colorScheme,
  }) {
    // Build station list content
    final stationListContent = SizeTransition(
      sizeFactor: _stationExpandAnimation,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _stationExpandAnimation,
        child: Wrap(
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
        ),
      ),
    );
    
    // Use unified _buildSelectorCard for consistency
    return _buildSelectorCard(
      context: context,
      icon: Icons.location_on_outlined,
      title: widget.selectedStation != null
          ? widget.selectedStation!.displayName(lang.isEnglish)
          : lang.isEnglish ? 'Select Station' : '選擇車站',
      color: widget.selectedLine!.lineColor,
      isExpanded: _showStations,
      showToggle: true,
      onToggle: () => _saveStationExpandPref(!_showStations),
      trailing: widget.selectedStation != null && widget.selectedStation!.isInterchange
          ? _buildCompactInterchangeIndicator(context, widget.selectedStation!)
          : null,
      content: stationListContent,
    );
  }
  
  /// Build direction filter as separate container
  Widget _buildDirectionFilter({
    required BuildContext context,
    required MtrCatalogProvider catalog,
    required LanguageProvider lang,
    required ColorScheme colorScheme,
  }) {
    final directions = catalog.availableDirections;
    final selectedDirection = catalog.selectedDirection;
    final hasDirections = directions.isNotEmpty;
    
    // Check if selected station is a terminus station
    final isTerminus = widget.selectedStation != null && 
                       widget.selectedLine != null &&
                       widget.selectedLine!.isTerminusStation(widget.selectedStation!.stationCode);
    
      // Only show direction filter for through trains (non-terminus stations)
      if (!hasDirections || widget.selectedStation == null || isTerminus) {
        // If switching to a terminus, reset direction selection to avoid crash
        if (isTerminus && selectedDirection != null && selectedDirection.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            catalog.selectDirection('');
          });
        }
        return const SizedBox.shrink();
      }
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(UIConstants.cardRadius),
        border: Border.all(
          color: widget.selectedLine!.lineColor.withOpacity(UIConstants.cardBorderOpacity),
          width: UIConstants.cardBorderWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UIConstants.cardPadding,
          vertical: 4,
        ),
        child: Row(
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 15,
              color: widget.selectedLine!.lineColor,
            ),
            const SizedBox(width: 6),
            Text(
              lang.isEnglish ? 'Direction' : '方向',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                fontSize: UIConstants.chipFontSize + 1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _buildCompactDirectionButton(
                    context: context,
                    label: lang.isEnglish ? 'All' : '全部',
                    isSelected: selectedDirection == null || selectedDirection.isEmpty,
                    color: widget.selectedLine!.lineColor,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      catalog.selectDirection('');
                      SharedPreferences.getInstance().then((prefs) {
                        prefs.remove('mtr_selected_direction');
                      });
                    },
                  ),
                  ...directions.map((dir) {
                    return _buildCompactDirectionButton(
                      context: context,
                      label: _formatDirectionLabel(dir, lang.isEnglish),
                      isSelected: selectedDirection == dir,
                      color: widget.selectedLine!.lineColor,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        catalog.selectDirection(dir);
                      },
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build compact direction button for inline display
  Widget _buildCompactDirectionButton({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(UIConstants.chipRadius),
      splashColor: color.withOpacity(0.15),
      highlightColor: color.withOpacity(0.08),
      hoverColor: color.withOpacity(0.05),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        // Use consistent chip padding for uniform appearance
        padding: const EdgeInsets.symmetric(
          horizontal: UIConstants.chipPaddingH,
          vertical: UIConstants.chipPaddingV,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(UIConstants.chipRadius),
          border: Border.all(
            color: isSelected 
                ? color.withOpacity(UIConstants.selectedChipBorderOpacity)
                : colorScheme.outline.withOpacity(UIConstants.chipBorderOpacity),
            width: isSelected ? UIConstants.selectedChipBorderWidth : UIConstants.chipBorderWidth,
          ),
          // Subtle shadow for selected state
          boxShadow: isSelected ? [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          style: TextStyle(
            fontSize: UIConstants.chipFontSize,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? color : colorScheme.onSurfaceVariant,
          ),
          child: Text(label),
        ),
      ),
    );
  }
  
  /// Format direction label for display
  String _formatDirectionLabel(String direction, bool isEnglish) {
    // Map common direction codes to user-friendly labels
    switch (direction.toUpperCase()) {
      case 'UP':
        return isEnglish ? 'Up' : '上行';
      case 'DOWN':
        return isEnglish ? 'Down' : '下行';
      case 'IN':
        return isEnglish ? 'Inbound' : '入站';
      case 'OUT':
        return isEnglish ? 'Outbound' : '出站';
      default:
        return direction; // Return as-is if not a known code
    }
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
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
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
          // Unified expand/collapse animation with consistent timing
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: content != null && isExpanded
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        UIConstants.cardPadding,
                        4,
                        UIConstants.cardPadding,
                        UIConstants.cardPadding,
                      ),
                      child: content,
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
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
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UIConstants.chipRadius),
        splashColor: color.withOpacity(0.15),
        highlightColor: color.withOpacity(0.08),
        hoverColor: color.withOpacity(0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(
            horizontal: UIConstants.chipPaddingH, 
            vertical: UIConstants.chipPaddingV,
          ),
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
            // Subtle shadow for selected chips
            boxShadow: isSelected ? [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingWidget != null) ...[
                leadingWidget,
                const SizedBox(width: UIConstants.selectorSpacing),
              ],
              // Animated check icon (fade only, no scale)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: isSelected
                    ? Padding(
                        key: const ValueKey('check'),
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check_circle,
                          size: UIConstants.checkIconSize,
                          color: color,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-check')),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated text properties
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      style: TextStyle(
                        fontSize: UIConstants.chipFontSize,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: textColor,
                      ),
                      child: Text(label),
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
    );
  }  Widget _buildInterchangeIndicator(BuildContext context, MtrStation station) {
    if (!station.isInterchange || station.interchangeLines.isEmpty) {
      // Return empty SizedBox to maintain layout without visual element
      return const SizedBox.shrink();
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
      return const SizedBox.shrink();
    }

    return Tooltip(
      message: lang.isEnglish 
          ? 'Interchange station'
          : '轉車站',
      child: Container(
        // Remove fixed height - let content determine height naturally
        // Use minimal padding to fit within chip's vertical padding
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
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
              size: UIConstants.compareIconSize,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            const SizedBox(width: 3),
            ...lineColors.take(3).map((color) => Container(
              width: 8,
              height: 8,
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
                    fontSize: UIConstants.chipSubtitleFontSize,
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
    final interchangeLineCodes = station.interchangeLines;

    // Emphasized container with label and animation
    return Tooltip(
      message: lang.isEnglish
          ? 'Tap to switch line'
          : '\u9ede\u64ca\u5207\u63db\u7dab\u8def',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(0.13),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: colorScheme.primary,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_arrows,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Text(
              lang.isEnglish ? 'Lines' : '轉綫',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
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
                    final targetLine = widget.lines.firstWhere(
                      (line) => line.lineCode == lineCode,
                      orElse: () => widget.lines.first,
                    );
                    final stationOnNewLine = targetLine.stations.firstWhere(
                      (s) => s.stationCode == station.stationCode,
                      orElse: () => targetLine.stations.first,
                    );
                    HapticFeedback.selectionClick();
                    await catalog.selectLineAndStation(targetLine, stationOnNewLine);
                    widget.onLineChanged(targetLine);
                    widget.onStationChanged(stationOnNewLine);
                  },
                  borderRadius: BorderRadius.circular(4),
                  splashColor: lineColor.withOpacity(0.25),
                  highlightColor: lineColor.withOpacity(0.08),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.train,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (interchangeLineCodes.length > 4)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '+${interchangeLineCodes.length - 4}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
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
    final catalog = context.watch<MtrCatalogProvider>();
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
      // Filter directions based on selected direction
      final selectedDirection = catalog.selectedDirection;
      var directionEntries = data!.directionTrains.entries.toList();
      
      // Apply direction filter if a specific direction is selected
      if (selectedDirection != null && selectedDirection.isNotEmpty) {
        directionEntries = directionEntries.where((entry) {
          return entry.key.toUpperCase() == selectedDirection.toUpperCase();
        }).toList();
      }
      
      // Handle case where filtering results in no trains
      if (directionEntries.isEmpty) {
        content = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Center(
              child: Text(
                lang.isEnglish 
                  ? 'No trains for this direction' 
                  : '此方向沒有列車',
              ),
            ),
          ],
        );
      } else {
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
                            
                            // Simple fade-in animation from top to bottom
                            return AnimatedOpacity(
                              key: ValueKey(train.hashCode),
                              opacity: 1.0,
                              duration: Duration(milliseconds: 150 + (idx * 30)),
                              curve: Curves.easeOut,
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
