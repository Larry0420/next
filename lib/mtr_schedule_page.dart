import 'dart:async';
import 'dart:convert';
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
  
  Future<MtrScheduleResponse> fetchSchedule(String lineCode, String stationCode) async {
    try {
      final url = Uri.parse('$_baseUrl?line=$lineCode&sta=$stationCode');
      debugPrint('MTR API: Fetching schedule for line=$lineCode, station=$stationCode');
      
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return MtrScheduleResponse.fromJson(json);
      } else {
        throw Exception('MTR API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('MTR API Error: $e');
      rethrow;
    }
  }
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
  
  MtrTrainInfo({
    required this.destination,
    required this.platform,
    required this.time,
    this.timeInMinutes,
    this.sequence,
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
    );
  }
  
  bool get isArriving => time.toLowerCase().contains('arriving') || time == '-';
  
  String get displayTime {
    // Use timeInMinutes (ttnt: Time to Next Train in minutes)
    if (timeInMinutes != null) {
      final minutes = timeInMinutes!;
      if (minutes <= 0) return 'Arriving';
      
      if (minutes == 1) {
        return '1 min';
      } else {
        return '$minutes mins';
      }
    }
    
    // Fallback to time field if ttnt is not available
    if (time.isEmpty) return '-';
    if (time.toUpperCase() == 'ARR' || isArriving) return 'Arriving';
    return time;
  }

  bool get isDueSoon {
    if (isArriving) return true;
    if (timeInMinutes != null) return timeInMinutes! <= 1;
    return false;
  }

  String get etaDescription {
    if (isArriving) return 'Arriving';
    if (timeInMinutes != null) {
      final minutes = timeInMinutes!;
      if (minutes <= 0) return 'Arriving';
      if (minutes == 1) return '1 min';
      return '$minutes mins';
    }
    return displayTime;
  }

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
  'TML': _LineMetadata('Tuen Ma Line', '屯馬綫', Color.fromRGBO(255, 51, 173, 0.644)),
  'TKL': _LineMetadata('Tseung Kwan O Line', '將軍澳綫', Color(0xFF92278F)),
  'EAL': _LineMetadata('East Rail Line', '東鐵綫', Color(0xFF0055B8)),
  'SIL': _LineMetadata('South Island Line', '南港島綫', Color.fromRGBO(186, 196, 4, 0.75)),
  'TWL': _LineMetadata('Tsuen Wan Line', '荃灣綫', Color(0xFFE60012)),
  'ISL': _LineMetadata('Island Line', '港島綫', Color(0xFF0075C2)),
  'KTL': _LineMetadata('Kwun Tong Line', '觀塘綫', Color(0xFF00A040)),
  'DRL': _LineMetadata('Disneyland Resort Line', '迪士尼綫', Color(0xFFE45DBF)),
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
  // === Auto-refresh state ===
  Timer? _autoRefreshTimer;
  Duration? _currentRefreshInterval;
  static const Duration _defaultRefreshInterval = Duration(seconds: 30);
  DateTime? _lastRefreshTime;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  
  MtrScheduleResponse? get data => _data;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _data != null;
  bool get isAutoRefreshActive => _autoRefreshTimer != null && _autoRefreshTimer!.isActive;
  String get currentRefreshIntervalDescription => _currentRefreshInterval != null ? '${_currentRefreshInterval!.inSeconds}s' : '';
  
  Future<void> loadSchedule(String lineCode, String stationCode, {bool forceRefresh = false}) async {
    if (_loading) return;
    
    _loading = true;
    _error = null;
    if (forceRefresh) _data = null;
    notifyListeners();
    
    try {
      final schedule = await _api.fetchSchedule(lineCode, stationCode);
      if (schedule.status != 1) {
        _data = null;
        _error = schedule.message.isNotEmpty ? schedule.message : 'Unable to load schedule';
      } else {
        _data = schedule;
        _error = null;
        _lastRefreshTime = DateTime.now();
        _consecutiveErrors = 0;
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('MTR Schedule Error: $e');
      _consecutiveErrors++;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
  void startAutoRefresh(String lineCode, String stationCode, {Duration? interval}) {
    stopAutoRefresh();
    final refreshInterval = interval ?? _defaultRefreshInterval;
    _currentRefreshInterval = refreshInterval;
    _autoRefreshTimer = Timer.periodic(refreshInterval, (_) async {
      debugPrint('MTR Auto-refresh: refreshing $lineCode/$stationCode');
      await loadSchedule(lineCode, stationCode, forceRefresh: true);
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        debugPrint('MTR Auto-refresh: too many errors, stopping');
        stopAutoRefresh();
      }
    });
    // Immediate refresh
    loadSchedule(lineCode, stationCode, forceRefresh: true);
    notifyListeners();
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    notifyListeners();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduleIfNeeded();
    });
    _refreshAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
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
      // Resume auto-refresh if selection exists
      if (catalog.hasSelection) {
        schedule.loadSchedule(
          catalog.selectedLine!.lineCode,
          catalog.selectedStation!.stationCode,
          forceRefresh: true,
        );
        schedule.startAutoRefresh(
          catalog.selectedLine!.lineCode,
          catalog.selectedStation!.stationCode,
        );
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
        // Auto-refresh control bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _refreshAnimController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: schedule.isAutoRefreshActive ? _refreshAnimController.value * 6.28319 : 0, // 2*pi
                          child: Icon(Icons.refresh, color: colorScheme.primary),
                        );
                      },
                    ),
                    if (schedule.isAutoRefreshActive)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: schedule.isAutoRefreshActive
                    ? (lang.isEnglish ? 'Auto-refresh ON (${schedule.currentRefreshIntervalDescription})' : '自動刷新已啟用 (${schedule.currentRefreshIntervalDescription})')
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
              const SizedBox(width: 8),
              Text(
                schedule.isAutoRefreshActive
                    ? (lang.isEnglish ? 'Auto-refresh enabled' : '自動刷新中')
                    : (lang.isEnglish ? 'Manual refresh' : '手動刷新'),
                style: TextStyle(
                  color: schedule.isAutoRefreshActive ? Colors.green : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (schedule._lastRefreshTime != null)
                Text(
                  '${lang.isEnglish ? 'Last updated' : '最後更新'}: '
                  '${TimeOfDay.fromDateTime(schedule._lastRefreshTime!).format(context)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
                  ? const Icon(Icons.compare_arrows, size: 16)
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
                        ? const Icon(Icons.compare_arrows, size: 12)
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
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: content != null && isExpanded
                ? Container(
                    padding: const EdgeInsets.fromLTRB(UIConstants.cardPadding, 4, UIConstants.cardPadding, UIConstants.cardPadding),
                    child: content,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
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
    
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return AnimatedContainer(
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
                              color: isSelected ? color : colorScheme.onSurface,
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
        );
      },
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
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 160),
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
  // Unified status header is always shown as index 0
      content = ListView.builder(
        padding: const EdgeInsets.all(8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: directionEntries.length + 1, // One unified status header card
        itemBuilder: (context, index) {
          // Unified Train Services Status header card
          if (index == 0) {
            final isError = data!.status != 1;
            final hasDelay = data!.isDelay;
            final colorScheme = Theme.of(context).colorScheme;
            Color bg;
            Color? fg;
            IconData icon;
            String title;
            if (isError) {
              bg = Colors.red.withOpacity(0.1);
              fg = Colors.red[800];
              icon = Icons.error_outline;
              title = lang.isEnglish ? 'Train Services Status' : '列車服務狀態';
            } else if (hasDelay) {
              bg = Colors.orange.withOpacity(0.12);
              fg = Colors.orange[800];
              icon = Icons.schedule;
              title = lang.isEnglish ? 'Train Services Status' : '列車服務狀態';
            } else {
              bg = colorScheme.surface;
              fg = colorScheme.onSurface;
              icon = Icons.check_circle_outline;
              title = lang.isEnglish ? 'Train Services Status' : '列車服務狀態';
            }

            final ts = data!.systemTime ?? data!.currentTime;
            final timeText = ts != null ? TimeOfDay.fromDateTime(ts).format(context) : '-';
            final suffix = lang.isEnglish ? 'HKT' : '';
            final message = data!.message.isNotEmpty
                ? data!.message
                : (isError
                    ? (lang.isEnglish ? 'Service alert issued.' : '服務提示已發出。')
                    : (hasDelay
                        ? (lang.isEnglish ? 'Possible delays reported.' : '可能出現延誤。')
                        : (lang.isEnglish ? 'Services normal.' : '服務正常。')));

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              color: bg,
              child: ListTile(
                leading: Icon(icon, color: fg),
                title: Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: TextStyle(color: fg)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${lang.isEnglish ? 'Last updated' : '最後更新'}: ${timeText} ${suffix}'.trim(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          final entryIndex = index - 1;
          final entry = directionEntries.elementAt(entryIndex);
          final directionKey = entry.key;
          final trains = entry.value;
          final termini = line?.directionDisplayNames(directionKey, stationNameResolver) ?? const <String>[];

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
          
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(UIConstants.cardRadius),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.train, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${directionLabel(directionKey)} ${lang.isEnglish ? 'departures' : '開出'}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (terminusLabel != null)
                              Text(
                                '${lang.isEnglish ? 'Terminus' : '終點站'}: $terminusLabel',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (trains.isEmpty)
                    Text(lang.isEnglish ? 'No trains scheduled' : '暫無班次')
                  else
                    ...trains.map((train) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                      leading: Icon(
                        train.isDueSoon ? Icons.circle : Icons.schedule,
                        size: 20,
                        color: train.isDueSoon ? Colors.green : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        train.displayDestination(stationNameResolver, isEnglish: lang.isEnglish),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      subtitle: Builder(
                        builder: (context) {
                          final colorScheme = Theme.of(context).colorScheme;
                          final minutesVal = train.timeInMinutes;
                          final minutesLabel = () {
                            if (minutesVal == null) return '-';
                            if (lang.isEnglish) {
                              if (minutesVal <= 0) return '0 min';
                              if (minutesVal == 1) return '1 min';
                              return '$minutesVal mins';
                            } else {
                              // Chinese: always use 分鐘, no singular form
                              final v = minutesVal < 0 ? 0 : minutesVal;
                              return '$v 分鐘';
                            }
                          }();

                          final timeUpper = train.time.toUpperCase();
                          String statusLabel = '';
                          // Determine status with thresholds:
                          // - Departing: <= 0 min or explicit DEP
                          // - Arriving: <= 2 mins or explicit ARR
                          if ((minutesVal != null && minutesVal <= 0) || timeUpper == 'DEP') {
                            statusLabel = lang.isEnglish ? 'Departing' : '即將開出';
                          } else if ((minutesVal != null && minutesVal <= 2) || timeUpper == 'ARR' || train.isArriving) {
                            statusLabel = lang.isEnglish ? 'Arriving' : '即將到站';
                          }

                          final List<Widget> parts = [];

                          // Platform chip (emphasized)
                          if (devSettings.showMtrArrivalDetails && train.platform.isNotEmpty) {
                            parts.add(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.primary.withOpacity(0.3), width: 1),
                              ),
                              child: Text(
                                '${lang.platform} ${train.platform}',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                                ),
                              ),
                            ));
                          }

                          Widget sep() => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '|',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              );

                          // Minutes
                          if (minutesLabel.isNotEmpty) {
                            if (parts.isNotEmpty) parts.add(sep());
                            parts.add(Text(
                              minutesLabel,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ));
                          }

                          // Status
                          if (statusLabel.isNotEmpty) {
                            if (parts.isNotEmpty) parts.add(sep());
                            final isArriving = statusLabel == (lang.isEnglish ? 'Arriving' : '即將到站');
                            final isDeparting = statusLabel == (lang.isEnglish ? 'Departing' : '即將開出');
                            parts.add(Text(
                              statusLabel,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isArriving
                                        ? Colors.green
                                        : isDeparting
                                            ? Colors.orange
                                            : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ));
                          }

                          return Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: parts,
                          );
                        },
                      ),
                    )),
                ],
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
}
