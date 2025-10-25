import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:animations/animations.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:implicitly_animated_reorderable_list_2/implicitly_animated_reorderable_list_2.dart';
import 'package:implicitly_animated_reorderable_list_2/transitions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ========================= Station Grouping (Top-level) =========================
class _StationGroupInfo {
  const _StationGroupInfo(this.name, this.nameEn, this.stationIds);
  final String name;
  final String nameEn;
  final Set<int> stationIds;
}

// Single source of truth for all station groupings, based on the Light Rail map.
const _stationGroups = [
  // Tin Shui Wai (Zone 4 & 5A)
  _StationGroupInfo('天水圍北', 'Tin Shui Wai North', {490, 500, 510, 520, 530, 540, 550}),
  _StationGroupInfo('天水圍南', 'Tin Shui Wai South', {430, 435, 445, 448, 450, 455, 460, 468, 480}),

  // Yuen Long (Zone 4 & 5)
  _StationGroupInfo('元朗市中心', 'Yuen Long Central', {560, 570, 580, 590, 600}),
  _StationGroupInfo('屏山段', 'Ping Shan Section', {400, 425}),
  _StationGroupInfo('洪水橋段', 'Hung Shui Kiu Section', {370, 380, 390}),

  // Tuen Mun (Zone 1, 2, & 3)
  _StationGroupInfo('屯門碼頭區', 'Tuen Mun Ferry Pier', {1, 10, 15, 20, 30, 40, 50, 920}),
  _StationGroupInfo('屯門市中心', 'Tuen Mun Central', {60, 70, 75, 80, 90, 212, 220, 230, 240, 250, 260, 265, 270, 275, 280, 295, 300, 310, 320, 330, 340, 350, 360}),
  _StationGroupInfo('屯門北區', 'Tuen Mun North', {100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200}),
];

// A lookup map for efficient retrieval of group info by station ID.
final Map<int, _StationGroupInfo> _stationGroupCache = {
  for (var group in _stationGroups)
    for (var id in group.stationIds) id: group
};

/// Returns the Chinese name of the station group for a given [stationId].
String _getStationGroup(int stationId) {
  return _stationGroupCache[stationId]?.name ?? '其他';
}

/// Returns the English name of the station group for a given [stationId].
String _getStationGroupEn(int stationId) {
  return _stationGroupCache[stationId]?.nameEn ?? 'Others';
}

// ========================= 統一顏色方案 =========================

/// 統一的顏色方案類別 - 確保整個應用程式的顏色一致性
class AppColors {
  // 透明度常數 - 統一的透明度值
  static const double _primaryOpacity = 0.6;
  static const double _secondaryOpacity = 0.6;
  static const double _hintOpacity = 0.5;
  static const double _disabledOpacity = 0.38;
  static const double _subtleOpacity = 0.4;
  static const double _verySubtleOpacity = 0.2;
  
  // 邊框和陰影透明度
  static const double _borderSubtleOpacity = 0.06;
  static const double _borderLightOpacity = 0.08;
  static const double _borderMediumOpacity = 0.1;
  static const double _borderStrongOpacity = 0.12;
  static const double _borderVeryStrongOpacity = 0.2;
  
  // 陰影透明度
  static const double _shadowLightOpacity = 0.08;
  static const double _shadowMediumOpacity = 0.1;
  
  // 容器透明度
  static const double _containerLightOpacity = 0.2;
  static const double _containerMediumOpacity = 0.3;
  
  // 主要文字顏色
  static Color getPrimaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: _primaryOpacity);
  }
  
  // 次要文字顏色
  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: _secondaryOpacity);
  }
  
  // 提示文字顏色
  static Color getHintTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: _hintOpacity);
  }
  
  // 禁用文字顏色
  static Color getDisabledTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: _disabledOpacity);
  }
  
  // 微妙文字顏色
  static Color getSubtleTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: _subtleOpacity);
  }
  
  // 非常微妙的文字顏色
  static Color getVerySubtleTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: _verySubtleOpacity);
  }
  
  // 邊框顏色 - 微妙
  static Color getSubtleBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withValues(alpha: _borderSubtleOpacity);
  }
  
  // 邊框顏色 - 輕微
  static Color getLightBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withValues(alpha: _borderLightOpacity);
  }
  
  // 邊框顏色 - 中等
  static Color getMediumBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withValues(alpha: _borderMediumOpacity);
  }
  
  // 邊框顏色 - 強烈
  static Color getStrongBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withValues(alpha: _borderStrongOpacity);
  }
  
  // 邊框顏色 - 非常強烈
  static Color getVeryStrongBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withValues(alpha: _borderVeryStrongOpacity);
  }
  
  // 陰影顏色 - 輕微
  static Color getLightShadowColor(BuildContext context) {
    return Theme.of(context).colorScheme.shadow.withValues(alpha: _shadowLightOpacity);
  }
  
  // 陰影顏色 - 中等
  static Color getMediumShadowColor(BuildContext context) {
    return Theme.of(context).colorScheme.shadow.withValues(alpha: _shadowMediumOpacity);
  }
  
  // 主要顏色 - 輕微透明度
  static Color getPrimaryLightColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary.withValues(alpha: _containerLightOpacity);
  }
  
  // 主要顏色 - 中等透明度
  static Color getPrimaryMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary.withValues(alpha: _containerMediumOpacity);
  }
  
  // 次要顏色 - 中等透明度
  static Color getSecondaryMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondary.withValues(alpha: _containerMediumOpacity);
  }
  
  // 主要容器顏色 - 中等透明度
  static Color getPrimaryContainerMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.primaryContainer.withValues(alpha: _containerMediumOpacity);
  }
  
  // 次要容器顏色 - 中等透明度
  static Color getSecondaryContainerMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: _containerMediumOpacity);
  }
  
  // 表面顏色
  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }
  
  // 主要顏色
  static Color getPrimaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }
  
  // 次要顏色
  static Color getSecondaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondary;
  }
  
  // 主要容器顏色
  static Color getPrimaryContainerColor(BuildContext context) {
    return Theme.of(context).colorScheme.primaryContainer;
  }
  
  // 次要容器顏色
  static Color getSecondaryContainerColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondaryContainer;
  }
  
  // 主要文字容器顏色
  static Color getOnPrimaryContainerColor(BuildContext context) {
    return Theme.of(context).colorScheme.onPrimaryContainer;
  }
  
  // 次要文字容器顏色
  static Color getOnSecondaryContainerColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSecondaryContainer;
  }
  
  // 主要文字顏色
  static Color getOnPrimaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.onPrimary;
  }
  
  // 次要文字顏色
  static Color getOnSecondaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSecondary;
  }
}

// ========================= 通用組件 =========================

/// 自適應圓圈文字組件 - 自動縮放文字以適應圓圈大小
class AdaptiveCircleText extends StatelessWidget {
  final String text;
  final double circleSize;
  final double baseFontSize;
  final FontWeight fontWeight;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;

  const AdaptiveCircleText({
    super.key,
    required this.text,
    required this.circleSize,
    this.baseFontSize = 16.0,
    this.fontWeight = FontWeight.w600,
    required this.textColor,
    required this.backgroundColor,
    this.borderColor = Colors.transparent,
    this.borderWidth = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(circleSize / 2),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(
              text,
              style: TextStyle(
                fontSize: baseFontSize,
                fontWeight: fontWeight,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ========================= 優化的數據結構和緩存系統 =========================

/// 優化的車站查找表 - O(1) 時間複雜度
class OptimizedStationLookup {
  static final Map<String, int> _englishToId = {};
  static final Map<String, int> _chineseToId = {};
  static final Map<int, StationData> _idToData = {};
  static bool _initialized = false;

  static void initialize(Map<int, Map<String, String>> stations) {
    if (_initialized) return;
    
    for (final entry in stations.entries) {
      final id = entry.key;
      final data = entry.value;
      final en = data['en']!;
      final zh = data['zh']!;
      
      _englishToId[en.toLowerCase()] = id;
      _chineseToId[zh] = id;
      _idToData[id] = StationData(id: id, nameEn: en, nameZh: zh);
    }
    _initialized = true;
  }

  static int? findById(int id) => _idToData.containsKey(id) ? id : null;
  static int? findByEnglish(String name) => _englishToId[name.toLowerCase()];
  static int? findByChinese(String name) => _chineseToId[name];
  static StationData? getData(int id) => _idToData[id];
  
  static List<StationData> getAllStations() => _idToData.values.toList();
  static int get count => _idToData.length;
}

/// 優化的車站數據結構
class StationData {
  final int id;
  final String nameEn;
  final String nameZh;
  
  const StationData({required this.id, required this.nameEn, required this.nameZh});
  
  String displayName(bool isEnglish) => isEnglish ? nameEn : nameZh;
}

/// 優化的緩存系統 - LRU 緩存策略
class OptimizedCache<K, V> {
  final int maxSize;
  final Map<K, _CacheEntry<V>> _cache = {};
  final Queue<K> _accessOrder = Queue<K>();
  
  OptimizedCache({this.maxSize = 100});
  
  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;
    
    // 更新訪問順序
    _accessOrder.remove(key);
    _accessOrder.add(key);
    entry.lastAccessed = DateTime.now();
    
    return entry.value;
  }
  
  void put(K key, V value) {
    if (_cache.length >= maxSize) {
      // 移除最久未使用的項目
      final oldestKey = _accessOrder.removeFirst();
      _cache.remove(oldestKey);
    }
    
    _cache[key] = _CacheEntry(value);
    _accessOrder.add(key);
  }
  
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }
  
  int get size => _cache.length;
}

class _CacheEntry<V> {
  final V value;
  DateTime lastAccessed;
  
  _CacheEntry(this.value) : lastAccessed = DateTime.now();
}

/// 優化的 API 響應緩存
class ApiResponseCache {
  static final OptimizedCache<String, _CachedResponse> _cache = OptimizedCache(maxSize: 50);
  static const Duration _defaultTtl = Duration(seconds: 30);
  
  static void cache(String key, dynamic data, {Duration? ttl}) {
    _cache.put(key, _CachedResponse(
      data: data,
      timestamp: DateTime.now(),
      ttl: ttl ?? _defaultTtl,
    ));
  }
  
  static dynamic get(String key) {
    final cached = _cache.get(key);
    if (cached == null) return null;
    
    if (DateTime.now().difference(cached.timestamp) > cached.ttl) {
      // 過期，移除
      _cache._cache.remove(key);
      _cache._accessOrder.remove(key);
      return null;
    }
    
    return cached.data;
  }
  
  static void clear() => _cache.clear();
}

class _CachedResponse {
  final dynamic data;
  final DateTime timestamp;
  final Duration ttl;
  
  _CachedResponse({required this.data, required this.timestamp, required this.ttl});
}

/// 優化的搜索索引 - 使用 Trie 數據結構
class OptimizedSearchIndex {
  final Map<String, List<int>> _index = {};
  
  void buildIndex(Map<int, Map<String, String>> stations) {
    _index.clear();
    
    for (final entry in stations.entries) {
      final id = entry.key;
      final data = entry.value;
      final en = data['en']!.toLowerCase();
      final zh = data['zh']!;
      
      // 為英文名稱建立前綴索引
      for (int i = 1; i <= en.length; i++) {
        final prefix = en.substring(0, i);
        _index.putIfAbsent(prefix, () => []).add(id);
      }
      
      // 為中文名稱建立前綴索引
      for (int i = 1; i <= zh.length; i++) {
        final prefix = zh.substring(0, i);
        _index.putIfAbsent(prefix, () => []).add(id);
      }
    }
  }
  
  List<int> search(String query) {
    final normalizedQuery = query.toLowerCase();
    final results = _index[normalizedQuery] ?? [];
    
    // 去重並限制結果數量
    return results.toSet().take(20).toList();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始設定螢幕方向為直向，稍後會由 AccessibilityProvider 控制
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  
  // 設定系統UI樣式
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  
  // 測試API響應時間以優化自動刷新間隔
  await LrtApiService.testResponseTime();
  
  runApp(const LrtApp());
}

class LrtApp extends StatelessWidget {
  const LrtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
          ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
          ChangeNotifierProvider(create: (_) => HttpErrorProvider()), 
          ChangeNotifierProvider(create: (_) => LanguageProvider()..initialize()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()..initialize()),
          ChangeNotifierProvider(create: (_) => AccessibilityProvider()..initialize()),
          ChangeNotifierProvider(create: (_) => DeveloperSettingsProvider()..initialize()),
          ChangeNotifierProvider(create: (_) => StationProvider()..initialize()),
          ChangeNotifierProvider(create: (_) => ScheduleProvider()..loadCacheAlertSetting()),
          ChangeNotifierProvider(create: (_) => RoutesCatalogProvider()..loadFromEmbeddedJson()),
      ],
      child: Builder(
        builder: (context) {
                      return Consumer3<LanguageProvider, ThemeProvider, AccessibilityProvider>(
              builder: (context, lang, themeProvider, accessibility, _) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(accessibility.pageScale),
                  ),
                  child: MaterialApp(
                    title: lang.isEnglish ? 'LRT Next Train' : '輕鐵班次',
                theme: ThemeData(
                  useMaterial3: true,
                  splashFactory: InkSparkle.splashFactory,
                  colorSchemeSeed: themeProvider.seedColor,
                  brightness: themeProvider.useSystemTheme 
                      ? MediaQuery.platformBrightnessOf(context) == Brightness.dark ? Brightness.dark : Brightness.light
                      : themeProvider.isDarkMode ? Brightness.dark : Brightness.light,
                  pageTransitionsTheme: const PageTransitionsTheme(builders: {
                    TargetPlatform.android: ZoomPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  }),
                  textTheme: Theme.of(context).textTheme.apply(
                    fontSizeFactor: accessibility.textScale,
                  ),
                ),
                darkTheme: ThemeData(
                  useMaterial3: true,
                  splashFactory: InkSparkle.splashFactory,
                  colorSchemeSeed: themeProvider.seedColor,
                  brightness: Brightness.dark,
                  pageTransitionsTheme: const PageTransitionsTheme(builders: {
                    TargetPlatform.android: ZoomPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  }),
                  textTheme: Theme.of(context).textTheme.apply(
                    fontSizeFactor: accessibility.textScale,
                  ).copyWith(
                    // 針對深色主題優化文字顏色對比度
                    bodyLarge: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.87),
                    ),
                    bodyMedium: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.87),
                    ),
                    bodySmall: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                    titleLarge: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w600,
                    ),
                    titleMedium: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.87),
                      fontWeight: FontWeight.w600,
                    ),
                    titleSmall: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.87),
                    ),
                    headlineMedium: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w600,
                    ),
                    labelLarge: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.87),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                themeMode: themeProvider.useSystemTheme 
                    ? ThemeMode.system 
                    : themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
                home: const HomePage(),
              ),
            );
            },
          );
        },
      ),
    );
  }
}


/* ========================= Motion Constants ========================= */

class MotionConstants {
  // Material motion standard durations
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 400);
  static const Duration slow = Duration(milliseconds: 500);
  
  // Material motion standard curves
  static const Curve standardEasing = Curves.fastOutSlowIn;
  static const Curve emphasizedEasing = Curves.easeInOut;
  static const Curve deceleratedEasing = Curves.easeOut;
  static const Curve acceleratedEasing = Curves.easeIn;
  
  // Animation configuration
  static const Duration pageTransition = medium;
  static const Duration contentTransition = fast;
  static const Duration modalTransition = slow;
}
/* ========================= UI Constants ========================= */

class UIConstants {
  // Card styling
  static const double cardBorderRadius = 12.0;
  static const double cardElevation = 8.0;
  static const EdgeInsets cardMargin = EdgeInsets.symmetric(horizontal: 1, vertical: 6);
  static const EdgeInsets cardPadding = EdgeInsets.all(8);
  
  // Platform card specific
  static const double platformCardBorderRadius = 12.0;
  static const double platformCardElevation = 1.0;
  static const EdgeInsets platformCardMargin = EdgeInsets.symmetric(horizontal: 10, vertical: 5);
  
  // Compact card styling (for settings page)
  static const double compactCardBorderRadius = 12.0;
  static const EdgeInsets compactCardMargin = EdgeInsets.symmetric(vertical: 4);
  static const EdgeInsets compactCardPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
  static const EdgeInsets compactSectionPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 8);
  
  // Spacing constants
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;
  static const double spacingXL = 24.0;
  static const double spacingXXL = 32.0;
  
  // Border radius constants
  static const double borderRadiusXS = 8.0;
  static const double borderRadiusS = 12.0;
  static const double borderRadiusM = 16.0;
  static const double borderRadiusL = 20.0;
  static const double borderRadiusXL = 24.0;
  
  // Icon sizes
  static const double iconSizeXS = 16.0;
  static const double iconSizeS = 20.0;
  static const double iconSizeM = 24.0;
  static const double iconSizeL = 28.0;
  static const double iconSizeXL = 32.0;
  
  // Color circle sizes (for theme selection)
  static const double colorCircleSizeS = 32.0;
  static const double colorCircleSizeM = 40.0;
  
  // ========================= Schedules 頁面統一樣式變數 =========================
  
  // 字體大小常數
  static const double fontSizeXS = 11.0;
  static const double fontSizeS = 12.0;
  static const double fontSizeM = 14.0;
  static const double fontSizeL = 16.0;
  static const double fontSizeXL = 18.0;
  static const double fontSizeXXL = 20.0;
  
  // 圓圈大小常數
  static const double circleSizeS = 48.0;
  static const double circleSizeM = 64.0;
  
  // 統一樣式方法
  static TextStyle scheduleTitleStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeL * accessibility.textScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle scheduleSubtitleStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeM * accessibility.textScale,
      color: AppColors.getPrimaryTextColor(context),
    );
  }
  
  static TextStyle scheduleBodyStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeM * accessibility.textScale,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.70)
          : null,
    );
  }
  
  static TextStyle scheduleCaptionStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    );
  }
  
  static TextStyle scheduleErrorStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Colors.red,
      fontWeight: FontWeight.w500,
    );
  }
  
  static TextStyle scheduleRouteHeaderStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeXXL * accessibility.textScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle scheduleStationNameStyle(BuildContext context, AccessibilityProvider accessibility) {
    return Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
      fontWeight: FontWeight.w600,
      fontSize: fontSizeL * accessibility.textScale,
    ) ?? TextStyle(
      fontSize: fontSizeL * accessibility.textScale,
      fontWeight: FontWeight.w600,
    );
  }
  
  static TextStyle scheduleTrainNameStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: fontSizeL * accessibility.textScale,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle scheduleBadgeStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      color: Theme.of(context).colorScheme.onPrimary,
      fontSize: fontSizeS * accessibility.textScale,
      fontWeight: FontWeight.w500,
    );
  }
  
  static TextStyle scheduleNoDataStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeXL * accessibility.textScale,
      color: AppColors.getPrimaryTextColor(context),
    );
  }
  
  // 統一間距常數
  static const EdgeInsets scheduleCardMargin = EdgeInsets.symmetric(horizontal: 20, vertical: 6);
  
  // 統一邊框常數
  static const double borderWidth = 1.5;
  static const double borderWidthThin = 2.0;
  static const double borderWidthThick = 4.5;
  static const EdgeInsets scheduleCardPadding = EdgeInsets.all(10);
  static const EdgeInsets scheduleBadgePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  static const EdgeInsets scheduleListTilePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 6);
  static const EdgeInsets scheduleSubtitlePadding = EdgeInsets.only(top: 4);
  
  // 統一圓角常數
  static const double scheduleCardBorderRadius = 20.0;
  static const double scheduleBadgeBorderRadius = 12.0;
  static const double scheduleIconBorderRadius = 10.0;
  
  // 統一陰影
  static List<BoxShadow> scheduleCardShadow(BuildContext context) {
    return [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.4),
        blurRadius: 4,
        offset: const Offset(0, 1),
        spreadRadius: 1.5,
      ),
    ];
  }
  
  // 統一邊框
  static Border scheduleCardBorder(BuildContext context) {
    return Border.all(
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 1),
      width: UIConstants.borderWidth,
    );
  }
  
  static Border scheduleListTileBorder(BuildContext context) {
    return Border(
      bottom: BorderSide(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
        width: UIConstants.borderWidth,
      ),
    );
  }
  
  // 統一背景色
  static Color scheduleHeaderBackground(BuildContext context) {
    return Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 1);
  }
  
  static Color scheduleErrorBackground(BuildContext context) {
    return Colors.red.withValues(alpha: 0.1);
  }
  
  static Color scheduleErrorBorder(BuildContext context) {
    return Colors.red.withValues(alpha: 0.3);
  }
  
  // 統一圖標大小
  static double scheduleIconSize(BuildContext context, AccessibilityProvider accessibility, {double multiplier = 1.0}) {
    return iconSizeS * accessibility.iconScale * multiplier;
  }
  
  static double scheduleLargeIconSize(BuildContext context, AccessibilityProvider accessibility) {
    return circleSizeM * accessibility.iconScale;
  }
  
  // 統一圓圈文字組件配置
  static AdaptiveCircleText scheduleCircleText({
    required String text,
    required AccessibilityProvider accessibility,
    required bool isStopped,
    required BuildContext context,
  }) {
    return AdaptiveCircleText(
      text: text,
      circleSize: circleSizeS,
      baseFontSize: fontSizeL * accessibility.textScale,
      textColor: isStopped 
          ? Colors.red
          : Theme.of(context).colorScheme.onSecondaryContainer,
      backgroundColor: isStopped 
          ? scheduleErrorBackground(context)
          : Theme.of(context).colorScheme.secondaryContainer,
      borderColor: isStopped 
          ? scheduleErrorBorder(context)
          : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
    );
  }

  // ========================= Routes 頁面統一樣式變數 =========================
  
  // Routes 頁面間距常數
  static const EdgeInsets routesSelectorMargin = EdgeInsets.symmetric(horizontal: 1, vertical: 1);
  static const EdgeInsets routesSelectorPadding = EdgeInsets.all(1);
  static const EdgeInsets routesChipPadding = EdgeInsets.symmetric(horizontal: 1, vertical: 1);
  static const EdgeInsets routesCompactChipPadding = EdgeInsets.symmetric(horizontal: 1, vertical: 1);
  static const EdgeInsets routesWarningPadding = EdgeInsets.all(1);
  static const EdgeInsets routesWarningChipPadding = EdgeInsets.symmetric(horizontal: 1, vertical: 6);
  
  // Routes 頁面圓角常數
  static const double routesSelectorBorderRadius = 20.0;
  static const double routesWarningBorderRadius = 12.0;
  static const double routesWarningChipBorderRadius = 12.0;
  
  // Routes 頁面陰影
  static List<BoxShadow> routesSelectorShadow(BuildContext context) {
    return [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
        blurRadius: 4,
        offset: const Offset(0, 1),
        spreadRadius: 5,
      ),
    ];
  }
  
  // Routes 頁面邊框
  static Border routesSelectorBorder(BuildContext context) {
    return Border.all(
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
      width: UIConstants.borderWidth,
    );
  }
  
  static Border routesWarningBorder(BuildContext context) {
    return Border.all(
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
      width: UIConstants.borderWidth,
    );
  }
  
  static Border routesWarningChipBorder(BuildContext context) {
    return Border.all(
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
      width: UIConstants.borderWidth,
    );
  }
  
  // Routes 頁面背景色
  static Color routesWarningBackground(BuildContext context) {
    return Colors.orange.withValues(alpha: 0.1);
  }
  
  // Routes 頁面樣式方法
  static TextStyle routesLabelStyle(BuildContext context) {
    return TextStyle(
      fontSize: fontSizeM * context.watch<AccessibilityProvider>().textScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle routesDistrictChipStyle(BuildContext context, AccessibilityProvider accessibility, bool isSelected) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle routesRouteChipStyle(BuildContext context, AccessibilityProvider accessibility, bool isSelected) {
    return TextStyle(
      fontSize: fontSizeXS * accessibility.textScale,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle routesDescriptionStyle(BuildContext context) {
    return TextStyle(
      fontSize: fontSizeM * context.watch<AccessibilityProvider>().textScale,
      color: AppColors.getPrimaryTextColor(context),
    );
  }
  
  static TextStyle routesWarningTitleStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeL * accessibility.textScale,
      fontWeight: FontWeight.w600,
      color: Colors.orange,
    );
  }
  
  static TextStyle routesWarningChipStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Colors.orange,
    );
  }
  
  // Routes 頁面圖標大小
  static double routesWarningIconSize(BuildContext context, AccessibilityProvider accessibility) {
    return iconSizeS * accessibility.iconScale;
  }

  // ========================= Settings 頁面統一樣式變數 =========================
  
  // Settings 頁面間距常數
  static const EdgeInsets settingsPagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 6);
  static const EdgeInsets settingsSliderPadding = EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets settingsChoiceChipPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  
  // Settings 頁面圓角常數
  static const double settingsChoiceChipBorderRadius = 12.0;
  
  // Settings 頁面樣式方法
  static TextStyle settingsCardTitleStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeM * accessibility.textScale,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle settingsCardSubtitleStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
    );
  }
  
  static TextStyle settingsSectionTitleStyle(BuildContext context) {
    return TextStyle(
      fontSize: fontSizeL * context.watch<AccessibilityProvider>().textScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.87)
          : null,
    );
  }
  
  static TextStyle settingsSliderLabelStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.70)
          : null,
    );
  }
  
  static TextStyle settingsChoiceChipLabelStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withValues(alpha: 0.70)
          : null,
    );
  }
  
  // Settings 頁面圖標大小
  static double settingsIconSize(BuildContext context, AccessibilityProvider accessibility) {
    return iconSizeS * accessibility.iconScale;
  }
  
  static double settingsLargeIconSize(BuildContext context, AccessibilityProvider accessibility) {
    return iconSizeL * accessibility.iconScale;
  }
  
  static List<BoxShadow> cardShadow(BuildContext context) {
    return [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 1),
        spreadRadius: 0,
      ),
    ];
  }
  
  static List<BoxShadow> compactCardShadow(BuildContext context) {
    return [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 1),
        spreadRadius: 0,
      ),
    ];
  }
  
  static List<BoxShadow> elevatedCardShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: isDark 
            ? Colors.black.withValues(alpha: 0.4)
            : Colors.grey.withValues(alpha: 0.2),
        blurRadius: 12,
        offset: const Offset(0, 4),
        spreadRadius: 0,
      ),
      BoxShadow(
        color: isDark 
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.1),
        blurRadius: 6,
        offset: const Offset(0, 2),
        spreadRadius: 0,
      ),
    ];
  }
  
  static List<BoxShadow> colorCircleShadow(BuildContext context, Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.3),
        blurRadius: 4,
        spreadRadius: 1,
      ),
    ];
  }

  static double getAdaptiveIconSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth / 428; // Assuming 428 is the width of the iPhone 12 Pro Max
    return baseSize * scaleFactor;
  }
}

/* ========================= Connectivity Provider ========================= */

class ConnectivityProvider extends ChangeNotifier {
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  ConnectivityProvider() {
    _init();
    _sub = Connectivity().onConnectivityChanged.listen(_update);
  }

  Future<void> _init() async {
    try {
      final res = await Connectivity().checkConnectivity();
      _update(res);
    } catch (_) {
      _isOnline = false;
      notifyListeners();
    }
  }

  void _update(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);
    if (wasOnline != _isOnline) notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/* ========================= HTTP Error Provider ========================= */

class HttpErrorProvider extends ChangeNotifier {
  bool _hasApiError = false;
  String? _lastErrorMessage;
  DateTime? _lastErrorTime;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;

  bool get hasApiError => _hasApiError;
  bool get isApiHealthy => !_hasApiError;
  String? get lastErrorMessage => _lastErrorMessage;
  DateTime? get lastErrorTime => _lastErrorTime;
  int get consecutiveErrors => _consecutiveErrors;
  
  // Check if we should stop making requests due to persistent errors
  bool get shouldStopRequests => _consecutiveErrors >= _maxConsecutiveErrors;
  
  void reportApiError(String errorMessage) {
    _hasApiError = true;
    _lastErrorMessage = errorMessage;
    _lastErrorTime = DateTime.now();
    _consecutiveErrors++;
    
    debugPrint('HttpErrorProvider: API error reported - $_lastErrorMessage');
    debugPrint('HttpErrorProvider: Consecutive errors: $_consecutiveErrors');
    
    notifyListeners();
  }
  
  void clearApiError() {
    if (_hasApiError || _consecutiveErrors > 0) {
      _hasApiError = false;
      _lastErrorMessage = null;
      _lastErrorTime = null;
      _consecutiveErrors = 0;
      
      debugPrint('HttpErrorProvider: API errors cleared');
      notifyListeners();
    }
  }
  
  void reportApiSuccess() {
    if (_hasApiError || _consecutiveErrors > 0) {
      clearApiError();
      debugPrint('HttpErrorProvider: API success reported, errors cleared');
    }
  }
  
  // Check if enough time has passed to retry after consecutive errors
  bool canRetryAfterError() {
    if (!shouldStopRequests) return true;
    if (_lastErrorTime == null) return true;
    
    final timeSinceLastError = DateTime.now().difference(_lastErrorTime!);
    final waitTime = Duration(minutes: _consecutiveErrors.clamp(1, 10)); // Progressive backoff
    
    return timeSinceLastError > waitTime;
  }
  
  String getErrorStatusMessage(bool isEnglish) {
    if (!_hasApiError) return '';
    
    if (shouldStopRequests) {
      return isEnglish 
        ? 'Multiple API errors - requests paused'
        : '多次API錯誤 - 請求已暫停';
    }
    
    return isEnglish
      ? 'API Error: ${_lastErrorMessage ?? 'Unknown error'}'
      : 'API錯誤：${_lastErrorMessage ?? '未知錯誤'}';
  }
}


/* ========================= Theme Provider ========================= */

class ThemeProvider extends ChangeNotifier {
  static const String _themeColorKey = 'app_theme_color';
  static const String _isDarkModeKey = 'app_is_dark_mode';
  static const String _useSystemThemeKey = 'app_use_system_theme';
  
  Color _seedColor = Colors.green;
  bool _isDarkMode = false;
  bool _useSystemTheme = true;
  SharedPreferences? _prefs;

  Color get seedColor => _seedColor;
  bool get isDarkMode => _isDarkMode;
  bool get useSystemTheme => _useSystemTheme;

  // 預設的主題顏色選項
  static const List<Color> colorOptions = [
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.orange,
    Colors.red,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Colors.amber,
    Colors.cyan,
    Colors.deepOrange,
    Colors.deepPurple,
  ];

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // 載入保存的顏色（保存為顏色值）
    final savedColorValue = _prefs!.getInt(_themeColorKey);
    if (savedColorValue != null) {
      _seedColor = Color(savedColorValue);
    }
    
    _isDarkMode = _prefs!.getBool(_isDarkModeKey) ?? false;
    _useSystemTheme = _prefs!.getBool(_useSystemThemeKey) ?? true;
    
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    await _save();
  }

  Future<void> setDarkMode(bool darkMode) async {
    _isDarkMode = darkMode;
    await _save();
  }

  Future<void> setUseSystemTheme(bool useSystem) async {
    _useSystemTheme = useSystem;
    await _save();
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_themeColorKey, _seedColor.toARGB32());
    await _prefs!.setBool(_isDarkModeKey, _isDarkMode);
    await _prefs!.setBool(_useSystemThemeKey, _useSystemTheme);
    notifyListeners();
  }

  String getColorName(Color color, bool isEnglish) {
    if (color == Colors.green) return isEnglish ? 'Green' : '綠色';
    if (color == Colors.blue) return isEnglish ? 'Blue' : '藍色';
    if (color == Colors.purple) return isEnglish ? 'Purple' : '紫色';
    if (color == Colors.orange) return isEnglish ? 'Orange' : '橙色';
    if (color == Colors.red) return isEnglish ? 'Red' : '紅色';
    if (color == Colors.teal) return isEnglish ? 'Teal' : '湖綠色';
    if (color == Colors.indigo) return isEnglish ? 'Indigo' : '靛色';
    if (color == Colors.pink) return isEnglish ? 'Pink' : '粉紅色';
    if (color == Colors.amber) return isEnglish ? 'Amber' : '琥珀色';
    if (color == Colors.cyan) return isEnglish ? 'Cyan' : '青色';
    if (color == Colors.deepOrange) return isEnglish ? 'Deep Orange' : '深橙色';
    if (color == Colors.deepPurple) return isEnglish ? 'Deep Purple' : '深紫色';
    return isEnglish ? 'Custom' : '自定義';
  }
}

  /* ========================= Developer Settings Provider ========================= */
  
  class DeveloperSettingsProvider extends ChangeNotifier {
    static const String _hideStationIdKey = 'hide_station_id';
    static const String _showGridDebugKey = 'show_grid_debug';
    
    bool _hideStationId = false;
    bool _showGridDebug = false;
    SharedPreferences? _prefs;

    bool get hideStationId => _hideStationId;
    bool get showGridDebug => _showGridDebug;

    Future<void> initialize() async {
      _prefs = await SharedPreferences.getInstance();
      _hideStationId = _prefs!.getBool(_hideStationIdKey) ?? false;
      _showGridDebug = _prefs!.getBool(_showGridDebugKey) ?? false;
      notifyListeners();
    }

    Future<void> setHideStationId(bool hide) async {
      _hideStationId = hide;
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_hideStationIdKey, hide);
      notifyListeners();
    }
    
    Future<void> setShowGridDebug(bool show) async {
      _showGridDebug = show;
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_showGridDebugKey, show);
      notifyListeners();
    }
  }

  /* ========================= Accessibility Provider ========================= */
  
  class AccessibilityProvider extends ChangeNotifier {
  static const String _textScaleKey = 'app_text_scale';
  static const String _iconScaleKey = 'app_icon_scale';
  static const String _screenRotationKey = 'app_screen_rotation_enabled';
  static const String _pageScaleKey = 'app_page_scale';
  
  double _textScale = 1.0;
  double _iconScale = 1.0;
  bool _screenRotationEnabled = true;
  double _pageScale = 1.0;
  SharedPreferences? _prefs;

  double get textScale => _textScale;
  double get iconScale => _iconScale;
  bool get screenRotationEnabled => _screenRotationEnabled;
  double get pageScale => _pageScale;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _textScale = _prefs!.getDouble(_textScaleKey) ?? 1.0;
    _iconScale = _prefs!.getDouble(_iconScaleKey) ?? 1.0;
    _screenRotationEnabled = _prefs!.getBool(_screenRotationKey) ?? true;
    _pageScale = _prefs!.getDouble(_pageScaleKey) ?? 1.0;
    notifyListeners();
    _applyScreenRotationSetting();
  }

  Future<void> setTextScale(double scale) async {
    _textScale = scale.clamp(0.8, 2.0); // 限制範圍在 0.8 到 2.0 之間
    await _save();
  }

  Future<void> setIconScale(double scale) async {
    _iconScale = scale.clamp(0.8, 2.0); // 限制範圍在 0.8 到 2.0 之間
    await _save();
  }

  Future<void> setScreenRotationEnabled(bool enabled) async {
    _screenRotationEnabled = enabled;
    await _save();
    _applyScreenRotationSetting();
  }

  Future<void> setPageScale(double scale) async {
    _pageScale = scale.clamp(0.8, 2.0); // 限制範圍在 0.8 到 2.0 之間
    await _save();
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_textScaleKey, _textScale);
    await _prefs!.setDouble(_iconScaleKey, _iconScale);
    await _prefs!.setBool(_screenRotationKey, _screenRotationEnabled);
    await _prefs!.setDouble(_pageScaleKey, _pageScale);
    notifyListeners();
  }

  void _applyScreenRotationSetting() {
    if (kIsWeb) return; // Web 平台不支援螢幕方向控制
    
    if (_screenRotationEnabled) {
      // 允許所有方向
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // 只允許直向
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  // 預設文字、圖示和頁面縮放選項
  static const List<double> textScaleOptions = [0.8, 0.9, 1.0, 1.2, 1.5, 2.0];
  static const List<double> iconScaleOptions = [0.8, 0.9, 1.0, 1.2, 1.5, 2.0];
  static const List<double> pageScaleOptions = [0.8, 0.9, 1.0, 1.2, 1.5, 2.0];
  
  String getTextSizeLabel(double scale, bool isEnglish) {
    if (scale == 0.8) return isEnglish ? 'Very Small' : '非常小';
    if (scale == 0.9) return isEnglish ? 'Small' : '小';
    if (scale == 1.0) return isEnglish ? 'Normal' : '正常';
    if (scale == 1.2) return isEnglish ? 'Large' : '大';
    if (scale == 1.5) return isEnglish ? 'Very Large' : '非常大';
    if (scale == 2.0) return isEnglish ? 'Extra Large' : '超大';
    return isEnglish ? 'Custom' : '自定義';
  }
  
  String getIconSizeLabel(double scale, bool isEnglish) {
    if (scale == 0.8) return isEnglish ? 'Very Small' : '非常小';
    if (scale == 0.9) return isEnglish ? 'Small' : '小';
    if (scale == 1.0) return isEnglish ? 'Normal' : '正常';
    if (scale == 1.2) return isEnglish ? 'Large' : '大';
    if (scale == 1.5) return isEnglish ? 'Very Large' : '非常大';
    if (scale == 2.0) return isEnglish ? 'Extra Large' : '超大';
    return isEnglish ? 'Custom' : '自定義';
  }
  
  String getPageScaleLabel(double scale, bool isEnglish) {
    if (scale == 0.8) return isEnglish ? 'Very Small' : '非常小';
    if (scale == 0.9) return isEnglish ? 'Small' : '小';
    if (scale == 1.0) return isEnglish ? 'Normal' : '正常';
    if (scale == 1.2) return isEnglish ? 'Large' : '大';
    if (scale == 1.5) return isEnglish ? 'Very Large' : '非常大';
    if (scale == 2.0) return isEnglish ? 'Extra Large' : '超大';
    return isEnglish ? 'Custom' : '自定義';
  }
}
/* ========================= Language Provider ========================= */

class LanguageProvider extends ChangeNotifier {
  static const String _langKey = 'app_language_is_english';
  bool _isEnglish = true;
  SharedPreferences? _prefs;

  bool get isEnglish => _isEnglish;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isEnglish = _prefs!.getBool(_langKey) ?? true;
    notifyListeners();
  }

  Future<void> setEnglish() async {
    _isEnglish = true;
    await _save();
  }

  Future<void> setChinese() async {
    _isEnglish = false;
    await _save();
  }

  Future<void> toggle() async {
    _isEnglish = !_isEnglish;
    await _save();
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_langKey, _isEnglish);
    notifyListeners();
  }

  // Labels
  String get appTitle => _isEnglish ? 'LRT Next Train' : '輕鐵班次';
  String get schedule => _isEnglish ? 'Schedule' : '班次表';
  String get routes => _isEnglish ? 'Routes' : '路綫';
  String get settings => _isEnglish ? 'Settings' : '設定';
  String get selectStation => _isEnglish ? 'Select Station' : '選擇車站';
  String get selectDistrict => _isEnglish ? 'Select District' : '選擇地區';
  String get selectRoute => _isEnglish ? 'Select Route' : '選擇路綫';
  String get platform => _isEnglish ? 'Platform' : '月台';
  String get route => _isEnglish ? 'Route' : '路綫';
  String get destination => _isEnglish ? 'Destination' : '目的地';
  String get arrivalTime => _isEnglish ? 'Arrival Time' : '到達時間';
  String get departureTime => _isEnglish ? 'Departure Time' : '開出時間';
  String get trainLength => _isEnglish ? 'Train Length' : '列車長度';
  String get status => _isEnglish ? 'Status' : '狀態';
  String get normal => _isEnglish ? 'Normal' : '正常';
  String get alert => _isEnglish ? 'Alert' : '警示';
  String get system => _isEnglish ? 'System' : '系統';
  String get lastUpdated => _isEnglish ? 'Last updated' : '最後更新';
  String get refresh => _isEnglish ? 'Refresh' : '重新整理';
  String get retry => _isEnglish ? 'Retry' : '重試';
  String get noData => _isEnglish ? 'Please select a route' : '請選擇路綫';
  String get noTrains => _isEnglish ? 'No upcoming trains' : '沒有即將到達的列車';
  String get cars => _isEnglish ? 'cars' : '卡';
  String get arrives => _isEnglish ? 'Arrives' : '到達';
  String get departs => _isEnglish ? 'Departs' : '開出';
  String get serviceStopped => _isEnglish ? 'Service Stopped' : '服務暫停';
  String get normalService => _isEnglish ? 'Normal Service' : '正常服務';
  String get language => _isEnglish ? 'Language' : '語言';
  String get english => 'English';
  String get chinese => '繁體中文';
  String get stationsServed => _isEnglish ? 'Stations Served' : '服務車站';
  String get unmatchedStations => _isEnglish ? 'Unmatched stations' : '未對應車站';
  String get offline => _isEnglish ? 'You are offline' : '您已離綫';
  String get networkError => _isEnglish ? 'Network Error' : '網絡錯誤';
  String get tryAgain => _isEnglish ? 'Try Again' : '重試';
  String get usingCachedData => _isEnglish ? 'Using cached data' : '使用緩存數據';
  String get showCacheAlert => _isEnglish ? 'Show Cache Alert' : '顯示快取警告';
  String get cacheAlertDescription => _isEnglish ? 'Show alert when using cached data' : '使用快取數據時顯示警告';
  String get accessibility => _isEnglish ? 'Accessibility' : '輔助功能';
  String get textSize => _isEnglish ? 'Text Size' : '文字大小';
  String get iconSize => _isEnglish ? 'Icon Size' : '圖示大小';
  String get pageScale => _isEnglish ? 'Page Scale' : '頁面縮放';
  String get screenRotation => _isEnglish ? 'Screen Rotation' : '螢幕旋轉';
  String get enableScreenRotation => _isEnglish ? 'Enable screen rotation' : '啟用螢幕旋轉';
  String get disableScreenRotation => _isEnglish ? 'Disable screen rotation' : '停用螢幕旋轉';
  String get theme => _isEnglish ? 'Theme' : '主題';
  String get themeColor => _isEnglish ? 'Theme Color' : '主題顏色';
  String get darkMode => _isEnglish ? 'Dark Mode' : '深色模式';
  String get lightMode => _isEnglish ? 'Light Mode' : '淺色模式';
  String get systemTheme => _isEnglish ? 'System Theme' : '系統主題';
  String get useSystemTheme => _isEnglish ? 'Use system theme' : '使用系統主題';
  String get manualTheme => _isEnglish ? 'Manual theme selection' : '手動選擇主題';
  String get searchStations => _isEnglish ? 'Search stations...' : '搜尋車站...';
  String get recent => _isEnglish ? 'Recent' : '最近使用';
  String get noStationsFound => _isEnglish ? 'No stations found' : '找不到車站';
  String get selectDistrictDescription => _isEnglish ? 'Choose a district to view available routes' : '選擇一個地區來查看可用的路綫';
  String get selectRouteDescription => _isEnglish ? 'Choose a route to view schedule information' : '選擇一條路綫來查看班次信息';
  String get noScheduleDataDescription => _isEnglish ? 'Choose a route from the list above to view schedules' : '從上方列表中選擇路綫以查看班次';
  String get noTrainsDescription => _isEnglish ? 'No trains available for this route' : '該路綫目前沒有班次信息';
  String get totalTrains => _isEnglish ? 'trains' : '列車';
}

/* ========================= API Models ========================= */

class LrtScheduleResponse {
  final int status;
  final DateTime? systemTime;
  final List<PlatformSchedule> platforms;
  LrtScheduleResponse({required this.status, required this.systemTime, required this.platforms});

  factory LrtScheduleResponse.fromJson(Map<String, dynamic> json) {
    final statusVal = json['status'];
    final platformList = json['platform_list'];
    return LrtScheduleResponse(
      status: statusVal is int ? statusVal : int.tryParse('${statusVal ?? "0"}') ?? 0,
      systemTime: json['system_time'] is String ? _parseTime(json['system_time']) : null,
      platforms: (platformList is List ? platformList : const <dynamic>[])
          .map((e) => PlatformSchedule.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'system_time': systemTime != null ? '${systemTime!.year.toString().padLeft(4, '0')}-${systemTime!.month.toString().padLeft(2, '0')}-${systemTime!.day.toString().padLeft(2, '0')} ${systemTime!.hour.toString().padLeft(2, '0')}:${systemTime!.minute.toString().padLeft(2, '0')}:${systemTime!.second.toString().padLeft(2, '0')}' : null,
      'platform_list': platforms.map((p) => p.toJson()).toList(),
    };
  }

  static DateTime? _parseTime(String s) {
    try {
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(s.trim());
      if (match == null) return null;
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final second = int.parse(match.group(6)!);
      // Store the time as-is, treating it as local time in HKT
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}

class PlatformSchedule {
  final int platformId;
  final List<TrainInfo> trains;
  PlatformSchedule({required this.platformId, required this.trains});

  factory PlatformSchedule.fromJson(Map<String, dynamic> json) {
    final raw = json['route_list'] ?? json['train_list'] ?? json['routes'];
    final list = raw is List ? raw : const <dynamic>[];
    return PlatformSchedule(
      platformId: json['platform_id'] is int
          ? json['platform_id']
          : int.tryParse('${json['platform_id'] ?? "-1"}') ?? -1,
      trains: list.map((e) => TrainInfo.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'platform_id': platformId,
      'route_list': trains.map((t) => t.toJson()).toList(),
    };
  }
}

class TrainInfo {
  final int? trainLength;
  final String arrivalDeparture;
  final String destEn;
  final String destCh;
  final String timeEn;
  final String timeCh;
  final String routeNo;
  final int? stop;

  const TrainInfo({
    required this.trainLength,
    required this.arrivalDeparture,
    required this.destEn,
    required this.destCh,
    required this.timeEn,
    required this.timeCh,
    required this.routeNo,
    required this.stop,
  });

  factory TrainInfo.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ""}');
    String asStr(dynamic v) => (v ?? '').toString();
    return TrainInfo(
      trainLength: asInt(json['train_length']),
      arrivalDeparture: asStr(json['arrival_departure']),
      destEn: asStr(json['dest_en']),
      destCh: asStr(json['dest_ch']),
      timeEn: asStr(json['time_en']),
      timeCh: asStr(json['time_ch']),
      routeNo: asStr(json['route_no']),
      stop: asInt(json['stop']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'train_length': trainLength,
      'arrival_departure': arrivalDeparture,
      'dest_en': destEn,
      'dest_ch': destCh,
      'time_en': timeEn,
      'time_ch': timeCh,
      'route_no': routeNo,
      'stop': stop,
    };
  }

  bool get isArrivingSoon => timeEn.toLowerCase() == 'arriving' || timeCh == '即將抵達';
  bool get isDepartingSoon => timeEn.toLowerCase() == 'departing' || timeCh == '正在離開';
  bool get isStopped => stop == 1;

  String get identity =>
      '$routeNo|$destEn|$timeEn|$arrivalDeparture|${trainLength ?? 0}|${stop ?? 0}';

  String name(bool isEnglish) => isEnglish ? destEn : destCh;
  String time(bool isEnglish) => isEnglish ? timeEn : timeCh;
}

/* ========================= Routes Catalog Models ========================= */

class LrtRoutesCatalog {
  final List<LrtDistrict> districts;
  LrtRoutesCatalog({required this.districts});
}

class LrtDistrict {
  final String nameEn;
  final String nameZh;
  final List<LrtRoute> routes;
  LrtDistrict({required this.nameEn, required this.nameZh, required this.routes});
  
  String displayName(bool isEnglish) => isEnglish ? nameEn : nameZh;
}

class LrtRoute {
  final String routeNumber;
  final String descriptionEn;
  final String descriptionZh;
  final List<LrtRouteStationName> stations;
  LrtRoute({required this.routeNumber, required this.descriptionEn, required this.descriptionZh, required this.stations});
  
  String displayDescription(bool isEnglish) => isEnglish ? descriptionEn : descriptionZh;
}

class LrtRouteStationName {
  final String en;
  final String zh;
  LrtRouteStationName({required this.en, required this.zh});
}

/* ========================= Routes Catalog Provider (persistent selection) ========================= */

class RoutesCatalogProvider extends ChangeNotifier {
  static const String _districtKey = 'selected_district_index';
  static const String _routeKey = 'selected_route_index';
  static const String _hasUserSelectedKey = 'has_user_selected';

  LrtRoutesCatalog? _catalog;
  int _districtIndex = 0;
  int _routeIndex = 0;
  bool _hasUserSelected = false;
  SharedPreferences? _prefs;

  LrtRoutesCatalog? get catalog => _catalog;
  int get districtIndex => _districtIndex;
  int get routeIndex => _routeIndex;
  LrtDistrict? get selectedDistrict =>
      (_catalog?.districts.isNotEmpty ?? false) ? _catalog!.districts[_districtIndex] : null;
  LrtRoute? get selectedRoute =>
      (selectedDistrict != null && selectedDistrict!.routes.isNotEmpty)
          ? selectedDistrict!.routes[_routeIndex]
          : null;
          
  // 檢查用戶是否已經進行過選擇
  bool get hasUserSelection {
    final result = _hasUserSelected && selectedDistrict != null && selectedRoute != null;
    debugPrint('RoutesCatalogProvider.hasUserSelection: hasUserSelected=$_hasUserSelected, selectedDistrict != null=${selectedDistrict != null}, selectedRoute != null=${selectedRoute != null} -> $result');
    return result;
  }


  Future<void> loadFromEmbeddedJson() async {
    try {
      _catalog = _parseRoutesCatalog(kRoutesJson);
      await _restore();
    } catch (_) {
      _catalog = LrtRoutesCatalog(districts: []);
    }
    notifyListeners();
  }

  Future<void> _restore() async {
    _prefs ??= await SharedPreferences.getInstance();
    final d = _prefs!.getInt(_districtKey) ?? 0;
    if (_catalog != null && d < _catalog!.districts.length) _districtIndex = d;
    
    // 確保地區索引有效後再設置路綫索引
    if (_catalog != null && _districtIndex < _catalog!.districts.length) {
      final district = _catalog!.districts[_districtIndex];
      final r = _prefs!.getInt(_routeKey) ?? 0;
      if (r < district.routes.length) _routeIndex = r;
    }
    
    _hasUserSelected = _prefs!.getBool(_hasUserSelectedKey) ?? false;
    
    debugPrint('RoutesCatalogProvider._restore: districtIndex=$_districtIndex, routeIndex=$_routeIndex, hasUserSelected=$_hasUserSelected');
  }

  Future<void> setDistrictIndex(int index) async {
    if (_catalog == null) return;
    if (index < 0 || index >= _catalog!.districts.length) return;
    _districtIndex = index;
    _routeIndex = 0;
    _hasUserSelected = true;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_districtKey, index);
    await _prefs!.setInt(_routeKey, 0);
    await _prefs!.setBool(_hasUserSelectedKey, true);
    debugPrint('RoutesCatalogProvider.setDistrictIndex: saved districtIndex=$index, routeIndex=0, hasUserSelected=true');
    notifyListeners();
  }

  Future<void> setRouteIndex(int index) async {
    if (selectedDistrict == null) return;
    if (index < 0 || index >= selectedDistrict!.routes.length) return;
    _routeIndex = index;
    _hasUserSelected = true;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_routeKey, index);
    await _prefs!.setBool(_hasUserSelectedKey, true);
    debugPrint('RoutesCatalogProvider.setRouteIndex: saved routeIndex=$index, hasUserSelected=true');
    notifyListeners();
  }

  static LrtRoutesCatalog _parseRoutesCatalog(String jsonStr) {
    final root = json.decode(jsonStr) as Map<String, dynamic>;
    final sys = root['light_rail_system'] as Map<String, dynamic>;
    final ds = (sys['districts'] as List<dynamic>).map((d) {
      final md = d as Map<String, dynamic>;
      final nameEn = md['name'] as String? ?? '';
      final nameZh = _getDistrictNameZh(nameEn);
      final routes = (md['routes'] as List<dynamic>? ?? []).map((r) {
        final mr = r as Map<String, dynamic>;
        final routeNo = mr['route_number'] as String? ?? '';
        final descEn = mr['description'] as String? ?? '';
        final descZh = _getRouteDescriptionZh(descEn);
        final stations = (mr['stations'] as List<dynamic>? ?? []).map((s) {
          final ms = s as Map<String, dynamic>;
          return LrtRouteStationName(
            en: (ms['name_en'] as String? ?? '').trim(),
            zh: (ms['name_zh'] as String? ?? '').trim(),
          );
        }).toList();
        return LrtRoute(routeNumber: routeNo, descriptionEn: descEn, descriptionZh: descZh, stations: stations);
      }).toList();
      return LrtDistrict(nameEn: nameEn, nameZh: nameZh, routes: routes);
    }).toList();
    return LrtRoutesCatalog(districts: ds);
  }

  static String _getDistrictNameZh(String nameEn) {
    switch (nameEn) {
      case 'Tuen Mun': return '屯門';
      case 'Tin Shui Wai': return '天水圍';
      case 'Inter-District': return '跨區';
      default: return nameEn;
    }
  }

  static String _getRouteDescriptionZh(String descriptionEn) {
    switch (descriptionEn) {
      case 'Sam Shing↔Siu Hong': return '三聖↔兆康';
      case 'Tuen Mun Ferry Pier↔Tin King': return '屯門碼頭↔田景';
      case 'Tuen Mun Ferry Pier↔Siu Hong': return '屯門碼頭↔兆康';
      case 'Tin Shui Wai Loop (Anti-clockwise)': return '天水圍循環綫 (逆時針)';
      case 'Tin Shui Wai Loop (Clockwise)': return '天水圍循環綫 (順時針)';
      case 'Tin Yat↔Tin Shui Wai': return '天逸↔天水圍';
      case 'Tuen Mun Ferry Pier↔Yuen Long': return '屯門碼頭↔元朗';
      case 'Tin Yat↔Yuen Long': return '天逸↔元朗';
      case 'Tin Yat↔Yau Oi': return '天逸↔友愛';
      default: return descriptionEn;
    }
  }
}

/* ========================= 優化的 API Service ========================= */

class LrtApiService {
  static const String base = 'https://rt.data.gov.hk/v1/transport/mtr/lrt/getSchedule?station_id=';
  static const Duration ttl = Duration(seconds: 5);
  static final http.Client _client = http.Client();
  static final Map<String, Timer> _debounceTimers = {};
  
  // 響應時間追蹤
  static final List<Duration> _responseTimes = [];
  static const int _maxResponseTimeHistory = 10;
  static Duration _lastResponseTime = Duration.zero;

  static String _key(int stationId) => 'lrt_schedule_$stationId';

  // 獲取平均響應時間
  static Duration get averageResponseTime {
    if (_responseTimes.isEmpty) return const Duration(milliseconds: 59); // 基於實際測試結果
    final total = _responseTimes.fold<Duration>(
      Duration.zero, 
      (sum, time) => sum + time
    );
    return Duration(milliseconds: total.inMilliseconds ~/ _responseTimes.length);
  }

  // 獲取建議的刷新間隔
  static Duration get suggestedRefreshInterval {
    final avgTime = averageResponseTime;
    
    // 基於響應時間計算合適的間隔
    Duration interval;
    if (avgTime.inMilliseconds < 100) {
      // 響應很快（<100ms），使用較短的間隔
      interval = const Duration(seconds: 5);
    } else if (avgTime.inMilliseconds < 500) {
      // 響應中等（100-500ms），使用中等間隔
      interval = const Duration(seconds: 8);
    } else if (avgTime.inMilliseconds < 1000) {
      // 響應較慢（500-1000ms），使用較長間隔
      interval = const Duration(seconds: 12);
    } else {
      // 響應很慢（>1000ms），使用最長間隔
      interval = const Duration(seconds: 15);
    }
    
    // 確保間隔在合理範圍內
    if (interval.inSeconds < 5) interval = const Duration(seconds: 5);
    if (interval.inSeconds > 30) interval = const Duration(seconds: 30);
    
    debugPrint('API response time: ${avgTime.inMilliseconds}ms, suggested interval: ${interval.inSeconds}s');
    return interval;
  }

  Future<LrtScheduleResponse> fetch(int stationId, {bool useCache = true, HttpErrorProvider? errorProvider}) async {
    final cacheKey = _key(stationId);
    
    if (useCache) {
      final cached = ApiResponseCache.get(cacheKey);
      if (cached != null) {
        // Report success when using valid cache
        errorProvider?.reportApiSuccess();
        return cached as LrtScheduleResponse;
      }
    }
    
    final startTime = DateTime.now();

    if (_debounceTimers.containsKey(cacheKey)) {
      _debounceTimers[cacheKey]!.cancel();
    }

    final completer = Completer<LrtScheduleResponse>();
    _debounceTimers[cacheKey] = Timer(const Duration(milliseconds: 100), () async {
      try {
        final uri = Uri.parse('$base$stationId');
        final res = await _client.get(uri, headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 10));
            
        if (res.statusCode != 200) {
          final errorMessage = 'HTTP ${res.statusCode}';
          errorProvider?.reportApiError(errorMessage);
          throw Exception(errorMessage);
        }
        
        final body = json.decode(res.body);
        if (body is! Map<String, dynamic>) {
          final errorMessage = 'Invalid response format';
          errorProvider?.reportApiError(errorMessage);
          throw Exception(errorMessage);
        }
        
        final parsed = LrtScheduleResponse.fromJson(body);
        ApiResponseCache.cache(cacheKey, parsed, ttl: ttl);
        
        // Record response time
        final endTime = DateTime.now();
        _lastResponseTime = endTime.difference(startTime);
        _responseTimes.add(_lastResponseTime);
        
        if (_responseTimes.length > _maxResponseTimeHistory) {
          _responseTimes.removeAt(0);
        }
        
        // Report success on successful API call
        errorProvider?.reportApiSuccess();
        completer.complete(parsed);
      } catch (e) {
        // Report error for network/parsing failures
        if (e is! Exception || !e.toString().contains('HTTP')) {
          errorProvider?.reportApiError(e.toString());
        }
        completer.completeError(e);
      } finally {
        _debounceTimers.remove(cacheKey);
      }
    });

    return completer.future;
  }

  // 測試API響應時間
  static Future<void> testResponseTime() async {
    debugPrint('Testing API response time...');
    const testStationId = 1; // 使用屯門碼頭作為測試
    final api = LrtApiService();
    
    try {
      final startTime = DateTime.now();
      await api.fetch(testStationId, useCache: false);
      final endTime = DateTime.now();
      final responseTime = endTime.difference(startTime);
      
      debugPrint('Test API response time: ${responseTime.inMilliseconds}ms');
      debugPrint('Suggested refresh interval: ${suggestedRefreshInterval.inSeconds}s');
    } catch (e) {
      debugPrint('API test failed: $e');
    }
  }

  static void dispose() {
    _client.close();
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    ApiResponseCache.clear();
  }
}


/* ========================= HTTP Error Banner ========================= */
class HttpErrorBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final httpError = context.watch<HttpErrorProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (!httpError.hasApiError) return const SizedBox.shrink();
    
    final backgroundColor = isDark ? Colors.red.shade800.withValues(alpha: 0.3) : Colors.red.shade100;
    final textColor = isDark ? Colors.red.shade100 : Colors.red.shade700;
    
    return AnimatedContainer(
      duration: MotionConstants.contentTransition,
      curve: MotionConstants.standardEasing,
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) {
              return Icon(
                httpError.shouldStopRequests ? Icons.error : Icons.warning,
                color: textColor,
                size: 16 * accessibility.iconScale,
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              httpError.getErrorStatusMessage(lang.isEnglish),
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}


/* ========================= 優化的 Station Provider ========================= */

class StationProvider extends ChangeNotifier {
  static const String _stationKey = 'selected_station_id';

  final Map<int, Map<String, String>> stations = const {
    1: {'en': 'Tuen Mun Ferry Pier', 'zh': '屯門碼頭'},
    10: {'en': 'Melody Garden', 'zh': '美樂'},
    15: {'en': 'Butterfly', 'zh': '蝴蝶'},
    20: {'en': 'Light Rail Depot', 'zh': '輕鐵車廠'},
    30: {'en': 'Lung Mun', 'zh': '龍門'},
    40: {'en': 'Tsing Shan Tsuen', 'zh': '青山村'},
    50: {'en': 'Tsing Wun', 'zh': '青雲'},
    60: {'en': 'Kin On', 'zh': '建安'},
    70: {'en': 'Ho Tin', 'zh': '河田'},
    75: {'en': 'Choy Yee Bridge', 'zh': '蔡意橋'},
    80: {'en': 'Affluence', 'zh': '澤豐'},
    90: {'en': 'Tuen Mun Hospital', 'zh': '屯門醫院'},
    100: {'en': 'Siu Hong', 'zh': '兆康'},
    110: {'en': 'Kei Lun', 'zh': '麒麟'},
    120: {'en': 'Ching Chung', 'zh': '青松'},
    130: {'en': 'Kin Sang', 'zh': '建生'},
    140: {'en': 'Tin King', 'zh': '田景'},
    150: {'en': 'Leung King', 'zh': '良景'},
    160: {'en': 'San Wai', 'zh': '新圍'},
    170: {'en': 'Shek Pai', 'zh': '石排'},
    180: {'en': 'Shan King (North)', 'zh': '山景 (北)'},
    190: {'en': 'Shan King (South)', 'zh': '山景 (南)'},
    200: {'en': 'Ming Kum', 'zh': '鳴琴'},
    212: {'en': 'Tai Hing (North)', 'zh': '大興 (北)'},
    220: {'en': 'Tai Hing (South)', 'zh': '大興 (南)'},
    230: {'en': 'Ngan Wai', 'zh': '銀圍'},
    240: {'en': 'Siu Hei', 'zh': '兆禧'},
    250: {'en': 'Tuen Mun Swimming Pool', 'zh': '屯門泳池'},
    260: {'en': 'Goodview Garden', 'zh': '豐景園'},
    265: {'en': 'Siu Lun', 'zh': '兆麟'},
    270: {'en': 'On Ting', 'zh': '安定'},
    275: {'en': 'Yau Oi', 'zh': '友愛'},
    280: {'en': 'Town Centre', 'zh': '市中心'},
    295: {'en': 'Tuen Mun', 'zh': '屯門'},
    300: {'en': 'Pui To', 'zh': '杯渡'},
    310: {'en': 'Hoh Fuk Tong', 'zh': '何福堂'},
    320: {'en': 'San Hui', 'zh': '新墟'},
    330: {'en': 'Prime View', 'zh': '景峰'},
    340: {'en': 'Fung Tei', 'zh': '鳳地'},
    350: {'en': 'Lam Tei', 'zh': '藍地'},
    360: {'en': 'Nai Wai', 'zh': '泥圍'},
    370: {'en': 'Chung Uk Tsuen', 'zh': '鍾屋村'},
    380: {'en': 'Hung Shui Kiu', 'zh': '洪水橋'},
    390: {'en': 'Tong Fong Tsuen', 'zh': '塘坊村'},
    400: {'en': 'Ping Shan', 'zh': '屏山'},
    425: {'en': 'Hang Mei Tsuen', 'zh': '坑尾村'},
    430: {'en': 'Tin Shui Wai', 'zh': '天水圍'},
    435: {'en': 'Tin Tsz', 'zh': '天慈'},
    445: {'en': 'Tin Yiu', 'zh': '天耀'},
    448: {'en': 'Locwood', 'zh': '樂湖'},
    450: {'en': 'Tin Wu', 'zh': '天湖'},
    455: {'en': 'Ginza', 'zh': '銀座'},
    460: {'en': 'Tin Shui', 'zh': '天瑞'},
    468: {'en': 'Chung Fu', 'zh': '頌富'},
    480: {'en': 'Tin Fu', 'zh': '天富'},
    490: {'en': 'Chestwood', 'zh': '翠湖'},
    500: {'en': 'Tin Wing', 'zh': '天榮'},
    510: {'en': 'Tin Yuet', 'zh': '天悅'},
    520: {'en': 'Tin Sau', 'zh': '天秀'},
    530: {'en': 'Wetland Park', 'zh': '濕地公園'},
    540: {'en': 'Tin Heng', 'zh': '天恒'},
    550: {'en': 'Tin Yat', 'zh': '天逸'},
    560: {'en': 'Shui Pin Wai', 'zh': '水邊圍'},
    570: {'en': 'Fung Nin Road', 'zh': '豐年路'},
    580: {'en': 'Hong Lok Road', 'zh': '康樂路'},
    590: {'en': 'Tai Tong Road', 'zh': '大棠路'},
    600: {'en': 'Yuen Long', 'zh': '元朗'},
    920: {'en': 'Sam Shing', 'zh': '三聖'},
  };

  int _selectedStationId = 600;
  bool _userHasSelected = false;
  SharedPreferences? _prefs;
  late final OptimizedSearchIndex _searchIndex;

  int get selectedStationId => _selectedStationId;
  bool get userHasSelected => _userHasSelected;

  StationProvider() {
    // 初始化優化的查找表和搜索索引
    OptimizedStationLookup.initialize(stations);
    _searchIndex = OptimizedSearchIndex();
    _searchIndex.buildIndex(stations);
  }

  Future<void> initialize() async {
    debugPrint('=== StationProvider initialize called ===');
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs!.getInt(_stationKey);
    debugPrint('Saved station ID: $saved');
    
    if (saved != null && stations.containsKey(saved)) {
      _selectedStationId = saved;
      _userHasSelected = true;
      debugPrint('Restored station ID: $_selectedStationId, userHasSelected: $_userHasSelected');
    } else {
      debugPrint('No saved station or invalid station ID');
    }
    notifyListeners();
  }

  Future<void> setStation(int stationId) async {
    debugPrint('=== setStation called for station $stationId ===');
    if (!stations.containsKey(stationId)) {
      debugPrint('Invalid station ID: $stationId');
      return;
    }
    _selectedStationId = stationId;
    _userHasSelected = true;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_stationKey, stationId);
    debugPrint('Station set to: $_selectedStationId, userHasSelected: $_userHasSelected');
    notifyListeners();
  }

  // O(1) 時間複雜度的查找方法
  int? idByEnglish(String name) => OptimizedStationLookup.findByEnglish(name);
  int? idByChinese(String name) => OptimizedStationLookup.findByChinese(name);
  int? idByEither(String en, String zh) => OptimizedStationLookup.findByEnglish(en) ?? OptimizedStationLookup.findByChinese(zh);

  String displayName(int id, bool isEnglish) {
    final data = OptimizedStationLookup.getData(id);
    if (data == null) return 'Unknown';
    return data.displayName(isEnglish);
  }

  // 優化的搜索方法 - O(k) 其中 k 是搜索結果數量
  List<StationData> searchStations(String query) {
    if (query.isEmpty) return OptimizedStationLookup.getAllStations();
    
    final resultIds = _searchIndex.search(query);
    return resultIds
        .map((id) => OptimizedStationLookup.getData(id))
        .where((data) => data != null)
        .cast<StationData>()
        .toList();
  }
}
/* ========================= 優化的 Schedule Provider ========================= */

class ScheduleProvider extends ChangeNotifier {
  final LrtApiService _api = LrtApiService();
  LrtScheduleResponse? _data;
  String? _error;
  bool _loading = false;
  bool _isUsingCachedData = false;
  bool _showCacheAlert = true; // 控制快取警告的顯示
  Timer? _timer;
  int? _currentStationId;
  Duration? _currentRefreshInterval;
  int _adjustmentCheckCounter = 0; // 用於控制間隔調整的頻率

  LrtScheduleResponse? get data => _data;
  String? get error => _error;
  bool get loading => _loading;
  bool get isUsingCachedData => _isUsingCachedData;
  bool get showCacheAlert => _showCacheAlert;

  Future<void> load(int stationId, {bool forceRefresh = false, BuildContext? context}) async {
    final httpError = context?.read<HttpErrorProvider>();
    
    // 檢查是否因 API 錯誤而停止請求
    if (httpError?.shouldStopRequests == true && !httpError!.canRetryAfterError()) {
      debugPrint('ScheduleProvider: 因 API 錯誤跳過載入');
      return;
    }

    debugPrint('Loading data for station $stationId, forceRefresh: $forceRefresh');
    debugPrint('Current station ID before load: $_currentStationId');
    
    if (!forceRefresh && _currentStationId == stationId && data != null) {
      debugPrint('Skipping load - same station and data exists, not forced refresh');
      return;
    }

    _loading = true;
    _error = null;
    _isUsingCachedData = false;

    if (_timer == null || !_timer!.isActive) {
      _currentStationId = stationId;
      debugPrint('Setting current station ID to $stationId (no auto-refresh active)');
    } else {
      debugPrint('Keeping current station ID $_currentStationId (auto-refresh active)');
    }
    
    notifyListeners();

    try {
      _data = await _api.fetch(stationId, useCache: !forceRefresh, errorProvider: httpError);
      
      // 每5次API調用檢查一次間隔調整，避免過於頻繁的調整
      if (_timer != null && _timer!.isActive) {
        _adjustmentCheckCounter++;
        if (_adjustmentCheckCounter >= 5) {
          _adjustRefreshIntervalIfNeeded();
          _adjustmentCheckCounter = 0;
        }
      }
      
      // Clear any previous errors on successful load
      if (httpError != null && _error != null) {
        _error = null;
      }
    } catch (e) {
      _error = e.toString();
      if (data != null) {
        _isUsingCachedData = true;
        _error = null;
      }
      // Error is already reported by LrtApiService, no need to duplicate
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _adjustRefreshIntervalIfNeeded() {
    if (_currentStationId == null) return;
    
    final suggestedInterval = LrtApiService.suggestedRefreshInterval;
    final currentInterval = _getCurrentRefreshInterval();
    
    // 如果建議的間隔與當前間隔相差超過20%，則重新調整
    final difference = (currentInterval.inSeconds - suggestedInterval.inSeconds).abs();
    final threshold = currentInterval.inSeconds * 0.2; // 20%閾值
    
    if (difference > threshold) {
      debugPrint('Adjusting refresh interval from ${currentInterval.inSeconds}s to ${suggestedInterval.inSeconds}s');
      _restartAutoRefreshWithNewInterval(suggestedInterval);
    }
  }

  void _restartAutoRefreshWithNewInterval(Duration newInterval) {
    if (_currentStationId == null) return;
    
    final stationId = _currentStationId!;
    _timer?.cancel();
    _timer = Timer.periodic(newInterval, (_) {
      debugPrint('Auto-refresh timer triggered for station $stationId (restarted)');
      load(stationId, forceRefresh: true);
    });
    _currentRefreshInterval = newInterval;
    debugPrint('Auto-refresh restarted with new interval: ${newInterval.inSeconds}s');
  }

  Duration _getCurrentRefreshInterval() {
    return _currentRefreshInterval ?? const Duration(seconds: 5); // 基於API測試結果優化
  }

  void startAutoRefresh(int stationId, {Duration? interval}) {
    debugPrint('=== startAutoRefresh called for station $stationId ===');
    
    // 避免重複啟動相同車站的自動刷新
    if (_currentStationId == stationId && _timer != null && _timer!.isActive) {
      debugPrint('Auto-refresh already active for station $stationId');
      return;
    }

    // 使用自適應間隔或默認間隔
    final refreshInterval = interval ?? LrtApiService.suggestedRefreshInterval;
    debugPrint('Using refresh interval: ${refreshInterval.inSeconds}s');
    
    // 確保清理舊的timer和重置計數器
    _timer?.cancel();
    _adjustmentCheckCounter = 0;
    
    // 先設置當前車站ID，避免在load過程中被改變
    _currentStationId = stationId;
    _currentRefreshInterval = refreshInterval;
    
    _timer = Timer.periodic(refreshInterval, (_) {
      debugPrint('Auto-refresh timer triggered for station $stationId');
      load(stationId, forceRefresh: true); // 強制刷新以獲取最新數據
    });
    
    // 立即加載一次數據
    load(stationId);
    debugPrint('Auto-refresh started for station $stationId with interval: ${refreshInterval.inSeconds}s');
  }

  void stopAutoRefresh() {
    _timer?.cancel();
    _timer = null;
    _currentStationId = null;
    _currentRefreshInterval = null;
    _adjustmentCheckCounter = 0; // 重置調整檢查計數器
    debugPrint('Auto-refresh stopped');
  }

  // 控制快取警告的顯示
  void setShowCacheAlert(bool show) {
    _showCacheAlert = show;
    notifyListeners();
  }

  // 載入快取警告設定
  Future<void> loadCacheAlertSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showCacheAlert = prefs.getBool('show_cache_alert') ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load cache alert setting: $e');
      _showCacheAlert = true; // 預設顯示
    }
  }

  // 儲存快取警告設定
  Future<void> saveCacheAlertSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_cache_alert', _showCacheAlert);
    } catch (e) {
      debugPrint('Failed to save cache alert setting: $e');
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
  
  bool get isAutoRefreshActive => _timer != null && _timer!.isActive;
  
  // 獲取當前刷新間隔的描述
  String get currentRefreshIntervalDescription {
    if (!isAutoRefreshActive || _currentRefreshInterval == null) {
      return '';
    }
    return '${_currentRefreshInterval!.inSeconds}s';
  }
  
  // 獲取API響應時間的描述
  String get apiResponseTimeDescription {
    final avgTime = LrtApiService.averageResponseTime;
    return '${avgTime.inMilliseconds}ms';
  }
}

/* ========================= Adaptive Index Picker ========================= */

class AdaptiveIndexPicker extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  const AdaptiveIndexPicker({
    super.key,
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.fromLTRB(8, 6, 8, 4),
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Padding(
        padding: padding,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          child: const Text('—'),
        ),
      );
    }

    final safeIndex = selectedIndex.clamp(0, options.length - 1);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4.0, // Horizontal space between chips
            runSpacing: 2.0, // Vertical space between lines of chips
            children: List.generate(options.length, (i) {
              return ChoiceChip(
                label: Text(
                  options[i],
                  // No truncation, text will wrap within the chip
                ),
                selected: i == safeIndex,
                onSelected: (_) => onSelected(i),
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                checkmarkColor: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).colorScheme.surface,
                side: BorderSide(
                  color: (i == safeIndex) 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  width: UIConstants.borderWidthThin,
                ),
              );
              
            }),
          ),
        ],
      ),
    );
  }
}

/* ========================= UI Shell ========================= */

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _pageIndex = 0;
  bool _reverse = false;
  
  // 頁面緩存相關
  static const String _pageIndexKey = 'selected_page_index';
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedPageIndex();
    // Wait for station provider to initialize before starting auto refresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 延遲一點時間確保所有provider都已初始化
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkAndStartAutoRefresh();
        }
      });
    });
  }
  
  
  Future<void> _loadCachedPageIndex() async {
    _prefs ??= await SharedPreferences.getInstance();
    final cachedIndex = _prefs!.getInt(_pageIndexKey) ?? 0;
    // 確保索引在有效範圍內 (0-2)
    if (cachedIndex >= 0 && cachedIndex <= 2) {
      setState(() {
        _pageIndex = cachedIndex;
      });
      debugPrint('Loaded cached page index: $_pageIndex');
    }
  }
  
  Future<void> _savePageIndex(int index) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_pageIndexKey, index);
    debugPrint('Saved page index: $index');
  }
  
  void _checkAndStartAutoRefresh() {
    final station = context.read<StationProvider>();
    final sched = context.read<ScheduleProvider>();
    final connectivity = context.read<ConnectivityProvider>();
    
    debugPrint('=== _checkAndStartAutoRefresh called ===');
    debugPrint('Connectivity isOnline: ${connectivity.isOnline}');
    debugPrint('Station userHasSelected: ${station.userHasSelected}');
    debugPrint('Selected station ID: ${station.selectedStationId}');
    debugPrint('Auto refresh active: ${sched.isAutoRefreshActive}');
    
    if (connectivity.isOnline && station.userHasSelected) {
      debugPrint('Conditions met, checking if auto-refresh is not active');
      if (!sched.isAutoRefreshActive) {
        debugPrint('Starting auto-refresh for station ${station.selectedStationId}');
        sched.load(station.selectedStationId, forceRefresh: true);
        sched.startAutoRefresh(station.selectedStationId);
      } else {
        debugPrint('Auto-refresh already active, skipping');
      }
    } else {
      debugPrint('Conditions not met: online=${connectivity.isOnline}, selected=${station.userHasSelected}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sched = context.read<ScheduleProvider>();
    final station = context.read<StationProvider>();
    final connectivity = context.read<ConnectivityProvider>();
    
    if (state == AppLifecycleState.resumed) {
      // Only resume auto-refresh if user has previously selected a station
      if (connectivity.isOnline && station.userHasSelected) {
        sched.load(station.selectedStationId, forceRefresh: true);
        sched.startAutoRefresh(station.selectedStationId);
      }
    } else if (state == AppLifecycleState.paused) {
      sched.stopAutoRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _goTo(int index) {
    setState(() {
      _reverse = index < _pageIndex;
      _pageIndex = index;
    });
    _savePageIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final sched = context.watch<ScheduleProvider>();
    final station = context.watch<StationProvider>();
    final connectivity = context.watch<ConnectivityProvider>();
    // 更新系統導航欄顏色以適應主題
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        final colorScheme = Theme.of(context).colorScheme;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          systemNavigationBarColor: colorScheme.surface,
          systemNavigationBarIconBrightness: colorScheme.brightness == Brightness.dark 
              ? Brightness.light 
              : Brightness.dark,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: colorScheme.brightness == Brightness.dark 
              ? Brightness.light 
              : Brightness.dark,
        ));
      }
    });

    final pages = [
      _SchedulePage(stationProvider: station, scheduleProvider: sched, key: const ValueKey('schedule')),
      const _RoutesPage(key: ValueKey('routes')),
      const _SettingsPage(key: ValueKey('settings')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: MotionConstants.contentTransition,
          switchInCurve: MotionConstants.standardEasing,
          child: Text(lang.appTitle, key: ValueKey(lang.isEnglish)),
        ),
        actions: [
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => IconButton(
              icon: Icon(Icons.translate, size: 24 * accessibility.iconScale),
              tooltip: lang.language,
              onPressed: lang.toggle,
            ),
          ),
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => IconButton(
              icon: Stack(
                children: [
                  Icon(Icons.refresh, size: 24 * accessibility.iconScale),
                  if (sched.isAutoRefreshActive)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: sched.isAutoRefreshActive 
                  ? '自動刷新已啟用 (${sched.currentRefreshIntervalDescription})' 
                  : lang.refresh,
              onPressed: connectivity.isOnline 
                  ? () {
                      debugPrint('=== Manual refresh button pressed ===');
                      debugPrint('Current auto-refresh state: ${sched.isAutoRefreshActive}');
                      debugPrint('Selected station: ${station.selectedStationId}');
                      
                      if (sched.isAutoRefreshActive) {
                        debugPrint('Stopping auto-refresh');
                        sched.stopAutoRefresh();
                      } else {
                        debugPrint('Starting auto-refresh');
                        sched.startAutoRefresh(station.selectedStationId);
                      }
                    }
                  : null,
            ),
          ),
          Consumer2<AccessibilityProvider, ThemeProvider>(
            builder: (context, accessibility, themeProvider, _) => IconButton(
              icon: Icon(
                themeProvider.useSystemTheme 
                  ? Icons.brightness_auto
                  : (themeProvider.isDarkMode ? Icons.brightness_2 : Icons.brightness_7),
                size: 24 * accessibility.iconScale,
              ),
              tooltip: themeProvider.useSystemTheme 
                  ? (lang.isEnglish ? 'Auto Theme' : '自動主題')
                  : (themeProvider.isDarkMode 
                      ? (lang.isEnglish ? 'Dark Theme' : '深色主題')
                      : (lang.isEnglish ? 'Light Theme' : '淺色主題')),
              onPressed: () {
                if (themeProvider.useSystemTheme) {
                  // Switch from auto to light mode
                  themeProvider.setUseSystemTheme(false);
                  themeProvider.setDarkMode(false);
                } else {
                  if (!themeProvider.isDarkMode) {
                    // Switch from light to dark mode
                    themeProvider.setDarkMode(true);
                  } else {
                    // Switch from dark to auto mode
                    themeProvider.setUseSystemTheme(true);
                  }
                }
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: MotionConstants.contentTransition,
            switchInCurve: MotionConstants.standardEasing,
            child: connectivity.isOffline ? _OfflineBanner() : const SizedBox.shrink(),
          ),
          AnimatedSwitcher(
            duration: MotionConstants.contentTransition,
            switchInCurve: MotionConstants.standardEasing,
            child: context.watch<HttpErrorProvider>().hasApiError ? HttpErrorBanner() : const SizedBox.shrink(),
          ),
          AnimatedSwitcher(
            duration: MotionConstants.contentTransition,
            switchInCurve: MotionConstants.standardEasing,
            child: (sched.isUsingCachedData && sched.showCacheAlert) ? _CachedDataBanner() : const SizedBox.shrink(),
          ),
          Expanded(
            child: PageTransitionSwitcher(
              reverse: _reverse,
              duration: MotionConstants.pageTransition,
              transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
                animation: primary,
                secondaryAnimation: secondary,
                transitionType: SharedAxisTransitionType.horizontal,
                child: child,
              ),
              child: pages[_pageIndex],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: _goTo,
        destinations: [
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => NavigationDestination(
              icon: Icon(Icons.schedule, size: 24 * accessibility.iconScale), 
              label: lang.schedule
            ),
          ),
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => NavigationDestination(
              icon: Icon(Icons.route, size: 24 * accessibility.iconScale), 
              label: lang.routes
            ),
          ),
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => NavigationDestination(
              icon: Icon(Icons.settings, size: 24 * accessibility.iconScale), 
              label: lang.settings
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return AnimatedContainer(
      duration: MotionConstants.contentTransition,
      curve: MotionConstants.standardEasing,
      width: double.infinity,
      color: Colors.orange.shade600,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => Icon(
              Icons.wifi_off, 
              color: Colors.white, 
              size: 18 * accessibility.iconScale
            ),
          ),
          const SizedBox(width: 8),
          Text(lang.offline, style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CachedDataBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.blue.shade800.withValues(alpha: 0.3) : Colors.blue.shade100;
    final textColor = isDark ? Colors.blue.shade100 : Colors.blue.shade700;
    
    return AnimatedContainer(
      duration: MotionConstants.contentTransition,
      curve: MotionConstants.standardEasing,
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => Icon(
              Icons.cached, 
              color: textColor, 
              size: 16 * accessibility.iconScale
            ),
          ),
          const SizedBox(width: 8),
          Text(lang.usingCachedData, style: TextStyle(color: textColor, fontSize: 12)),
        ],
      ),
    );
  }
}

/* ------------------------- Schedule Page ------------------------- */

class _SchedulePage extends StatelessWidget {
  final StationProvider stationProvider;
  final ScheduleProvider scheduleProvider;
  const _SchedulePage({super.key, required this.stationProvider, required this.scheduleProvider});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final connectivity = context.watch<ConnectivityProvider>();

    return Column(
      children: [
        // 優化的車站選擇器
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: _OptimizedStationSelector(
            stationProvider: stationProvider,
            scheduleProvider: scheduleProvider,
            isEnglish: lang.isEnglish,
          ),
        ),
        if (stationProvider.userHasSelected)
          _StatusBar(systemTime: scheduleProvider.data?.systemTime, status: scheduleProvider.data?.status),
        Expanded(
          child: _ScheduleBody(
            loading: scheduleProvider.loading && scheduleProvider.data == null,
            error: scheduleProvider.error,
            data: scheduleProvider.data,
            onRefresh: connectivity.isOnline
                ? () => scheduleProvider.load(stationProvider.selectedStationId, forceRefresh: true)
                : null,
          ),
        ),
      ],
    );
  }


}

class _StatusBar extends StatelessWidget {
  final DateTime? systemTime;
  final int? status;
  const _StatusBar({this.systemTime, this.status});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final ok = status == 1;
    final t = systemTime != null ? '${DateFormat('HH:mm:ss').format(systemTime!)} HKT' : lang.noData;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 根據深色模式調整顏色
    final backgroundColor = ok 
        ? (isDark ? Colors.green.shade800.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.08))
        : (isDark ? Colors.orange.shade800.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.12));
    
    final iconColor = ok
        ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
        : (isDark ? Colors.orange.shade300 : Colors.orange.shade800);
    
    final textColor = ok
        ? (isDark ? Colors.green.shade100 : Colors.green.shade900)
        : (isDark ? Colors.orange.shade100 : Colors.orange.shade900);
    
    return AnimatedContainer(
      duration: MotionConstants.contentTransition,
      curve: MotionConstants.standardEasing,
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Consumer<AccessibilityProvider>(
              builder: (context, accessibility, _) => AnimatedSwitcher(
                duration: MotionConstants.contentTransition,
                child: Icon(
                  ok ? Icons.check_circle : Icons.error, 
                  color: iconColor, 
                  size: 18 * accessibility.iconScale,
                  key: ValueKey(ok),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedDefaultTextStyle(
              duration: MotionConstants.contentTransition,
              curve: MotionConstants.standardEasing,
              style: TextStyle(color: textColor),
              child: Text('${lang.system}: ${ok ? lang.normal : lang.alert} • ${lang.lastUpdated}: $t'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final LrtScheduleResponse? data;
  final Future<void> Function()? onRefresh;
  const _ScheduleBody({required this.loading, required this.error, required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final connectivity = context.watch<ConnectivityProvider>();

    Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      content = _ErrorView(error: error!, onRetry: onRefresh, isOffline: connectivity.isOffline);
    } else if (data == null || data!.platforms.isEmpty) {
      content = Center(child: Text(lang.noData));
    } else {
      content = ImplicitlyAnimatedList<PlatformSchedule>(
        items: data!.platforms,
        areItemsTheSame: (a, b) => a.platformId == b.platformId,
        itemBuilder: (context, anim, platform, index) {
          return SizeFadeTransition(
            sizeFraction: 0.7,
            curve: MotionConstants.standardEasing,
            animation: anim,
            child: _PlatformCard(platform: platform),
          );
        },
      );
    }

    return onRefresh != null
        ? RefreshIndicator(
            onRefresh: onRefresh!,
            child: PageTransitionSwitcher(
              duration: MotionConstants.contentTransition,
              transitionBuilder: (child, p, s) => FadeThroughTransition(
                animation: p, 
                secondaryAnimation: s, 
                child: child
              ),
              child: content,
            ),
          )
        : PageTransitionSwitcher(
            duration: MotionConstants.contentTransition,
            transitionBuilder: (child, p, s) => FadeThroughTransition(
              animation: p, 
              secondaryAnimation: s, 
              child: child
            ),
            child: content,
          );
  }
}

class _PlatformCard extends StatefulWidget {
  final PlatformSchedule platform;
  const _PlatformCard({required this.platform});

  @override
  State<_PlatformCard> createState() => _PlatformCardState();
}

class _PlatformCardState extends State<_PlatformCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  bool _isExpanded = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: MotionConstants.fast,
      vsync: this,
    );

    final curve = CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.deceleratedEasing,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1).animate(curve);
    _elevationAnimation = Tween<double>(begin: 2.0, end: 2.0).animate(curve);

    _isExpanded = widget.platform.trains.isNotEmpty;
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onExpansionChanged(bool expanded) {
    setState(() {
      _isExpanded = expanded;
      _isPressed = false; // Reset press state during expansion changes
    });
    if (expanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // Combine both scale animations: expansion scale * press scale
        final combinedScale = _scaleAnimation.value * (_isPressed ? 1.0 : 1.0);
        
        return Transform.scale(
          scale: combinedScale,
          child: Container(
            margin: UIConstants.platformCardMargin,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(UIConstants.platformCardBorderRadius),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                width: UIConstants.borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: _elevationAnimation.value * 2,
                  offset: Offset(0, _elevationAnimation.value),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UIConstants.platformCardBorderRadius),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(UIConstants.platformCardBorderRadius),
            ),
            child: InkWell(
              splashFactory: InkSparkle.splashFactory,
              borderRadius: BorderRadius.circular(UIConstants.platformCardBorderRadius),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                final color = Theme.of(context).colorScheme.primary;
                if (states.contains(WidgetState.pressed)) return color.withValues(alpha: 0.12);
                if (states.contains(WidgetState.hovered)) return color.withValues(alpha: 0.08);
                return null;
              }),
              onTapDown: (_) {
                if (mounted) setState(() => _isPressed = true);
              },
              onTapUp: (_) {
                if (mounted) setState(() => _isPressed = false);
              },
              onTapCancel: () {
                if (mounted) setState(() => _isPressed = false);
              },
              child: ExpansionTile(
              initiallyExpanded: _isExpanded,
              onExpansionChanged: _onExpansionChanged,
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
          leading: Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => AdaptiveCircleText(
              text: '${widget.platform.platformId}',
              circleSize: 40,
              baseFontSize: 18 * accessibility.textScale,
              fontWeight: FontWeight.w700,
              textColor: Theme.of(context).colorScheme.onPrimaryContainer,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              borderColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          title: Text(
            '${lang.platform} ${widget.platform.platformId}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.87)
                  : null,
            ),
          ),
          children: [
            if (widget.platform.trains.isEmpty)
              ListTile(title: Center(child: Text(lang.noTrains)))
            else
              ImplicitlyAnimatedList<TrainInfo>(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                items: widget.platform.trains,
                areItemsTheSame: (a, b) => a.identity == b.identity,
                itemBuilder: (context, anim, train, i) {
                  return SizeFadeTransition(
                    sizeFraction: 0.7,
                    curve: MotionConstants.standardEasing,
                    animation: anim,
                    child: _TrainTile(train: train, platformId: widget.platform.platformId),
                  );
                },
              ),
          ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _TrainTile extends StatelessWidget {
  final TrainInfo train;
  final int platformId;
  const _TrainTile({required this.train, required this.platformId});

  Color _statusColor(BuildContext context) {
    if (train.isStopped) return Colors.red.shade700;
    if (train.isArrivingSoon) return Colors.orange.shade700;
    if (train.isDepartingSoon) return Colors.blue.shade700;
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final color = _statusColor(context);
    final ad = train.arrivalDeparture.toUpperCase() == 'D' ? lang.departs : lang.arrives;

    return OpenContainer(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: MotionConstants.modalTransition,
      closedElevation: 0,
      openElevation: 4,
      closedColor: Theme.of(context).colorScheme.surface,
      openColor: Theme.of(context).colorScheme.surface,
      closedBuilder: (context, open) => ListTile(
        onTap: open,
        leading: Consumer<AccessibilityProvider>(
          builder: (context, accessibility, _) => AdaptiveCircleText(
            text: train.routeNo.isEmpty ? '?' : train.routeNo,
            circleSize: 40,
            baseFontSize: 14 * accessibility.textScale,
            textColor: color,
            backgroundColor: color.withValues(alpha: 0.15),
            borderColor: color.withValues(alpha: 0.5),
            borderWidth: 1.5,
          ),
        ),
        title: Text(
          train.name(lang.isEnglish),
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white.withValues(alpha: 0.87)
                : null,
          ),
        ),
        subtitle: Text(
          '$ad: ${train.time(lang.isEnglish)} • ${train.trainLength ?? '?'} ${lang.cars}',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white.withValues(alpha: 0.70)
                : null,
          ),
        ),
        trailing: train.isStopped 
            ? Consumer<AccessibilityProvider>(
                builder: (context, accessibility, _) => AnimatedScale(
                  scale: 1.1,
                  duration: MotionConstants.contentTransition,
                  curve: MotionConstants.standardEasing,
                  child: Icon(
                    Icons.block, 
                    color: Colors.red,
                    size: 24 * accessibility.iconScale,
                  ),
                ),
              )
            : null,
      ),
      openBuilder: (context, close) => _TrainDetail(train: train, platformId: platformId),
    );
  }
}

class _TrainDetail extends StatelessWidget {
  final TrainInfo train;
  final int platformId;
  const _TrainDetail({required this.train, required this.platformId});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return Scaffold(
      appBar: AppBar(title: Text('${lang.route} ${train.routeNo}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AnimatedDefaultTextStyle(
            duration: MotionConstants.contentTransition,
            curve: MotionConstants.standardEasing,
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withValues(alpha: 0.95)
                  : null,
              fontWeight: FontWeight.w600,
            ),
            child: Text('${lang.destination}: ${train.name(lang.isEnglish)}'),
          ),
          const Divider(height: 30),
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) => Column(
              children: [
                ListTile(
                  leading: Icon(Icons.signpost_outlined, size: 24 * accessibility.iconScale), 
                  title: Text(
                    lang.platform,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.87)
                          : null,
                      fontWeight: FontWeight.w500,
                    ),
                  ), 
                  subtitle: Text(
                    '$platformId',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.70)
                          : null,
                      fontSize: 18 * accessibility.textScale,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                ),
                ListTile(
                  leading: Icon(Icons.timer_outlined, size: 24 * accessibility.iconScale),
                  title: Text(
                    train.arrivalDeparture.toUpperCase() == 'D' ? lang.departureTime : lang.arrivalTime,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.87)
                          : null,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    train.time(lang.isEnglish),
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.70)
                          : null,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.tram_outlined, size: 24 * accessibility.iconScale), 
                  title: Text(
                    lang.trainLength,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.87)
                          : null,
                      fontWeight: FontWeight.w500,
                    ),
                  ), 
                  subtitle: Text(
                    '${train.trainLength ?? '?'} ${lang.cars}',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.70)
                          : null,
                    ),
                  )
                ),
                ListTile(
                  leading: Icon(Icons.info_outline, size: 24 * accessibility.iconScale), 
                  title: Text(
                    lang.status,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.87)
                          : null,
                      fontWeight: FontWeight.w500,
                    ),
                  ), 
                  subtitle: Text(
                    train.isStopped ? lang.serviceStopped : lang.normalService,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.70)
                          : null,
                    ),
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------- Routes Page (json.txt-driven) ------------------------- */

class _RoutesPage extends StatefulWidget {
  const _RoutesPage({super.key});

  @override
  State<_RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<_RoutesPage> {
  final LrtApiService _api = LrtApiService();
  bool _loading = false;
  Map<int, LrtScheduleResponse> _schedules = {};
  List<String> _unmatched = [];
  bool _showRoutesList = true; // 控制路綫列表的顯示/隱藏
  bool _showDistrictsList = true; // 控制地區列表的顯示/隱藏
  bool _isLoadingCachedData = false;

  Timer? _loadingTimeoutTimer;

  void _startLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (_loading) {
        debugPrint('Routes: Loading timeout reached, forcing stop');
        final httpError = context.read<HttpErrorProvider>();
        httpError.reportApiError('Loading timeout - requests stuck');
        
        setState(() {
          _loading = false;
          _isLoadingCachedData = false;
        });
      }
    });
  }

  void _cancelLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
  }

  @override
  void dispose() {
    _cancelLoadingTimeout();
    super.dispose();
  }


  void checkAndLoadCachedData() {
  final cat = context.read<RoutesCatalogProvider>();
    final net = context.read<ConnectivityProvider>();
    final httpError = context.read<HttpErrorProvider>();
    
    debugPrint('checkAndLoadCachedData called');
    debugPrint('- cat.hasUserSelection: ${cat.hasUserSelection}');
    debugPrint('- schedules.isEmpty: ${_schedules.isEmpty}');
    debugPrint('- loading: $_loading');
    debugPrint('- isLoadingCachedData: $_isLoadingCachedData');
    debugPrint('- net.isOnline: ${net.isOnline}');
    debugPrint('- httpError.shouldStopRequests: ${httpError.shouldStopRequests}');
    
    if (cat.hasUserSelection && 
        _schedules.isEmpty && 
        !_loading && 
        !_isLoadingCachedData && 
        net.isOnline &&
        !httpError.shouldStopRequests) {
      
      // Additional check for retry window if there are errors
      if (httpError.hasApiError && !httpError.canRetryAfterError()) {
        debugPrint('checkAndLoadCachedData: Skipping - waiting for API error retry window');
        return;
      }
      
      debugPrint('Hot reload detected - loading cached route data...');
      _isLoadingCachedData = true;
      _loadForRouteIfNeeded();
    } else {
      debugPrint('checkAndLoadCachedData: Conditions not met');
    }
  }



  @override
  void initState() {
    super.initState();
    // 加載開關狀態緩存
    _loadSwitchStates();
    // 檢查是否有保存的選擇，如果有則自動加載數據
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final cat = context.read<RoutesCatalogProvider>();
        final httpError = context.read<HttpErrorProvider>();
        
        debugPrint('RoutesPage.initState: hasUserSelection=${cat.hasUserSelection}');
        debugPrint('RoutesPage.initState: httpError.shouldStopRequests=${httpError.shouldStopRequests}');
        
        if (cat.hasUserSelection && !httpError.shouldStopRequests) {
          // Additional check for retry window
          if (httpError.hasApiError && !httpError.canRetryAfterError()) {
            debugPrint('RoutesPage.initState: Skipping - waiting for API error retry window');
            return;
          }
          
          debugPrint('RoutesPage.initState: Loading cached route data');
          _loadForRouteIfNeeded();
        } else {
          debugPrint('RoutesPage.initState: Skipping load due to no user selection or API errors');
        }
    });
  }

  void _loadForRouteIfNeeded() {
    final cat = context.read<RoutesCatalogProvider>();
    final sp = context.read<StationProvider>();
    final net = context.read<ConnectivityProvider>();
    final httpError = context.read<HttpErrorProvider>();
    
    debugPrint('_loadForRouteIfNeeded called');
    debugPrint('- cat.selectedRoute: ${cat.selectedRoute?.routeNumber}');
    debugPrint('- net.isOnline: ${net.isOnline}');
    debugPrint('- loading: $_loading');
    debugPrint('- schedules.isEmpty: ${_schedules.isEmpty}');
    debugPrint('- httpError.hasApiError: ${httpError.hasApiError}');
    debugPrint('- httpError.shouldStopRequests: ${httpError.shouldStopRequests}');
    debugPrint('- httpError.canRetryAfterError: ${httpError.canRetryAfterError()}');
    
    // Don't attempt to load if offline
    if (net.isOffline) {
      debugPrint('_loadForRouteIfNeeded: Skipping - offline');
      return;
    }
    
    // Check if we should stop requests due to API errors
    if (httpError.shouldStopRequests && !httpError.canRetryAfterError()) {
      debugPrint('_loadForRouteIfNeeded: Skipping - API errors detected, stopping requests');
      setState(() {
        _loading = false;
        _isLoadingCachedData = false;
      });
      return;
    }
    
    // If we have API errors but can retry, still skip for now to avoid spam
    if (httpError.hasApiError && !httpError.canRetryAfterError()) {
      debugPrint('_loadForRouteIfNeeded: Skipping - API error present, waiting for retry window');
      return;
    }
    
    // Only proceed if we have a selected route and we're not already loading
    if (cat.selectedRoute != null && !_loading && _schedules.isEmpty) {
      debugPrint('_loadForRouteIfNeeded: Loading data for route ${cat.selectedRoute!.routeNumber}');
      _loadForRoute(cat.selectedRoute!, sp, net);
    } else {
      debugPrint('_loadForRouteIfNeeded: Conditions not met - route: ${cat.selectedRoute?.routeNumber}, loading: $_loading, hasData: ${_schedules.isNotEmpty}');
    }
  }


  // 加載開關狀態緩存
  Future<void> _loadSwitchStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showDistrictsList = prefs.getBool('show_districts_list') ?? true;
        _showRoutesList = prefs.getBool('show_routes_list') ?? true;
      });
      debugPrint('_loadSwitchStates: Loaded switch states - districts: $_showDistrictsList, routes: $_showRoutesList');
    } catch (e) {
      debugPrint('_loadSwitchStates: Failed to load switch states: $e');
      // 使用預設值
      setState(() {
        _showDistrictsList = true;
        _showRoutesList = true;
      });
    }
  }

  // 保存開關狀態到緩存
  Future<void> _saveSwitchStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_districts_list', _showDistrictsList);
      await prefs.setBool('show_routes_list', _showRoutesList);
      debugPrint('_saveSwitchStates: Saved switch states - districts: $_showDistrictsList, routes: $_showRoutesList');
    } catch (e) {
      debugPrint('_saveSwitchStates: Failed to save switch states: $e');
    }
  }

  Future<void> _loadForRoute(LrtRoute route, StationProvider sp, ConnectivityProvider net) async {
    if (net.isOffline) return;
    
    final httpErrorProvider = context.read<HttpErrorProvider>();
    if (httpErrorProvider.shouldStopRequests && !httpErrorProvider.canRetryAfterError()) {
      debugPrint('Routes: Skipping load due to API errors');
      setState(() {
        _loading = false;
        _isLoadingCachedData = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _schedules = {};
      _unmatched = [];
    });

    try {
      // Build station ID list
      final ids = <int>[];
      for (final s in route.stations) {
        final id = sp.idByEither(s.en, s.zh);
        if (id != null) {
          ids.add(id);
        } else {
          _unmatched.add('${s.en} / ${s.zh}');
        }
      }

      if (ids.isEmpty) {
        debugPrint('Routes: No valid station IDs found for route ${route.routeNumber}');
        setState(() {
          _loading = false;
          _isLoadingCachedData = false;
        });
        return;
      }

      // Create futures with timeout and better error handling
      final futures = ids.map((id) async {
        try {
          // Add timeout to prevent getting stuck
          final res = await _api.fetch(id).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Request timeout for station $id', const Duration(seconds: 15));
            },
          );
          
          // Report success for each successful call
          httpErrorProvider.reportApiSuccess();
          return MapEntry(id, res);
        } catch (e) {
          // Report error for each failed call
          httpErrorProvider.reportApiError(e.toString());
          debugPrint('Failed to load data for station $id: $e');
          return null;
        }
      });

      // Wait for all requests with overall timeout
      final results = await Future.wait(futures).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Routes: Overall timeout reached for route ${route.routeNumber}');
          httpErrorProvider.reportApiError('Route loading timeout');
          return <MapEntry<int, LrtScheduleResponse>?>[];
        },
      );

      // Process results
      final newSchedules = <int, LrtScheduleResponse>{};
      for (final result in results) {
        if (result != null) {
          newSchedules[result.key] = result.value;
        }
      }

      // Check if we got any data
      if (newSchedules.isEmpty && ids.isNotEmpty) {
        debugPrint('Routes: No data retrieved for any stations in route ${route.routeNumber}');
        httpErrorProvider.reportApiError('No data available for route');
      }

      setState(() {
        _schedules = newSchedules;
        _loading = false;
        _isLoadingCachedData = false;
      });
      
    } catch (e) {
      debugPrint('Routes: Error loading route ${route.routeNumber}: $e');
      httpErrorProvider.reportApiError('Route loading failed: $e');
      
      setState(() {
        _loading = false;
        _isLoadingCachedData = false;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final sp = context.watch<StationProvider>();
    final cat = context.watch<RoutesCatalogProvider>();
    final net = context.watch<ConnectivityProvider>();
    final accessibility = context.watch<AccessibilityProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
    checkAndLoadCachedData();
    });

    final districts = cat.catalog?.districts ?? [];
    if (districts.isEmpty) {
      return Center(child: Text(lang.noData));
    }

    final district = cat.selectedDistrict;
    final routes = district?.routes ?? [];
    final route = cat.selectedRoute;

    // 檢查用戶是否已經進行過選擇
    final hasUserSelection = cat.hasUserSelection;

    final districtNames = districts.map((d) => d.displayName(lang.isEnglish)).toList();
    final routeLabels = routes.map((r) => '${lang.route} ${r.routeNumber} — ${r.displayDescription(lang.isEnglish)}').toList();

    return Column(
      children: [
        // 優化的緩存狀態提示 - 緊湊間距
        if (hasUserSelection)
          AnimatedContainer(
            duration: MotionConstants.contentTransition,
            curve: MotionConstants.standardEasing,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // 最小化垂直間距
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), // 極致最小化內邊距
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                width: UIConstants.borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16 * context.watch<AccessibilityProvider>().iconScale,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${lang.usingCachedData} • ${cat.selectedDistrict?.displayName(lang.isEnglish)} • ${lang.route} ${cat.selectedRoute?.routeNumber}',
                    style: TextStyle(
                      fontSize: 12 * context.watch<AccessibilityProvider>().textScale,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 優化的緊湊間距地區和路綫選擇器 - 統一垂直和水平間距
        AnimatedContainer(
          duration: MotionConstants.contentTransition,
          curve: MotionConstants.standardEasing,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // 最小化垂直間距
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // 極致最小化垂直內邊距
          decoration: BoxDecoration(
            color: hasUserSelection 
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.05)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12), // 保持與按鈕一致的圓角
            boxShadow: [
              BoxShadow(
                color: hasUserSelection
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 1),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(
              color: hasUserSelection
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
              width: hasUserSelection ? UIConstants.borderWidth : UIConstants.borderWidthThin,
            ),
          ),
          child: buildOptimizedPortraitRouteSelector(districtNames, routeLabels, hasUserSelection, cat, sp, net),

        ),
        AnimatedContainer(
          duration: MotionConstants.contentTransition,
          curve: MotionConstants.standardEasing,
          height: _loading ? 3 : 0,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 0.04), // 最小化垂直間距
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: LinearProgressIndicator(
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        if (_unmatched.isNotEmpty)
          AnimatedContainer(
            duration: MotionConstants.contentTransition,
            curve: MotionConstants.standardEasing,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // 最小化垂直間距
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), // 極致最小化垂直內邊距
            decoration: BoxDecoration(
              color: UIConstants.routesWarningBackground(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
                width: UIConstants.borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: UIConstants.routesWarningIconSize(context, accessibility),
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lang.unmatchedStations,
                      style: UIConstants.routesWarningTitleStyle(context, accessibility),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _unmatched
                      .map((n) => Consumer<AccessibilityProvider>(
                            builder: (context, accessibility, _) => Container(
                              padding: UIConstants.routesWarningChipPadding,
                              decoration: BoxDecoration(
                                color: UIConstants.routesWarningBackground(context),
                                borderRadius: BorderRadius.circular(UIConstants.routesWarningChipBorderRadius),
                                border: UIConstants.routesWarningChipBorder(context),
                              ),
                              child: Text(
                                n,
                                style: UIConstants.routesWarningChipStyle(context, accessibility),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: MotionConstants.contentTransition,
            switchInCurve: MotionConstants.standardEasing,
            child: (!hasUserSelection)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 64 * context.watch<AccessibilityProvider>().iconScale,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          lang.selectDistrict,
                          style: TextStyle(
                            fontSize: 18 * context.watch<AccessibilityProvider>().textScale,
                            color: AppColors.getPrimaryTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          lang.selectDistrictDescription,
                          style: TextStyle(
                            fontSize: 14 * context.watch<AccessibilityProvider>().textScale,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : (route == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.route_outlined,
                              size: 64 * context.watch<AccessibilityProvider>().iconScale,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              lang.selectRoute,
                              style: TextStyle(
                                fontSize: 18 * context.watch<AccessibilityProvider>().textScale,
                                color: AppColors.getPrimaryTextColor(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              lang.selectRouteDescription,
                              style: TextStyle(
                                fontSize: 14 * context.watch<AccessibilityProvider>().textScale,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : _RouteSchedulesList(
                        routeNo: route.routeNumber, 
                        routeName: route.displayDescription(lang.isEnglish),
                        schedules: _schedules, 
                        stationProvider: sp
                      )),
          ),
        ),
      ],
    );
  }
  // 優化的橫向模式路綫選擇器 - 帶有視覺分隔綫，支援標籤隱藏時的平行排列
  Widget buildOptimizedPortraitRouteSelector(
    List<String> districtNames,
    List<String> routeLabels,
    bool hasUserSelection,
    RoutesCatalogProvider cat,
    StationProvider sp,
    ConnectivityProvider net,
  ) {
    final lang = context.watch<LanguageProvider>();
    final accessibility = context.watch<AccessibilityProvider>();
    final bool showDistricts = _showDistrictsList && districtNames.isNotEmpty;
    final bool showRoutes = _showRoutesList && hasUserSelection && routeLabels.isNotEmpty;

    // Use LayoutBuilder to make the layout more responsive to available width
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate flex ratio based on available width
        // For wider screens, give more space to the district column
        final isWideScreen = constraints.maxWidth > 600;
        final districtFlex = isWideScreen ? 3 : 1;
        final routeFlex = isWideScreen ? 2 : 1;
        
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // District Column (Left)
            Expanded(
              flex: districtFlex,
              child: AnimatedContainer(
            duration: MotionConstants.contentTransition,
            curve: MotionConstants.standardEasing,
            padding: EdgeInsets.symmetric(
              horizontal: 20, 
              vertical: showDistricts ? 8 : 4,
            ),
            decoration: BoxDecoration(
              color: hasUserSelection && cat.selectedDistrict != null
                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.05)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasUserSelection && cat.selectedDistrict != null
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
                width: UIConstants.borderWidth,
              ),
              boxShadow: UIConstants.cardShadow(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16 * accessibility.iconScale,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasUserSelection && cat.selectedDistrict != null 
                            ? cat.selectedDistrict!.displayName(lang.isEnglish)
                            : lang.selectDistrict,
                        style: TextStyle(
                          fontSize: 13 * accessibility.textScale,
                          fontWeight: FontWeight.w600,
                          color: hasUserSelection && cat.selectedDistrict != null
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Switch(
                      value: _showDistrictsList,
                      onChanged: (value) async {
                        setState(() {
                          _showDistrictsList = value;
                        });
                        await _saveSwitchStates();
                      },
                      //activeThumbColor: Theme.of(context).colorScheme.primary,
                      //activeTrackColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                if (showDistricts && districtNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 4.0,
                      runSpacing: 2.0,
                      children: List.generate(districtNames.length, (i) {
                        final safeIndex = cat.districtIndex.clamp(0, districtNames.length - 1);
                        return ChoiceChip(
                          label: Text(
                            districtNames[i],
                            style: TextStyle(
                              fontSize: 13 * accessibility.textScale,
                              fontWeight: i == safeIndex ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          selected: i == safeIndex,
                          onSelected: (_) async {
                            await cat.setDistrictIndex(i);
                          },
                          selectedColor: Theme.of(context).colorScheme.secondaryContainer,
                          checkmarkColor: Theme.of(context).colorScheme.secondary,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          side: BorderSide(
                            color: (i == safeIndex)
                                ? Theme.of(context).colorScheme.secondary 
                                : Theme.of(context).colorScheme.outline.withAlpha((0.3 * 255).toInt()),
                            width: UIConstants.borderWidthThin,
                          ),
                        );
                      }),
                    ),
                  )
                else if (!_showDistrictsList)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '地區列表已隱藏',
                      style: TextStyle(
                        fontSize: 10 * accessibility.textScale,
                        color: AppColors.getPrimaryTextColor(context),
                        fontStyle: FontStyle.normal,
                        //.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        // Vertical Divider
        Container(
          width: 1,
          height: 80,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        
        // Routes Column (Right)
        Expanded(
          flex: routeFlex,
          child: AnimatedContainer(
            duration: MotionConstants.contentTransition,
            curve: MotionConstants.standardEasing,
            padding: EdgeInsets.symmetric(
              horizontal: 20, 
              vertical: showRoutes ? 8 : 4,
            ),
            decoration: BoxDecoration(
              color: hasUserSelection && cat.selectedRoute != null
                  ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.05)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasUserSelection && cat.selectedRoute != null
                    ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2)
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
                width: UIConstants.borderWidth,
              ),
              boxShadow: UIConstants.cardShadow(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.route_outlined,
                      size: 16 * accessibility.iconScale,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasUserSelection && cat.selectedRoute != null 
                            ? '${lang.route} ${cat.selectedRoute!.routeNumber}'
                            : lang.selectRoute,
                        style: TextStyle(
                          fontSize: 13 * accessibility.textScale,
                          fontWeight: FontWeight.w600,
                          color: hasUserSelection && cat.selectedRoute != null
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Switch(
                      value: _showRoutesList,
                      onChanged: (value) async {
                        setState(() {
                          _showRoutesList = value;
                        });
                        await _saveSwitchStates();
                      },
                      //activeThumbColor: Theme.of(context).colorScheme.primary,
                      //activeTrackColor: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                if (showRoutes && hasUserSelection && routeLabels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 3.0,
                      runSpacing: 1.0,
                      children: List.generate(routeLabels.length, (i) {
                        final safeIndex = cat.routeIndex.clamp(0, routeLabels.length - 1);
                        return ChoiceChip(
                          label: Text(
                            routeLabels[i],
                            style: TextStyle(
                              fontSize: 13 * accessibility.textScale,
                              fontWeight: i == safeIndex ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          selected: i == safeIndex,
                          onSelected: (selected) async {
                            _cancelLoadingTimeout(); // Cancel any existing timeout
                            _startLoadingTimeout();
                            final httpError = context.read<HttpErrorProvider>();
                            
                            // Check if we should skip due to API errors
                            if (httpError.shouldStopRequests && !httpError.canRetryAfterError()) {
                              debugPrint('Route selection: Skipping load due to persistent API errors');
                              await cat.setRouteIndex(i); // Still save the selection
                              return;
                            }
                            
                            // Additional check for retry window if there are errors
                            if (httpError.hasApiError && !httpError.canRetryAfterError()) {
                              debugPrint('Route selection: Skipping load - waiting for API error retry window');
                              await cat.setRouteIndex(i); // Still save the selection
                              return;
                            }
                            
                            await cat.setRouteIndex(i);
                            final selectedRoute = cat.selectedRoute!;
                            debugPrint('Route selected: ${selectedRoute.routeNumber}');
                            await _loadForRoute(selectedRoute, sp, net);
                          },
                          selectedColor: Theme.of(context).colorScheme.secondaryContainer,
                          checkmarkColor: Theme.of(context).colorScheme.secondary,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          side: BorderSide(
                            color: (i==safeIndex) 
                                ? Theme.of(context).colorScheme.secondary 
                                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                            width: UIConstants.borderWidthThin,
                          ),
                        );
                      }),
                    ),
                  )
                else if (!_showRoutesList)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '路綫列表已隱藏',
                      style: TextStyle(
                        fontSize: 10 * accessibility.textScale,
                        color: AppColors.getPrimaryTextColor(context),
                        fontStyle: FontStyle.normal /*.italic*/,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
      },
    );
  }

}

class _RouteSchedulesList extends StatefulWidget {
  final String routeNo;
  final String? routeName;
  final Map<int, LrtScheduleResponse> schedules;
  final StationProvider stationProvider;

  const _RouteSchedulesList({
    Key? key,
    required this.routeNo,
    this.routeName,
    required this.schedules,
    required this.stationProvider,
  }) : super(key: key);

  @override
  State<_RouteSchedulesList> createState() => _RouteSchedulesListState();
}

class _RouteSchedulesListState extends State<_RouteSchedulesList> {
  late List<int> _stationIds;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _stationIds = widget.schedules.keys.toList()..sort();
    // Load saved order for this route (if any)
    _loadSavedOrder();
  }

  @override
  void didUpdateWidget(covariant _RouteSchedulesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If route changed, reload the saved order for the new route
    if (widget.routeNo != oldWidget.routeNo) {
      _loadSavedOrder();
      return;
    }

    // If schedules changed (different set of ids), recompute while preserving order when possible
    final newIds = widget.schedules.keys.toSet();
    final oldIds = _stationIds.toSet();
    if (!setEquals(newIds, oldIds)) {
      // Keep existing order for intersection, append new ids, remove missing
      final intersection = _stationIds.where((id) => newIds.contains(id)).toList();
      final added = widget.schedules.keys.where((id) => !oldIds.contains(id)).toList()..sort();
      _stationIds = [...intersection, ...added];
      // Persist the adjusted order
      _saveOrder();
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _stationIds.removeAt(oldIndex);
      _stationIds.insert(newIndex, id);
    });
    // Fire-and-forget save of the new order
    _saveOrder();
  }

  Future<void> _loadSavedOrder() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final key = 'route_order_${widget.routeNo}';
      final saved = _prefs!.getStringList(key);
      if (saved == null) return;

      final savedIds = <int>[];
      for (final s in saved) {
        final id = int.tryParse(s);
        if (id != null && widget.schedules.containsKey(id)) savedIds.add(id);
      }

      if (savedIds.isEmpty) return;

      // Append any new ids that weren't in saved list
      final remaining = widget.schedules.keys.where((id) => !savedIds.contains(id)).toList()..sort();
      setState(() {
        _stationIds = [...savedIds, ...remaining];
      });
    } catch (e) {
      // ignore errors silently
    }
  }

  Future<void> _saveOrder() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final key = 'route_order_${widget.routeNo}';
      await _prefs!.setStringList(key, _stationIds.map((e) => e.toString()).toList());
    } catch (e) {
      // ignore save errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final accessibility = context.watch<AccessibilityProvider>();

    if (widget.schedules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route_outlined,
              size: 64 * accessibility.iconScale,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              lang.noData,
              style: UIConstants.scheduleNoDataStyle(context, accessibility),
            ),
            const SizedBox(height: 8),
            Text(
              lang.noScheduleDataDescription,
              style: UIConstants.scheduleCaptionStyle(context, accessibility),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Build header
    final stationIdsAll = widget.schedules.keys.toList()..sort();

    Widget header = Container(
      margin: const EdgeInsets.all(8),
      padding: UIConstants.scheduleCardPadding,
      decoration: BoxDecoration(
        color: UIConstants.scheduleHeaderBackground(context),
        borderRadius: BorderRadius.circular(UIConstants.scheduleCardBorderRadius),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: UIConstants.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(UIConstants.scheduleIconBorderRadius),
            ),
            child: Icon(
              Icons.route,
              color: Theme.of(context).colorScheme.onPrimary,
              size: UIConstants.scheduleIconSize(context, accessibility, multiplier: 1.2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText(
                  widget.routeName != null
                      ? '${widget.routeName} (${lang.route} ${widget.routeNo})'
                      : '${lang.route} ${widget.routeNo}',
                  style: UIConstants.scheduleRouteHeaderStyle(context, accessibility),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 3),
                Text(
                  '${stationIdsAll.length} ${lang.stationsServed}',
                  style: UIConstants.scheduleSubtitleStyle(context, accessibility),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Build tile widgets in current order
    final tileWidgets = _stationIds.where((id) => widget.schedules.containsKey(id)).map((id) {
      final sched = widget.schedules[id]!;
      final stationName = widget.stationProvider.displayName(id, lang.isEnglish);

      // collect platform trains
      final platformTrains = <int, List<TrainInfo>>{};
      for (final p in sched.platforms) {
        final trains = p.trains.where((t) => t.routeNo == widget.routeNo).toList();
        if (trains.isNotEmpty) platformTrains[p.platformId] = trains;
      }
      if (platformTrains.isEmpty) return const SizedBox.shrink();

      return Container(
        key: ValueKey('station_$id'),
        margin: UIConstants.scheduleCardMargin,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(UIConstants.scheduleCardBorderRadius),
          boxShadow: UIConstants.scheduleCardShadow(context),
          border: UIConstants.scheduleCardBorder(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: UIConstants.scheduleCardPadding,
              decoration: BoxDecoration(
                color: UIConstants.scheduleHeaderBackground(context),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(UIConstants.scheduleCardBorderRadius),
                  topRight: Radius.circular(UIConstants.scheduleCardBorderRadius),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: UIConstants.scheduleIconSize(context, accessibility),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stationName, style: UIConstants.scheduleStationNameStyle(context, accessibility)),
                        const SizedBox(height: 2),
                        Text(
                          '${platformTrains.length} ${lang.platform}${platformTrains.length > 1 ? 's' : ''}',
                          style: UIConstants.scheduleCaptionStyle(context, accessibility),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: UIConstants.scheduleBadgePadding,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(UIConstants.scheduleBadgeBorderRadius),
                    ),
                    child: Text(
                      '${platformTrains.values.fold<int>(0, (sum, trains) => sum + trains.length)} ${lang.totalTrains}',
                      style: UIConstants.scheduleBadgeStyle(context, accessibility),
                    ),
                  ),
                ],
              ),
            ),
            // Platforms
            ...platformTrains.entries.map((entry) {
              final platformId = entry.key;
              final trains = entry.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                          width: UIConstants.borderWidthThin,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        UIConstants.scheduleCircleText(
                          text: '$platformId',
                          accessibility: accessibility,
                          isStopped: false,
                          context: context,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${lang.platform} $platformId',
                          style: UIConstants.scheduleSubtitleStyle(context, accessibility).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            borderRadius: BorderRadius.circular(UIConstants.borderRadiusXS),
                          ),
                          child: Text(
                            '${trains.length}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSecondary,
                              fontSize: UIConstants.fontSizeS * accessibility.textScale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ImplicitlyAnimatedList<TrainInfo>(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    items: trains,
                    areItemsTheSame: (a, b) => a.identity == b.identity,
                    itemBuilder: (context, anim, train, index) {
                      final ad = train.arrivalDeparture.toUpperCase() == 'D' ? lang.departs : lang.arrives;
                      final isLast = index == trains.length - 1;

                      return SizeFadeTransition(
                        sizeFraction: 0.7,
                        curve: MotionConstants.standardEasing,
                        animation: anim,
                        child: Container(
                          decoration: BoxDecoration(
                            border: isLast ? null : UIConstants.scheduleListTileBorder(context),
                          ),
                          child: ListTile(
                            contentPadding: UIConstants.scheduleListTilePadding,
                            leading: UIConstants.scheduleCircleText(
                              text: train.routeNo,
                              accessibility: accessibility,
                              isStopped: train.isStopped,
                              context: context,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    train.name(lang.isEnglish),
                                    style: UIConstants.scheduleTrainNameStyle(context, accessibility),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (train.isStopped)
                                  Container(
                                    padding: UIConstants.scheduleBadgePadding,
                                    decoration: BoxDecoration(
                                      color: UIConstants.scheduleErrorBackground(context),
                                      borderRadius: BorderRadius.circular(UIConstants.borderRadiusXS),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.block,
                                          color: Colors.red,
                                          size: UIConstants.scheduleIconSize(context, accessibility),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          lang.serviceStopped,
                                          style: UIConstants.scheduleErrorStyle(context, accessibility),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: UIConstants.scheduleSubtitlePadding,
                              child: Row(
                                children: [
                                  Icon(
                                    ad == lang.departs ? Icons.departure_board : Icons.schedule,
                                    size: UIConstants.scheduleIconSize(context, accessibility),
                                    color: AppColors.getPrimaryTextColor(context),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '$ad: ${train.time(lang.isEnglish)}',
                                      style: UIConstants.scheduleBodyStyle(context, accessibility),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.train_outlined,
                                    size: UIConstants.scheduleIconSize(context, accessibility),
                                    color: AppColors.getPrimaryTextColor(context),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${train.trainLength ?? '?'} ${lang.cars}',
                                      style: UIConstants.scheduleBodyStyle(context, accessibility),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            }),
          ],
        ),
      );
    }).where((w) => w is! SizedBox).toList();

    if (tileWidgets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.train_outlined,
              size: UIConstants.scheduleLargeIconSize(context, accessibility),
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              lang.noTrains,
              style: UIConstants.scheduleNoDataStyle(context, accessibility),
            ),
            const SizedBox(height: 8),
            Text(
              lang.noTrainsDescription,
              style: UIConstants.scheduleCaptionStyle(context, accessibility),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: ReorderableListView(
              onReorder: _onReorder,
              padding: EdgeInsets.zero,
              proxyDecorator: (Widget child, int index, Animation<double> animation) {
                return AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (BuildContext context, Widget? child) {
                    final double animValue = Curves.easeInOut.transform(animation.value);
                    final double scale = 1.0 + animValue * 0.05; // Slightly scale up the item
                    return Transform.scale(
                      scale: scale,
                      child: Material(
                        elevation: 4.0 * animValue, // Add a shadow that grows with animation
                        color: Colors.blue.withOpacity(0.8 + animValue * 0.2), // Change background color
                        borderRadius: BorderRadius.circular(10.0),
                        child: child,
                      ),
                    );
                  },
                );
              },
              children: tileWidgets,
            ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
/* ------------------------- Settings Page ------------------------- */

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({super.key});
  
  // 計算對比色，確保圖標在任何背景色上都清晰可見
  Color _getContrastColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
  
  // 構建緊湊的卡片
  Widget _buildCompactCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final accessibility = context.watch<AccessibilityProvider>();
    
    return Container(
      margin: UIConstants.compactCardMargin,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(UIConstants.compactCardBorderRadius),
        boxShadow: UIConstants.compactCardShadow(context),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: UIConstants.borderWidthThin,
        ),
      ),
      child: Padding(
        padding: UIConstants.compactCardPadding,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon, 
                size: UIConstants.settingsIconSize(context, accessibility),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      minHeight: 24 * accessibility.textScale,
                    ),
                    child: Text(
                      title,
                      style: UIConstants.settingsCardTitleStyle(context, accessibility).copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    constraints: BoxConstraints(
                      minHeight: 20 * accessibility.textScale,
                    ),
                    child: Text(
                      subtitle,
                      style: UIConstants.settingsCardSubtitleStyle(context, accessibility).copyWith(
                        fontWeight: FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
  
  // 構建區段標題
  Widget _buildSectionTitle(BuildContext context, String title) {
    final accessibility = context.watch<AccessibilityProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: UIConstants.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20 * accessibility.textScale,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: UIConstants.settingsSectionTitleStyle(context).copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final accessibility = context.watch<AccessibilityProvider>();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return ListView(
      padding: UIConstants.settingsPagePadding,
      children: [
        // 語言設定
        _buildCompactCard(
          context,
          icon: Icons.language,
          title: lang.language,
          subtitle: lang.isEnglish ? lang.english : lang.chinese,
          trailing: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(lang.english)),
              ButtonSegment(value: false, label: Text(lang.chinese)),
            ],
            selected: {lang.isEnglish},
            onSelectionChanged: (sel) async {
              if (sel.first) {
                await lang.setEnglish();
              } else {
                await lang.setChinese();
              }
            },
          ),
        ),
        
        const SizedBox(height: UIConstants.spacingS),
        
        // 橫向模式下的並排佈局
        if (isLandscape)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側：輔助功能設定
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(context, lang.accessibility),
                    const SizedBox(height: UIConstants.spacingXS),
                    
                    // 文字大小設定
                    _buildCompactCard(
                      context,
                      icon: Icons.text_fields,
                      title: lang.textSize,
                      subtitle: accessibility.getTextSizeLabel(accessibility.textScale, lang.isEnglish),
                    ),
                    
                    Padding(
                      padding: UIConstants.settingsSliderPadding,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text('A', style: UIConstants.settingsSliderLabelStyle(context, accessibility)),
                              Expanded(
                                child: Slider(
                                  value: accessibility.textScale,
                                  min: 0.8,
                                  max: 2.0,
                                  divisions: 12,
                                  onChanged: (value) {
                                    accessibility.setTextScale(value);
                                  },
                                ),
                              ),
                              Text('A', style: UIConstants.settingsSliderLabelStyle(context, accessibility)),
                            ],
                          ),
                          const SizedBox(height: UIConstants.spacingXS),
                          Wrap(
                            spacing: UIConstants.spacingXS,
                            runSpacing: UIConstants.spacingXS,
                            children: AccessibilityProvider.textScaleOptions.map((scale) {
                              return ChoiceChip(
                                label: Text(
                                  accessibility.getTextSizeLabel(scale, lang.isEnglish),
                                  style: UIConstants.settingsChoiceChipLabelStyle(context, accessibility),
                                ),
                                selected: accessibility.textScale == scale,
                                onSelected: (selected) {
                                  if (selected) {
                                    accessibility.setTextScale(scale);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: UIConstants.spacingS),
                    
                    // 圖示大小設定
                    _buildCompactCard(
                      context,
                      icon: Icons.apps,
                      title: lang.iconSize,
                      subtitle: accessibility.getIconSizeLabel(accessibility.iconScale, lang.isEnglish),
                    ),
                    
                    Padding(
                      padding: UIConstants.settingsSliderPadding,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.star, size: UIConstants.settingsIconSize(context, accessibility)),
                              Expanded(
                                child: Slider(
                                  value: accessibility.iconScale,
                                  min: 0.8,
                                  max: 2.0,
                                  divisions: 12,
                                  onChanged: (value) {
                                    accessibility.setIconScale(value);
                                  },
                                ),
                              ),
                              Icon(Icons.star, size: UIConstants.settingsLargeIconSize(context, accessibility)),
                            ],
                          ),
                          const SizedBox(height: UIConstants.spacingXS),
                          Wrap(
                            spacing: UIConstants.spacingXS,
                            runSpacing: UIConstants.spacingXS,
                            children: AccessibilityProvider.iconScaleOptions.map((scale) {
                              return ChoiceChip(
                                label: Text(
                                  accessibility.getIconSizeLabel(scale, lang.isEnglish),
                                  style: UIConstants.settingsChoiceChipLabelStyle(context, accessibility),
                                ),
                                selected: accessibility.iconScale == scale,
                                onSelected: (selected) {
                                  if (selected) {
                                    accessibility.setIconScale(scale);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: UIConstants.spacingS),
                    
                    // 頁面縮放設定
                    _buildCompactCard(
                      context,
                      icon: Icons.zoom_in,
                      title: lang.pageScale,
                      subtitle: accessibility.getPageScaleLabel(accessibility.pageScale, lang.isEnglish),
                    ),
                    
                    Padding(
                      padding: UIConstants.settingsSliderPadding,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.zoom_out, size: UIConstants.settingsIconSize(context, accessibility)),
                              Expanded(
                                child: Slider(
                                  value: accessibility.pageScale,
                                  min: 0.8,
                                  max: 2.0,
                                  divisions: 12,
                                  onChanged: (value) {
                                    accessibility.setPageScale(value);
                                  },
                                ),
                              ),
                              Icon(Icons.zoom_in, size: UIConstants.settingsLargeIconSize(context, accessibility)),
                            ],
                          ),
                          const SizedBox(height: UIConstants.spacingXS),
                          Wrap(
                            spacing: UIConstants.spacingXS,
                            runSpacing: UIConstants.spacingXS,
                            children: AccessibilityProvider.pageScaleOptions.map((scale) {
                              return ChoiceChip(
                                label: Text(
                                  accessibility.getPageScaleLabel(scale, lang.isEnglish),
                                  style: UIConstants.settingsChoiceChipLabelStyle(context, accessibility),
                                ),
                                selected: accessibility.pageScale == scale,
                                onSelected: (selected) {
                                  if (selected) {
                                    accessibility.setPageScale(scale);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: UIConstants.spacingS),
                    
                    // 螢幕旋轉設定
                    _buildCompactCard(
                      context,
                      icon: Icons.screen_rotation,
                      title: lang.screenRotation,
                      subtitle: accessibility.screenRotationEnabled 
                          ? lang.enableScreenRotation 
                          : lang.disableScreenRotation,
                      trailing: Switch(
                        value: accessibility.screenRotationEnabled,
                        onChanged: (value) {
                          accessibility.setScreenRotationEnabled(value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: UIConstants.spacingL),
              
              // 右側：主題設定
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(context, lang.theme),
                    const SizedBox(height: UIConstants.spacingXS),
                    
                    // 主題顏色選擇
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, _) => _buildCompactCard(
                        context,
                        icon: Icons.palette,
                        title: lang.themeColor,
                        subtitle: themeProvider.getColorName(themeProvider.seedColor, lang.isEnglish),
                      ),
                    ),
                    
                    // 顏色選擇器
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, _) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
                        child: Wrap(
                          spacing: UIConstants.spacingS,
                          runSpacing: UIConstants.spacingXS + 2,
                          children: ThemeProvider.colorOptions.map((color) {
                            final isSelected = themeProvider.seedColor.toARGB32() == color.toARGB32();
                            return InkWell(
                              onTap: () => themeProvider.setSeedColor(color),
                              borderRadius: BorderRadius.circular(UIConstants.borderRadiusL),
                              child: AnimatedContainer(
                                duration: MotionConstants.contentTransition,
                                curve: MotionConstants.standardEasing,
                                width: UIConstants.colorCircleSizeS,
                                height: UIConstants.colorCircleSizeS,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected 
                                      ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: UIConstants.borderWidth)
                                      : Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), width: UIConstants.borderWidthThin),
                                  boxShadow: isSelected 
                                      ? UIConstants.colorCircleShadow(context, color)
                                      : null,
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        color: _getContrastColor(color),
                                        size: UIConstants.iconSizeXS * accessibility.iconScale,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: UIConstants.spacingS),
                    
                    // 深色模式設定
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, _) => _buildCompactCard(
                        context,
                        icon: Icons.dark_mode,
                        title: lang.darkMode,
                        subtitle: themeProvider.useSystemTheme 
                            ? lang.systemTheme 
                            : (themeProvider.isDarkMode ? lang.darkMode : lang.lightMode),
                        trailing: SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(value: true, label: Text(lang.darkMode)),
                            ButtonSegment(value: false, label: Text(lang.lightMode)),
                          ],
                          selected: {themeProvider.isDarkMode},
                          onSelectionChanged: (sel) async {
                            await themeProvider.setDarkMode(sel.first);
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: UIConstants.spacingXS),
                    
                    // 系統主題設定
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, _) => _buildCompactCard(
                        context,
                        icon: Icons.settings_suggest,
                        title: lang.systemTheme,
                        subtitle: themeProvider.useSystemTheme 
                            ? lang.useSystemTheme 
                            : lang.manualTheme,
                        trailing: Switch(
                          value: themeProvider.useSystemTheme,
                          onChanged: (value) {
                            themeProvider.setUseSystemTheme(value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          // 直向模式下的原有佈局
          Column(
            children: [
              // 輔助功能標題
              _buildSectionTitle(context, lang.accessibility),
              
              const SizedBox(height: UIConstants.spacingXS),
              
              // 文字大小設定
              _buildCompactCard(
                context,
                icon: Icons.text_fields,
                title: lang.textSize,
                subtitle: accessibility.getTextSizeLabel(accessibility.textScale, lang.isEnglish),
              ),
              
              Padding(
                padding: UIConstants.settingsSliderPadding,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('A', style: UIConstants.settingsSliderLabelStyle(context, accessibility)),
                        Expanded(
                          child: Slider(
                            value: accessibility.textScale,
                            min: 0.8,
                            max: 2.0,
                            divisions: 12,
                            onChanged: (value) {
                              accessibility.setTextScale(value);
                            },
                          ),
                        ),
                        Text('A', style: UIConstants.settingsSliderLabelStyle(context, accessibility)),
                      ],
                    ),
                    const SizedBox(height: UIConstants.spacingXS),
                    Wrap(
                      spacing: UIConstants.spacingXS,
                      runSpacing: UIConstants.spacingXS,
                      children: AccessibilityProvider.textScaleOptions.map((scale) {
                        return ChoiceChip(
                          label: Text(
                            accessibility.getTextSizeLabel(scale, lang.isEnglish),
                            style: UIConstants.settingsChoiceChipLabelStyle(context, accessibility),
                          ),
                          selected: accessibility.textScale == scale,
                          onSelected: (selected) {
                            if (selected) {
                              accessibility.setTextScale(scale);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: UIConstants.spacingS),
              
              // 圖示大小設定
              _buildCompactCard(
                context,
                icon: Icons.apps,
                title: lang.iconSize,
                subtitle: accessibility.getIconSizeLabel(accessibility.iconScale, lang.isEnglish),
              ),
              
              Padding(
                padding: UIConstants.settingsSliderPadding,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.star, size: UIConstants.settingsIconSize(context, accessibility)),
                        Expanded(
                          child: Slider(
                            value: accessibility.iconScale,
                            min: 0.8,
                            max: 2.0,
                            divisions: 12,
                            onChanged: (value) {
                              accessibility.setIconScale(value);
                            },
                          ),
                        ),
                        Icon(Icons.star, size: UIConstants.settingsLargeIconSize(context, accessibility)),
                      ],
                    ),
                    const SizedBox(height: UIConstants.spacingXS),
                    Wrap(
                      spacing: UIConstants.spacingXS,
                      runSpacing: UIConstants.spacingXS,
                      children: AccessibilityProvider.iconScaleOptions.map((scale) {
                        return ChoiceChip(
                          label: Text(
                            accessibility.getIconSizeLabel(scale, lang.isEnglish),
                            style: UIConstants.settingsChoiceChipLabelStyle(context, accessibility),
                          ),
                          selected: accessibility.iconScale == scale,
                          onSelected: (selected) {
                            if (selected) {
                              accessibility.setIconScale(scale);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: UIConstants.spacingS),
              
              // 頁面縮放設定
              _buildCompactCard(
                context,
                icon: Icons.zoom_in,
                title: lang.pageScale,
                subtitle: accessibility.getPageScaleLabel(accessibility.pageScale, lang.isEnglish),
              ),
              
              Padding(
                padding: UIConstants.settingsSliderPadding,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.zoom_out, size: UIConstants.settingsIconSize(context, accessibility)),
                        Expanded(
                          child: Slider(
                            value: accessibility.pageScale,
                            min: 0.8,
                            max: 2.0,
                            divisions: 12,
                            onChanged: (value) {
                              accessibility.setPageScale(value);
                            },
                          ),
                        ),
                        Icon(Icons.zoom_in, size: UIConstants.settingsLargeIconSize(context, accessibility)),
                      ],
                    ),
                    const SizedBox(height: UIConstants.spacingXS),
                    Wrap(
                      spacing: UIConstants.spacingXS,
                      runSpacing: UIConstants.spacingXS,
                      children: AccessibilityProvider.pageScaleOptions.map((scale) {
                        return ChoiceChip(
                          label: Text(
                            accessibility.getPageScaleLabel(scale, lang.isEnglish),
                            style: UIConstants.settingsChoiceChipLabelStyle(context, accessibility),
                          ),
                          selected: accessibility.pageScale == scale,
                          onSelected: (selected) {
                            if (selected) {
                              accessibility.setPageScale(scale);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: UIConstants.spacingS),
              
              // 螢幕旋轉設定
              _buildCompactCard(
                context,
                icon: Icons.screen_rotation,
                title: lang.screenRotation,
                subtitle: accessibility.screenRotationEnabled 
                    ? lang.enableScreenRotation 
                    : lang.disableScreenRotation,
                trailing: Switch(
                  value: accessibility.screenRotationEnabled,
                  onChanged: (value) {
                    accessibility.setScreenRotationEnabled(value);
                  },
                ),
              ),
            ],
          ),
        // 直向模式下的主題設定
        if (!isLandscape) ...[
          const SizedBox(height: UIConstants.spacingM),
          
          // 主題設定標題
          _buildSectionTitle(context, lang.theme),
          
          const SizedBox(height: UIConstants.spacingXS),
          
          // 主題顏色選擇
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => _buildCompactCard(
              context,
              icon: Icons.palette,
              title: lang.themeColor,
              subtitle: themeProvider.getColorName(themeProvider.seedColor, lang.isEnglish),
            ),
          ),
          
          // 顏色選擇器
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
              child: Wrap(
                spacing: UIConstants.spacingXS,
                runSpacing: UIConstants.spacingXS,
                children: ThemeProvider.colorOptions.map((color) {
                  final isSelected = themeProvider.seedColor.toARGB32() == color.toARGB32();
                  return InkWell(
                    onTap: () => themeProvider.setSeedColor(color),
                    borderRadius: BorderRadius.circular(UIConstants.borderRadiusL),
                    child: AnimatedContainer(
                      duration: MotionConstants.contentTransition,
                      curve: MotionConstants.standardEasing,
                      width: UIConstants.colorCircleSizeS,
                      height: UIConstants.colorCircleSizeS,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected 
                            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: UIConstants.borderWidth)
                            : Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), width: UIConstants.borderWidthThin),
                        boxShadow: isSelected 
                            ? UIConstants.colorCircleShadow(context, color)
                            : null,
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: _getContrastColor(color),
                              size: UIConstants.iconSizeXS * accessibility.iconScale,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: UIConstants.spacingS),
          
          // 深色模式設定
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => _buildCompactCard(
              context,
              icon: themeProvider.useSystemTheme 
                  ? Icons.brightness_auto
                  : themeProvider.isDarkMode 
                      ? Icons.dark_mode 
                      : Icons.light_mode,
              title: lang.darkMode,
              subtitle: themeProvider.useSystemTheme 
                  ? lang.systemTheme
                  : themeProvider.isDarkMode 
                      ? lang.darkMode 
                      : lang.lightMode,
            ),
          ),
          
          // 系統主題切換
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingS),
                    title: Text(
                      lang.systemTheme,
                      style: TextStyle(fontSize: 13 * accessibility.textScale),
                    ),
                    leading: Radio<bool>(
                      value: true,
                      groupValue: themeProvider.useSystemTheme,
                      onChanged: (value) {
                        if (value != null) {
                          themeProvider.setUseSystemTheme(value);
                        }
                      },
                    ),
                    subtitle: Text(
                      lang.useSystemTheme,
                      style: TextStyle(fontSize: 11 * accessibility.textScale),
                    ),
                  ),
                                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingS),
                    title: Text(
                      lang.manualTheme,
                      style: TextStyle(fontSize: 13 * accessibility.textScale),
                    ),
                  leading: Radio<bool>(
                    value: false,
                    groupValue: themeProvider.useSystemTheme,
                    onChanged: (value) {
                      if (value != null) {
                        themeProvider.setUseSystemTheme(value);
                      }
                    },
                  ),
                ),
                if (!themeProvider.useSystemTheme)
                  Padding(
                    padding: const EdgeInsets.only(left: UIConstants.spacingL, top: UIConstants.spacingXS),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(lang.lightMode),
                          icon: Icon(Icons.light_mode, size: UIConstants.iconSizeXS * accessibility.iconScale),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(lang.darkMode),
                          icon: Icon(Icons.dark_mode, size: UIConstants.iconSizeXS * accessibility.iconScale),
                        ),
                      ],
                      selected: {themeProvider.isDarkMode},
                      onSelectionChanged: (selection) {
                        themeProvider.setDarkMode(selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        const SizedBox(height: UIConstants.spacingM),
        
        // 開發者設定區段
        _buildSectionTitle(context, lang.isEnglish ? 'Developer Settings' : '開發者設定'),
        const SizedBox(height: UIConstants.spacingXS),
        
        // 隱藏車站ID設定
        Consumer<DeveloperSettingsProvider>(
          builder: (context, devSettings, _) => _buildCompactCard(
            context,
            icon: Icons.visibility_off,
            title: lang.isEnglish ? 'Hide Station ID' : '隱藏車站ID',
            subtitle: devSettings.hideStationId 
                ? (lang.isEnglish ? 'Station ID is hidden' : '車站ID已隱藏')
                : (lang.isEnglish ? 'Station ID is visible' : '車站ID可見'),
            trailing: Switch(
              value: devSettings.hideStationId,
              onChanged: (value) {
                devSettings.setHideStationId(value);
              },
            ),
          ),
        ),
        
        const SizedBox(height: UIConstants.spacingXS),
        
        // Show Grid Debug Label setting
        Consumer<DeveloperSettingsProvider>(
          builder: (context, devSettings, _) => _buildCompactCard(
            context,
            icon: Icons.grid_3x3,
            title: lang.isEnglish ? 'Show Grid Debug Info' : '顯示網格偵錯資訊',
            subtitle: devSettings.showGridDebug 
                ? (lang.isEnglish ? 'Grid debug info is visible' : '網格偵錯資訊可見')
                : (lang.isEnglish ? 'Grid debug info is hidden' : '網格偵錯資訊已隱藏'),
            trailing: Switch(
              value: devSettings.showGridDebug,
              onChanged: (value) {
                devSettings.setShowGridDebug(value);
              },
            ),
          ),
        ),
        
        const SizedBox(height: UIConstants.spacingXS),
        
        // 快取警告設定
        Consumer<ScheduleProvider>(
          builder: (context, scheduleProvider, _) => _buildCompactCard(
            context,
            icon: Icons.cached,
            title: lang.showCacheAlert,
            subtitle: scheduleProvider.showCacheAlert 
                ? lang.cacheAlertDescription
                : (lang.isEnglish ? 'Cache alert is hidden' : '快取警告已隱藏'),
            trailing: Switch(
              value: scheduleProvider.showCacheAlert,
              onChanged: (value) async {
                scheduleProvider.setShowCacheAlert(value);
                await scheduleProvider.saveCacheAlertSetting();
              },
              activeThumbColor: Theme.of(context).colorScheme.primary,
              activeTrackColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              inactiveThumbColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
              inactiveTrackColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
        ),
        
        const SizedBox(height: UIConstants.spacingM),
        
        // 快取測試按鈕
        Consumer<RoutesCatalogProvider>(
          builder: (context, cat, _) => _buildCompactCard(
            context,
            icon: Icons.cached,
            title: '快取測試',
            subtitle: '當前選擇: ${cat.selectedDistrict?.displayName(lang.isEnglish) ?? "無"} - ${cat.selectedRoute?.routeNumber ?? "無"} (hasUserSelection: ${cat.hasUserSelection})',
            trailing: IconButton(
              icon: Icon(Icons.refresh, size: UIConstants.settingsIconSize(context, accessibility)),
                              onPressed: () {
                  debugPrint('=== 快取測試按鈕被點擊 ===');
                  debugPrint('districtIndex: ${cat.districtIndex}');
                  debugPrint('routeIndex: ${cat.routeIndex}');
                  debugPrint('selectedDistrict: ${cat.selectedDistrict?.displayName(lang.isEnglish)}');
                  debugPrint('selectedRoute: ${cat.selectedRoute?.routeNumber}');
                  debugPrint('hasUserSelection: ${cat.hasUserSelection}');
                },
            ),
          ),
        ),
      ],
    );
  }
}

/* ------------------------- Embedded routes JSON ------------------------- */

const String kRoutesJson = r'''
{
  "light_rail_system": {
    "districts": [
      {
        "name": "Tuen Mun",
        "routes": [
          {
            "route_number": "505",
            "description": "Sam Shing↔Siu Hong",
            "stations": [
              {"name_en": "Kin On", "name_zh": "建安"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "Kei Lun", "name_zh": "麒麟"},
              {"name_en": "Ching Chung", "name_zh": "青松"},
              {"name_en": "Kin Sang", "name_zh": "建生"},
              {"name_en": "Tin King", "name_zh": "田景"},
              {"name_en": "Leung King", "name_zh": "良景"},
              {"name_en": "San Wai", "name_zh": "新圍"},
              {"name_en": "Shek Pai", "name_zh": "石排"},
              {"name_en": "Shan King (North)", "name_zh": "山景 (北)"},
              {"name_en": "Shan King (South)", "name_zh": "山景 (南)"},
              {"name_en": "Ming Kum", "name_zh": "鳴琴"},
              {"name_en": "Siu Lun", "name_zh": "兆麟"},
              {"name_en": "On Ting", "name_zh": "安定"},
              {"name_en": "Town Centre", "name_zh": "市中心"},
              {"name_en": "Tuen Mun", "name_zh": "屯門"},
              {"name_en": "Sam Shing", "name_zh": "三聖"}
            ]
          },
          {
            "route_number": "507",
            "description": "Tuen Mun Ferry Pier↔Tin King",
            "stations": [
              {"name_en": "Tuen Mun Ferry Pier", "name_zh": "屯門碼頭"},
              {"name_en": "Ho Tin", "name_zh": "河田"},
              {"name_en": "Choy Yee Bridge", "name_zh": "蔡意橋"},
              {"name_en": "Tin King", "name_zh": "田景"},
              {"name_en": "Leung King", "name_zh": "良景"},
              {"name_en": "San Wai", "name_zh": "新圍"},
              {"name_en": "Tai Hing (North)", "name_zh": "大興 (北)"},
              {"name_en": "Tai Hing (South)", "name_zh": "大興 (南)"},
              {"name_en": "Ngan Wai", "name_zh": "銀圍"},
              {"name_en": "Siu Hei", "name_zh": "兆禧"},
              {"name_en": "Tuen Mun Swimming Pool", "name_zh": "屯門泳池"},
              {"name_en": "Goodview Garden", "name_zh": "豐景園"},
              {"name_en": "Siu Lun", "name_zh": "兆麟"},
              {"name_en": "On Ting", "name_zh": "安定"},
              {"name_en": "Town Centre", "name_zh": "市中心"},
              {"name_en": "Tuen Mun", "name_zh": "屯門"}
            ]
          },
          {
            "route_number": "614P",
            "description": "Tuen Mun Ferry Pier↔Siu Hong",
            "stations": [
              {"name_en": "Tuen Mun Ferry Pier", "name_zh": "屯門碼頭"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "Siu Hei", "name_zh": "兆禧"},
              {"name_en": "Tuen Mun Swimming Pool", "name_zh": "屯門泳池"},
              {"name_en": "Goodview Garden", "name_zh": "豐景園"},
              {"name_en": "On Ting", "name_zh": "安定"},
              {"name_en": "Town Centre", "name_zh": "市中心"},
              {"name_en": "Pui To", "name_zh": "杯渡"},
              {"name_en": "Hoh Fuk Tong", "name_zh": "何福堂"},
              {"name_en": "San Hui", "name_zh": "新墟"},
              {"name_en": "Prime View", "name_zh": "景峰"},
              {"name_en": "Fung Tei", "name_zh": "鳳地"}
            ]
          },
          {
            "route_number": "615P",
            "description": "Tuen Mun Ferry Pier↔Siu Hong",
            "stations": [
              {"name_en": "Tuen Mun Ferry Pier", "name_zh": "屯門碼頭"},
              {"name_en": "Melody Garden", "name_zh": "美樂"},
              {"name_en": "Butterfly", "name_zh": "蝴蝶"},
              {"name_en": "Light Rail Depot", "name_zh": "輕鐵車廠"},
              {"name_en": "Lung Mun", "name_zh": "龍門"},
              {"name_en": "Tsing Shan Tsuen", "name_zh": "青山村"},
              {"name_en": "Tsing Wun", "name_zh": "青雲"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "Kei Lun", "name_zh": "麒麟"},
              {"name_en": "Ching Chung", "name_zh": "青松"},
              {"name_en": "Kin Sang", "name_zh": "建生"},
              {"name_en": "Tin King", "name_zh": "田景"},
              {"name_en": "Leung King", "name_zh": "良景"},
              {"name_en": "San Wai", "name_zh": "新圍"},
              {"name_en": "Shek Pai", "name_zh": "石排"},
              {"name_en": "Ming Kum", "name_zh": "鳴琴"}
            ]
          }
        ]
      },
      {
        "name": "Tin Shui Wai",
        "routes": [
          {
            "route_number": "705",
            "description": "Tin Shui Wai Loop (Anti-clockwise)",
            "stations": [
              {"name_en": "Tin Shui Wai", "name_zh": "天水圍"},
              {"name_en": "Tin Tsz", "name_zh": "天慈"},
              {"name_en": "Tin Yiu", "name_zh": "天耀"},
              {"name_en": "Locwood", "name_zh": "樂湖"},
              {"name_en": "Tin Wu", "name_zh": "天湖"},
              {"name_en": "Ginza", "name_zh": "銀座"},
              {"name_en": "Tin Shui", "name_zh": "天瑞"},
              {"name_en": "Chung Fu", "name_zh": "頌富"},
              {"name_en": "Tin Fu", "name_zh": "天富"},
              {"name_en": "Tin Wing", "name_zh": "天榮"},
              {"name_en": "Tin Yuet", "name_zh": "天悅"},
              {"name_en": "Tin Sau", "name_zh": "天秀"},
              {"name_en": "Wetland Park", "name_zh": "濕地公園"},
              {"name_en": "Tin Heng", "name_zh": "天恒"},
              {"name_en": "Tin Yat", "name_zh": "天逸"}
            ]
          },
          {
            "route_number": "706",
            "description": "Tin Shui Wai Loop (Clockwise)",
            "stations": [
              {"name_en": "Tin Shui Wai", "name_zh": "天水圍"},
              {"name_en": "Tin Tsz", "name_zh": "天慈"},
              {"name_en": "Tin Yiu", "name_zh": "天耀"},
              {"name_en": "Locwood", "name_zh": "樂湖"},
              {"name_en": "Tin Wu", "name_zh": "天湖"},
              {"name_en": "Ginza", "name_zh": "銀座"},
              {"name_en": "Tin Shui", "name_zh": "天瑞"},
              {"name_en": "Chung Fu", "name_zh": "頌富"},
              {"name_en": "Tin Fu", "name_zh": "天富"},
              {"name_en": "Tin Wing", "name_zh": "天榮"},
              {"name_en": "Tin Yuet", "name_zh": "天悅"},
              {"name_en": "Tin Sau", "name_zh": "天秀"},
              {"name_en": "Wetland Park", "name_zh": "濕地公園"},
              {"name_en": "Tin Heng", "name_zh": "天恒"},
              {"name_en": "Tin Yat", "name_zh": "天逸"}
            ]
          },
          {
            "route_number": "751P",
            "description": "Tin Yat↔Tin Shui Wai",
            "stations": [
              {"name_en": "Tin Shui Wai", "name_zh": "天水圍"},
              {"name_en": "Tin Tsz", "name_zh": "天慈"},
              {"name_en": "Tin Wu", "name_zh": "天湖"},
              {"name_en": "Ginza", "name_zh": "銀座"},
              {"name_en": "Chung Fu", "name_zh": "頌富"},
              {"name_en": "Tin Fu", "name_zh": "天富"},
              {"name_en": "Chestwood", "name_zh": "翠湖"},
              {"name_en": "Tin Wing", "name_zh": "天榮"},
              {"name_en": "Tin Yat", "name_zh": "天逸"}
            ]
          }
        ]
      },
      {
        "name": "Inter-District",
        "routes": [
          {
            "route_number": "610",
            "description": "Tuen Mun Ferry Pier↔Yuen Long",
            "stations": [
              {"name_en": "Tuen Mun Ferry Pier", "name_zh": "屯門碼頭"},
              {"name_en": "Melody Garden", "name_zh": "美樂"},
              {"name_en": "Butterfly", "name_zh": "蝴蝶"},
              {"name_en": "Light Rail Depot", "name_zh": "輕鐵車廠"},
              {"name_en": "Lung Mun", "name_zh": "龍門"},
              {"name_en": "Tsing Shan Tsuen", "name_zh": "青山村"},
              {"name_en": "Tsing Wun", "name_zh": "青雲"},
              {"name_en": "Ho Tin", "name_zh": "河田"},
              {"name_en": "Choy Yee Bridge", "name_zh": "蔡意橋"},
              {"name_en": "Affluence", "name_zh": "澤豐"},
              {"name_en": "Tuen Mun Hospital", "name_zh": "屯門醫院"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "Ming Kum", "name_zh": "鳴琴"},
              {"name_en": "Tai Hing (North)", "name_zh": "大興 (北)"},
              {"name_en": "Tai Hing (South)", "name_zh": "大興 (南)"},
              {"name_en": "Ngan Wai", "name_zh": "銀圍"},
              {"name_en": "Tuen Mun", "name_zh": "屯門"},
              {"name_en": "Lam Tei", "name_zh": "藍地"},
              {"name_en": "Nai Wai", "name_zh": "泥圍"},
              {"name_en": "Chung Uk Tsuen", "name_zh": "鍾屋村"},
              {"name_en": "Hung Shui Kiu", "name_zh": "洪水橋"},
              {"name_en": "Tong Fong Tsuen", "name_zh": "塘坊村"},
              {"name_en": "Ping Shan", "name_zh": "屏山"},
              {"name_en": "Shui Pin Wai", "name_zh": "水邊圍"},
              {"name_en": "Fung Nin Road", "name_zh": "豐年路"},
              {"name_en": "Hong Lok Road", "name_zh": "康樂路"},
              {"name_en": "Tai Tong Road", "name_zh": "大棠路"},
              {"name_en": "Yuen Long", "name_zh": "元朗"}
            ]
          },
          {
            "route_number": "614",
            "description": "Tuen Mun Ferry Pier↔Yuen Long",
            "stations": [
              {"name_en": "Tuen Mun Ferry Pier", "name_zh": "屯門碼頭"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "Siu Hei", "name_zh": "兆禧"},
              {"name_en": "Tuen Mun Swimming Pool", "name_zh": "屯門泳池"},
              {"name_en": "Goodview Garden", "name_zh": "豐景園"},
              {"name_en": "On Ting", "name_zh": "安定"},
              {"name_en": "Town Centre", "name_zh": "市中心"},
              {"name_en": "Pui To", "name_zh": "杯渡"},
              {"name_en": "Hoh Fuk Tong", "name_zh": "何福堂"},
              {"name_en": "San Hui", "name_zh": "新墟"},
              {"name_en": "Prime View", "name_zh": "景峰"},
              {"name_en": "Fung Tei", "name_zh": "鳳地"},
              {"name_en": "Lam Tei", "name_zh": "藍地"},
              {"name_en": "Nai Wai", "name_zh": "泥圍"},
              {"name_en": "Chung Uk Tsuen", "name_zh": "鍾屋村"},
              {"name_en": "Hung Shui Kiu", "name_zh": "洪水橋"},
              {"name_en": "Tong Fong Tsuen", "name_zh": "塘坊村"},
              {"name_en": "Ping Shan", "name_zh": "屏山"},
              {"name_en": "Shui Pin Wai", "name_zh": "水邊圍"},
              {"name_en": "Fung Nin Road", "name_zh": "豐年路"},
              {"name_en": "Hong Lok Road", "name_zh": "康樂路"},
              {"name_en": "Tai Tong Road", "name_zh": "大棠路"},
              {"name_en": "Yuen Long", "name_zh": "元朗"}
            ]
          },
          {
            "route_number": "615",
            "description": "Tuen Mun Ferry Pier↔Yuen Long",
            "stations": [
              {"name_en": "Tuen Mun Ferry Pier", "name_zh": "屯門碼頭"},
              {"name_en": "Melody Garden", "name_zh": "美樂"},
              {"name_en": "Butterfly", "name_zh": "蝴蝶"},
              {"name_en": "Light Rail Depot", "name_zh": "輕鐵車廠"},
              {"name_en": "Lung Mun", "name_zh": "龍門"},
              {"name_en": "Tsing Shan Tsuen", "name_zh": "青山村"},
              {"name_en": "Tsing Wun", "name_zh": "青雲"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "Ching Chung", "name_zh": "青松"},
              {"name_en": "Kin Sang", "name_zh": "建生"},
              {"name_en": "Tin King", "name_zh": "田景"},
              {"name_en": "Leung King", "name_zh": "良景"},
              {"name_en": "San Wai", "name_zh": "新圍"},
              {"name_en": "Shek Pai", "name_zh": "石排"},
              {"name_en": "Ming Kum", "name_zh": "鳴琴"},
              {"name_en": "Lam Tei", "name_zh": "藍地"},
              {"name_en": "Nai Wai", "name_zh": "泥圍"},
              {"name_en": "Chung Uk Tsuen", "name_zh": "鍾屋村"},
              {"name_en": "Hung Shui Kiu", "name_zh": "洪水橋"},
              {"name_en": "Tong Fong Tsuen", "name_zh": "塘坊村"},
              {"name_en": "Ping Shan", "name_zh": "屏山"},
              {"name_en": "Shui Pin Wai", "name_zh": "水邊圍"},
              {"name_en": "Fung Nin Road", "name_zh": "豐年路"},
              {"name_en": "Hong Lok Road", "name_zh": "康樂路"},
              {"name_en": "Tai Tong Road", "name_zh": "大棠路"},
              {"name_en": "Yuen Long", "name_zh": "元朗"}
            ]
          },
          {
            "route_number": "751",
            "description": "Tin Yat↔Yau Oi",
            "stations": [
              {"name_en": "Ho Tin", "name_zh": "河田"},
              {"name_en": "Choy Yee Bridge", "name_zh": "蔡意橋"},
              {"name_en": "Affluence", "name_zh": "澤豐"},
              {"name_en": "Tuen Mun Hospital", "name_zh": "屯門醫院"},
              {"name_en": "Siu Hong", "name_zh": "兆康"},
              {"name_en": "On Ting", "name_zh": "安定"},
              {"name_en": "Yau Oi", "name_zh": "友愛"},
              {"name_en": "Town Centre", "name_zh": "市中心"},
              {"name_en": "Tuen Mun", "name_zh": "屯門"},
              {"name_en": "Lam Tei", "name_zh": "藍地"},
              {"name_en": "Nai Wai", "name_zh": "泥圍"},
              {"name_en": "Chung Uk Tsuen", "name_zh": "鍾屋村"},
              {"name_en": "Hung Shui Kiu", "name_zh": "洪水橋"},
              {"name_en": "Hang Mei Tsuen", "name_zh": "坑尾村"},
              {"name_en": "Tin Shui Wai", "name_zh": "天水圍"},
              {"name_en": "Tin Tsz", "name_zh": "天慈"},
              {"name_en": "Tin Wu", "name_zh": "天湖"},
              {"name_en": "Ginza", "name_zh": "銀座"},
              {"name_en": "Chung Fu", "name_zh": "頌富"},
              {"name_en": "Tin Fu", "name_zh": "天富"},
              {"name_en": "Chestwood", "name_zh": "翠湖"},
              {"name_en": "Tin Wing", "name_zh": "天榮"},
              {"name_en": "Tin Yat", "name_zh": "天逸"}
            ]
          },
          {
            "route_number": "761P",
            "description": "Tin Yat↔Yuen Long",
            "stations": [
              {"name_en": "Tong Fong Tsuen", "name_zh": "塘坊村"},
              {"name_en": "Ping Shan", "name_zh": "屏山"},
              {"name_en": "Hang Mei Tsuen", "name_zh": "坑尾村"},
              {"name_en": "Tin Yiu", "name_zh": "天耀"},
              {"name_en": "Locwood", "name_zh": "樂湖"},
              {"name_en": "Tin Shui", "name_zh": "天瑞"},
              {"name_en": "Chung Fu", "name_zh": "頌富"},
              {"name_en": "Tin Fu", "name_zh": "天富"},
              {"name_en": "Tin Yat", "name_zh": "天逸"},
              {"name_en": "Shui Pin Wai", "name_zh": "水邊圍"},
              {"name_en": "Fung Nin Road", "name_zh": "豐年路"},
              {"name_en": "Hong Lok Road", "name_zh": "康樂路"},
              {"name_en": "Tai Tong Road", "name_zh": "大棠路"},
              {"name_en": "Yuen Long", "name_zh": "元朗"}
            ]
          }
        ]
      }
    ]
  }
}
''';

/* ------------------------- Error View ------------------------- */

class _ErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function()? onRetry;
  final bool isOffline;
  const _ErrorView({required this.error, required this.onRetry, this.isOffline = false});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<AccessibilityProvider>(
              builder: (context, accessibility, _) => AnimatedSwitcher(
                duration: MotionConstants.contentTransition,
                child: Icon(
                  isOffline ? Icons.wifi_off : Icons.error_outline, 
                  size: 48 * accessibility.iconScale, 
                  color: Colors.grey,
                  key: ValueKey(isOffline),
                ),
              ),
            ),
                            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: MotionConstants.contentTransition,
              curve: MotionConstants.standardEasing,
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withValues(alpha: 0.87)
                    : null,
                fontWeight: FontWeight.w600,
              ),
              child: Text(isOffline ? lang.offline : lang.networkError),
            ),
            const SizedBox(height: 8),
            Text(
              error, 
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withValues(alpha: 0.70)
                    : null,
              ),
            ),
                            const SizedBox(height: 8),
            if (onRetry != null)
              Consumer<AccessibilityProvider>(
                builder: (context, accessibility, _) => AnimatedScale(
                  scale: 1.0,
                  duration: MotionConstants.contentTransition,
                  curve: MotionConstants.standardEasing,
                  child: FilledButton.icon(
                    onPressed: onRetry, 
                    icon: Icon(Icons.refresh, size: 20 * accessibility.iconScale), 
                    label: Text(lang.retry)
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ========================= Enhanced Station Selection ========================= */

class StationGroup {
  final String name;
  final String nameEn;
  final List<StationInfo> stations;
  
  StationGroup({required this.name, required this.nameEn, required this.stations});
}

class StationInfo {
  final int id;
  final String nameEn;
  final String nameZh;
  final String group;
  final String groupEn;
  
  StationInfo({
    required this.id,
    required this.nameEn,
    required this.nameZh,
    required this.group,
    required this.groupEn,
  });
  
  String displayName(bool isEnglish) => isEnglish ? nameEn : nameZh;
  String groupName(bool isEnglish) => isEnglish ? groupEn : group;
}

class EnhancedStationSelector extends StatefulWidget {
  final StationProvider stationProvider;
  final Function(int) onStationSelected;
  final bool isEnglish;
  
  const EnhancedStationSelector({
    super.key,
    required this.stationProvider,
    required this.onStationSelected,
    required this.isEnglish,
  });

  @override
  State<EnhancedStationSelector> createState() => _EnhancedStationSelectorState();
}
class _EnhancedStationSelectorState extends State<EnhancedStationSelector> 
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<StationGroup> _allGroups = [];
  List<StationGroup> _filteredGroups = [];
  List<StationInfo> _recentStations = [];
  bool _isSearching = false;
  
  // 優化的動畫控制器
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeStations();
    _loadRecentStations();
    _searchController.addListener(_onSearchChanged);
    
    // 啟動進入動畫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }
  
  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.standardEasing,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.emphasizedEasing,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.deceleratedEasing,
    ));
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  void _initializeStations() {
    // 將車站按地區分組
    final stationMap = <String, List<StationInfo>>{};
    
    for (final entry in widget.stationProvider.stations.entries) {
      final station = StationInfo(
        id: entry.key,
        nameEn: entry.value['en']!,
        nameZh: entry.value['zh']!,
        group: _getStationGroup(entry.key),
        groupEn: _getStationGroupEn(entry.key),
      );
      
      final groupKey = widget.isEnglish ? station.groupEn : station.group;
      stationMap.putIfAbsent(groupKey, () => []).add(station);
    }
    
    _allGroups = stationMap.entries.map((entry) {
      final stations = entry.value..sort((a, b) => a.displayName(widget.isEnglish).compareTo(b.displayName(widget.isEnglish)));
      return StationGroup(
        name: entry.key,
        nameEn: entry.value.first.groupEn,
        stations: stations,
      );
    }).toList()..sort((a, b) => (widget.isEnglish ? a.nameEn : a.name).compareTo(widget.isEnglish ? b.nameEn : b.name));
    
    _filteredGroups = List.from(_allGroups);
  }
  
  

  
  Future<void> _loadRecentStations() async {
    final prefs = await SharedPreferences.getInstance();
    final recentIds = prefs.getStringList('recent_stations') ?? [];
    
    _recentStations = recentIds
        .map((id) => int.tryParse(id))
        .where((id) => id != null && widget.stationProvider.stations.containsKey(id))
        .map((id) {
          final station = widget.stationProvider.stations[id]!;
          return StationInfo(
            id: id!,
            nameEn: station['en']!,
            nameZh: station['zh']!,
            group: _getStationGroup(id),
            groupEn: _getStationGroupEn(id),
          );
        })
        .toList();
  }
  
  Future<void> _addToRecent(int stationId) async {
    final prefs = await SharedPreferences.getInstance();
    final recentIds = prefs.getStringList('recent_stations') ?? [];
    
    // 移除已存在的ID
    recentIds.remove(stationId.toString());
    // 添加到開頭
    recentIds.insert(0, stationId.toString());
    // 只保留最近3個
    if (recentIds.length > 3) {
      recentIds.removeRange(3, recentIds.length);
    }
    
    await prefs.setStringList('recent_stations', recentIds);
    await _loadRecentStations();
  }
  
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _isSearching = query.isNotEmpty;
      
      if (query.isEmpty) {
        _filteredGroups = List.from(_allGroups);
      } else {
        _filteredGroups = _allGroups.map((group) {
          final filteredStations = group.stations.where((station) {
            final nameEn = station.nameEn.toLowerCase();
            final nameZh = station.nameZh.toLowerCase();
            return nameEn.contains(query) || nameZh.contains(query);
          }).toList();
          
          return StationGroup(
            name: group.name,
            nameEn: group.nameEn,
            stations: filteredStations,
          );
        }).where((group) => group.stations.isNotEmpty).toList();
      }
    });
  }
  
  void _selectStation(StationInfo station) {
    widget.onStationSelected(station.id);
    _addToRecent(station.id);
    Navigator.of(context).pop();
  }
  
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final accessibility = context.watch<AccessibilityProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(lang.selectStation),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: widget.isEnglish ? 'Search stations...' : '搜尋車站...',
                prefixIcon: Icon(Icons.search, size: 20 * accessibility.iconScale),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 20 * accessibility.iconScale),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 最近使用的車站 - 使用 RepaintBoundary 優化
          if (_recentStations.isNotEmpty && !_isSearching)
            RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 20 * accessibility.iconScale,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isEnglish ? 'Recent Stations' : '最近使用',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                            const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _recentStations.asMap().entries.map((entry) {
                        final index = entry.key;
                        final station = entry.value;
                        return RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              final delay = index * 0.1; // 錯開動畫時間
                              final animationValue = (_animationController.value - delay).clamp(0.0, 1.0);
                              
                              return Transform.scale(
                                scale: CurvedAnimation(
                                  parent: AlwaysStoppedAnimation(animationValue),
                                  curve: MotionConstants.deceleratedEasing,
                                ).value,
                                child: Opacity(
                                  opacity: CurvedAnimation(
                                    parent: AlwaysStoppedAnimation(animationValue),
                                    curve: MotionConstants.standardEasing,
                                  ).value,
                                  child: ActionChip(
                                    avatar: Icon(
                                      Icons.tram,
                                      size: 16 * accessibility.iconScale,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    label: Text(
                                      station.displayName(widget.isEnglish),
                                      style: TextStyle(fontSize: 14 * accessibility.textScale),
                                    ),
                                    onPressed: () => _selectStation(station),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          
          // 車站列表 - 使用 AnimatedBuilder 優化動畫
          Expanded(
            child: _filteredGroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64 * accessibility.iconScale,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.isEnglish ? 'No stations found' : '找不到車站',
                          style: TextStyle(
                            fontSize: 18 * accessibility.textScale,
                            color: AppColors.getPrimaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return SlideTransition(
                        position: _slideAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: _buildOptimizedStationList(),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  // 優化的車站列表構建方法
  Widget _buildOptimizedStationList() {
    return ListView.builder(
      itemCount: _filteredGroups.length,
      itemBuilder: (context, groupIndex) {
        final group = _filteredGroups[groupIndex];
        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final groupDelay = groupIndex * 0.05; // 分組錯開動畫
              final groupAnimationValue = (_animationController.value - groupDelay).clamp(0.0, 1.0);
              
              return Transform.translate(
                offset: Offset(
                  0,
                  20 * (1 - CurvedAnimation(
                    parent: AlwaysStoppedAnimation(groupAnimationValue),
                    curve: MotionConstants.emphasizedEasing,
                  ).value),
                ),
                child: Opacity(
                  opacity: CurvedAnimation(
                    parent: AlwaysStoppedAnimation(groupAnimationValue),
                    curve: MotionConstants.standardEasing,
                  ).value,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 分組標題
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Text(
                          group.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      // 車站列表
                      ...group.stations.asMap().entries.map((entry) {
                        final stationIndex = entry.key;
                        final station = entry.value;
                        final isSelected = station.id == widget.stationProvider.selectedStationId;
                        final stationDelay = groupDelay + stationIndex * 0.03; // 車站錯開動畫
                        final stationAnimationValue = (_animationController.value - stationDelay).clamp(0.0, 1.0);
                        
                        return RepaintBoundary(
                          child: Transform.translate(
                            offset: Offset(
                              20 * (1 - CurvedAnimation(
                                parent: AlwaysStoppedAnimation(stationAnimationValue),
                                curve: MotionConstants.deceleratedEasing,
                              ).value),
                              0,
                            ),
                            child: Opacity(
                              opacity: CurvedAnimation(
                                parent: AlwaysStoppedAnimation(stationAnimationValue),
                                curve: MotionConstants.standardEasing,
                              ).value,
                              child: _buildOptimizedStationTile(station, isSelected),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
  
  // 優化的車站圖塊構建方法
  Widget _buildOptimizedStationTile(StationInfo station, bool isSelected) {
    final accessibility = context.watch<AccessibilityProvider>();
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: MotionConstants.standardEasing,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              '${station.id}',
              style: TextStyle(
                fontSize: 14 * accessibility.textScale,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        title: Text(
          station.displayName(widget.isEnglish),
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 16 * accessibility.textScale,
          ),
        ),
        subtitle: Text(
          station.groupName(widget.isEnglish),
          style: TextStyle(
            fontSize: 14 * accessibility.textScale,
            color: AppColors.getPrimaryTextColor(context),
          ),
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 24 * accessibility.iconScale,
              )
            : null,
        onTap: () => _selectStation(station),
      ),
    );
  }
}

/* ========================= Optimized Station Selector ========================= */

class _OptimizedStationSelector extends StatefulWidget {
  final StationProvider stationProvider;
  final ScheduleProvider scheduleProvider;
  final bool isEnglish;
  
  const _OptimizedStationSelector({
    required this.stationProvider,
    required this.scheduleProvider,
    required this.isEnglish,
  });

  @override
  State<_OptimizedStationSelector> createState() => _OptimizedStationSelectorState();
}
class _OptimizedStationSelectorState extends State<_OptimizedStationSelector> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<StationInfo> _filteredStations = [];
  bool _isSearching = false;
  int? _pressedStationId;
  bool _showSearch = false;
  Map<String, List<StationInfo>> _stationsByDistrict = {};
  List<String> _districtNames = [];
  String _selectedDistrict = '';
  List<StationInfo> _recentStations = [];
  // 側邊索引相關
  bool _isDraggingIndex = false;
  String? _activeIndexLabel;
  bool _showIndexHint = false;
  // 僅針對主選擇器與搜尋按鈕的按壓動畫狀態（不影響車站/地區標籤）
  bool _mainButtonPressed = false;
  bool _searchButtonPressed = false;
  
  // 性能優化：緩存計算結果
  List<StationInfo>? _cachedStations;
  Map<String, List<StationInfo>>? _cachedStationsByDistrict;
  
  // 地區緩存相關
  static const String _selectedDistrictKey = 'selected_station_district';
  static const String _selectedDistrictEnKey = 'selected_station_district_en';
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _initializeStations();
    _loadRecentStations();
    _loadSelectedDistrict();
    _searchController.addListener(_onSearchChanged);
    // 首次使用顯示側邊索引提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowIndexHint();
    });
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(_OptimizedStationSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 當語言改變時，重新初始化地區分組
    if (oldWidget.isEnglish != widget.isEnglish) {
      _selectedDistrict = ''; // 重置選中的地區
      _initializeStations();
      // 重新載入緩存的地區選擇（可能因語言改變而不同）
      _loadSelectedDistrict();
    }
  }
  
  void _initializeStations() {
    // 使用緩存避免重複計算，但需要考慮語言變化
    if (_cachedStations != null && _cachedStationsByDistrict != null) {
      _filteredStations = List.from(_cachedStations!);
      
      // 重新計算地區分組，因為語言可能已改變
      _stationsByDistrict.clear();
      for (final station in _cachedStations!) {
        final district = widget.isEnglish ? station.groupEn : station.group;
        _stationsByDistrict.putIfAbsent(district, () => []).add(station);
      }
      
      _districtNames = _stationsByDistrict.keys.toList()..sort();
      if (_districtNames.isNotEmpty && _selectedDistrict.isEmpty) {
        _selectedDistrict = _districtNames.first;
      }
      // 載入緩存的地區選擇
      _loadSelectedDistrict();
      return;
    }
    
    final stations = widget.stationProvider.stations.entries.map((entry) {
      return StationInfo(
        id: entry.key,
        nameEn: entry.value['en']!,
        nameZh: entry.value['zh']!,
        group: _getStationGroup(entry.key),
        groupEn: _getStationGroupEn(entry.key),
      );
    }).toList();
    
    stations.sort((a, b) => a.displayName(widget.isEnglish).compareTo(b.displayName(widget.isEnglish)));
    
    // 緩存結果
    _cachedStations = List.from(stations);
    _filteredStations = List.from(stations);
    
    // 按地區分組車站
    final stationsByDistrict = <String, List<StationInfo>>{};
    for (final station in stations) {
      final district = widget.isEnglish ? station.groupEn : station.group;
      stationsByDistrict.putIfAbsent(district, () => []).add(station);
    }
    
    // 緩存分組結果
    _cachedStationsByDistrict = stationsByDistrict;
    _stationsByDistrict = Map.from(stationsByDistrict);
    
    // 獲取地區名稱列表並排序
    _districtNames = _stationsByDistrict.keys.toList();
    _districtNames.sort();
    
    // 設置默認選中的地區
    if (_districtNames.isNotEmpty && _selectedDistrict.isEmpty) {
      _selectedDistrict = _districtNames.first;
    }
    
    // 載入緩存的地區選擇
    _loadSelectedDistrict();
  }
  

  Future<void> _maybeShowIndexHint() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('side_index_hint_shown') ?? false;
    if (!shown && mounted) {
      setState(() { _showIndexHint = true; });
      Future.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;
        setState(() { _showIndexHint = false; });
        await prefs.setBool('side_index_hint_shown', true);
      });
    }
  }

  List<String> _buildIndexLabels() {
    if (_districtNames.isEmpty) return [];
    // 以地區名稱首字作為索引，去重後排序（維持原順序）
    final seen = <String>{};
    final labels = <String>[];
    for (final name in _districtNames) {
      if (name.isEmpty) continue;
      final first = name.characters.first.toUpperCase();
      if (seen.add(first)) labels.add(first);
    }
    return labels;
  }

  String _labelForDistrict(String district) {
    if (district.isEmpty) return '';
    return district.characters.first.toUpperCase();
  }

  void _jumpToDistrictByLabel(String label) {
    if (_districtNames.isEmpty) return;
    // 找到第一個符合該首字的分區
    final target = _districtNames.firstWhere(
      (d) => _labelForDistrict(d) == label,
      orElse: () => _districtNames.first,
    );
    if (target != _selectedDistrict) {
      setState(() { _selectedDistrict = target; });
      _saveSelectedDistrict(target);
    }
  }

  void _handleIndexGesture(Offset localPosition, double height) {
    final labels = _buildIndexLabels();
    if (labels.isEmpty || height <= 0) return;
    final itemHeight = height / labels.length;
    final int idx = (localPosition.dy ~/ itemHeight).clamp(0, labels.length - 1);
    final label = labels[idx];
    if (_activeIndexLabel != label) {
      setState(() { _activeIndexLabel = label; });
      HapticFeedback.selectionClick();
      _jumpToDistrictByLabel(label);
    }
  }

  Widget _buildSideIndexBar(BuildContext context) {
    final labels = _buildIndexLabels();
    if (labels.length <= 1) return const SizedBox.shrink();
    final accessibility = context.watch<AccessibilityProvider>();
    return Positioned(
      right: 4,
      top: 0,
      bottom: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barHeight = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) { setState(() { _isDraggingIndex = true; }); },
            onVerticalDragUpdate: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final local = box.globalToLocal(details.globalPosition);
                _handleIndexGesture(local, barHeight);
              }
            },
            onVerticalDragEnd: (_) { setState(() { _isDraggingIndex = false; _activeIndexLabel = null; }); },
            onVerticalDragCancel: () { setState(() { _isDraggingIndex = false; _activeIndexLabel = null; }); },
            onTapDown: (details) {
              setState(() { _isDraggingIndex = true; });
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final local = box.globalToLocal(details.globalPosition);
                _handleIndexGesture(local, barHeight);
              }
            },
            onTapUp: (_) { setState(() { _isDraggingIndex = false; _activeIndexLabel = null; }); },
            child: Container(
              width: 24,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  width: UIConstants.borderWidthThin,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: labels.map((l) {
                  final isActive = _activeIndexLabel == l || _labelForDistrict(_selectedDistrict) == l;
                  return Expanded(
                    child: Center(
                      child: Text(
                        l,
                        style: TextStyle(
                          fontSize: 10 * accessibility.textScale,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.getPrimaryTextColor(context),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIndexBubble(BuildContext context) {
    if (!_isDraggingIndex || _activeIndexLabel == null) return const SizedBox.shrink();
    final accessibility = context.watch<AccessibilityProvider>();
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            _activeIndexLabel!,
            style: TextStyle(
              fontSize: 28 * accessibility.textScale,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIndexHint(BuildContext context) {
    if (!_showIndexHint || _isSearching) return const SizedBox.shrink();
    final accessibility = context.watch<AccessibilityProvider>();
    final isEnglish = widget.isEnglish;
    return Positioned(
      right: 32,
      bottom: 24,
      child: AnimatedOpacity(
        opacity: _showIndexHint ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              width: UIConstants.borderWidthThin,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swipe, size: 14 * accessibility.iconScale, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                isEnglish ? 'Swipe index to jump' : '側邊滑動快速定位',
                style: TextStyle(fontSize: 12 * accessibility.textScale),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
  
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _isSearching = query.isNotEmpty;
      
      if (query.isEmpty) {
        // 重置為所有車站
        if (_cachedStations != null) {
          _filteredStations = List.from(_cachedStations!);
        } else {
          _initializeStations();
        }
      } else {
        // 使用優化的搜索方法，支持模糊搜索
        final searchResults = widget.stationProvider.searchStations(query);
        _filteredStations = searchResults
            .map((data) => StationInfo(
              id: data.id,
              nameEn: data.nameEn,
              nameZh: data.nameZh,
              group: _getStationGroup(data.id),
              groupEn: _getStationGroupEn(data.id),
            ))
            .toList();
      }
    });
  }
  
  Future<void> _loadRecentStations() async {
    final prefs = await SharedPreferences.getInstance();
    final recentIds = prefs.getStringList('recent_stations') ?? [];
    
    _recentStations = recentIds
        .map((id) => int.tryParse(id))
        .where((id) => id != null && widget.stationProvider.stations.containsKey(id))
        .map((id) {
          final station = widget.stationProvider.stations[id]!;
          return StationInfo(
            id: id!,
            nameEn: station['en']!,
            nameZh: station['zh']!,
            group: _getStationGroup(id),
            groupEn: _getStationGroupEn(id),
          );
        })
        .toList();
  }
  
  Future<void> _addToRecent(int stationId) async {
    final prefs = await SharedPreferences.getInstance();
    final recentIds = prefs.getStringList('recent_stations') ?? [];
    
    // 移除已存在的ID
    recentIds.remove(stationId.toString());
    // 添加到開頭
    recentIds.insert(0, stationId.toString());
    // 只保留最近3個
    if (recentIds.length > 3) {
      recentIds.removeRange(3, recentIds.length);
    }
    
    await prefs.setStringList('recent_stations', recentIds);
    await _loadRecentStations();
  }
  
  Future<void> _loadSelectedDistrict() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedDistrict = widget.isEnglish 
        ? prefs.getString(_selectedDistrictEnKey)
        : prefs.getString(_selectedDistrictKey);
    
    if (cachedDistrict != null && _districtNames.contains(cachedDistrict)) {
      setState(() {
        _selectedDistrict = cachedDistrict;
      });
    }
  }
  
  Future<void> _saveSelectedDistrict(String district) async {
    final prefs = await SharedPreferences.getInstance();
    if (widget.isEnglish) {
      await prefs.setString(_selectedDistrictEnKey, district);
    } else {
      await prefs.setString(_selectedDistrictKey, district);
    }
  }
  
  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
        // 移除自動聚焦，讓用戶手動點擊搜索框才彈出鍵盤
      } else {
        _animationController.reverse();
        _searchController.clear();
        _searchFocusNode.unfocus();
        _showSearch = false;
      }
    });
  }

  // 直接展開並聚焦到搜尋欄
  void _expandAndFocusSearch() {
    setState(() {
      if (!_isExpanded) {
        _isExpanded = true;
        _animationController.forward();
      }
      _showSearch = true;
    });
    // 等 UI 展開後再聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }
  
  Future<void> _selectStation(StationInfo station) async {
    debugPrint('=== _selectStation called for station ${station.id} ===');
    
    try {
      // 設置選中的車站
      await widget.stationProvider.setStation(station.id);
      
      // 添加到最近車站
      await _addToRecent(station.id);
      
      // 獲取連線狀態
      final connectivity = context.read<ConnectivityProvider>();
      debugPrint('Connectivity isOnline: ${connectivity.isOnline}');
      
      // 如果線上，載入班次資料並開始自動刷新
      if (connectivity.isOnline) {
        debugPrint('Loading data and starting auto-refresh for station ${station.id}');
        await widget.scheduleProvider.load(station.id);
        widget.scheduleProvider.startAutoRefresh(station.id);
      } else {
        debugPrint('Offline, skipping auto-refresh');
      }
      
      // 檢查 widget 是否仍然掛載
      if (mounted) {
        _toggleExpanded();
      }
    } catch (e) {
      debugPrint('Error selecting station: $e');
      // 顯示錯誤訊息給用戶
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('選擇車站時發生錯誤：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
  
  // 模組化組件：主選擇器按鈕
  Widget _buildMainSelectorButton({
    required BuildContext context,
    required LanguageProvider lang,
    required AccessibilityProvider accessibility,
    required String selectedStationName,
    required bool isLandscape,
  }) {
    return Material(
      color: Colors.transparent,
      child: AnimatedScale(
        scale: _mainButtonPressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: MotionConstants.standardEasing,
        child: InkWell(
          onTap: _toggleExpanded,
          onHighlightChanged: (pressed) {
            setState(() => _mainButtonPressed = pressed);
          },
          borderRadius: BorderRadius.circular(12),
          child: Ink(
          padding: EdgeInsets.all(isLandscape ? 6 : 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.8),
              width: UIConstants.borderWidth,
            ),
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            children: [
              Container(
                width: isLandscape ? 40 : 48,
                height: isLandscape ? 40 : 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(isLandscape ? 20 : 24),
                ),
                child: Center(
                  child: Icon(
                    Icons.tram,
                    size: (isLandscape ? 20 : 24) * accessibility.iconScale,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              SizedBox(width: isLandscape ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.selectStation,
                      style: TextStyle(
                        fontSize: (isLandscape ? 10 : 12) * accessibility.textScale,
                        color: AppColors.getPrimaryTextColor(context),
                      ),
                    ),
                    SizedBox(height: isLandscape ? 2 : 4),
                    Text(
                      selectedStationName,
                      style: TextStyle(
                        fontSize: (isLandscape ? 14 : 16) * accessibility.textScale,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              // 直接搜尋按鈕
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: lang.searchStations,
                  child: AnimatedScale(
                    scale: _searchButtonPressed ? 0.9 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: MotionConstants.standardEasing,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _expandAndFocusSearch,
                      onHighlightChanged: (pressed) {
                        setState(() => _searchButtonPressed = pressed);
                      },
                      child: Ink(
                        decoration: const ShapeDecoration(shape: CircleBorder()),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.search,
                            size: (isLandscape ? 18 : 20) * accessibility.iconScale,
                            color: AppColors.getPrimaryTextColor(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: (isLandscape ? 20 : 24) * accessibility.iconScale,
                  color: AppColors.getPrimaryTextColor(context),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
  
  // 模組化組件：搜索框（包含最近車站）
  Widget _buildSearchField({
    required BuildContext context,
    required LanguageProvider lang,
    required AccessibilityProvider accessibility,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: UIConstants.borderWidthThin,
        ),
      ),
      child: Row(
        children: [
          // 搜索輸入框（減少寬度）
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: lang.searchStations,
                prefixIcon: Icon(Icons.search, size: 20 * accessibility.iconScale),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 20 * accessibility.iconScale),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                    width: UIConstants.borderWidthThin,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          
          // 最近車站區域（只在非搜索狀態下顯示）
          if (_recentStations.isNotEmpty && !_isSearching) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 12 * accessibility.iconScale,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.isEnglish ? 'Recent' : '最近',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 10 * accessibility.textScale,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: () {
                          final width = MediaQuery.of(context).size.width;
                          final int maxChips = width < 360 ? 2 : (width < 520 ? 3 : 4);
                          final items = _recentStations.take(maxChips).toList();
                          return items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final station = entry.value;
                          return AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              final delay = index * 0.1;
                              final animationValue = (_animationController.value - delay).clamp(0.0, 1.0);
                              
                              return Transform.scale(
                                scale: CurvedAnimation(
                                  parent: AlwaysStoppedAnimation(animationValue),
                                  curve: Curves.easeOut,
                                ).value,
                                child: Opacity(
                                  opacity: CurvedAnimation(
                                    parent: AlwaysStoppedAnimation(animationValue),
                                    curve: Curves.easeOut,
                                  ).value,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: ActionChip(
                                      avatar: Icon(
                                        Icons.tram,
                                        size: 10 * accessibility.iconScale,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                      label: Text(
                                        station.displayName(widget.isEnglish),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: TextStyle(fontSize: 9.5 * accessibility.textScale),
                                      ),
                                      onPressed: () => _selectStation(station),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                          }).toList();
                        }(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  
  // 模組化組件：地區選擇器
  Widget _buildDistrictSelector({
    required BuildContext context,
    required AccessibilityProvider accessibility,
  }) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _districtNames.length,
        itemBuilder: (context, index) {
          final district = _districtNames[index];
          final isSelected = district == _selectedDistrict;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                district,
                style: TextStyle(
                  fontSize: 12 * accessibility.textScale,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedDistrict = district;
                  });
                  _saveSelectedDistrict(district);
                }
              },
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              checkmarkColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
              side: BorderSide(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                width: UIConstants.borderWidthThin,
              ),
            ),
          );
        },
      ),
    );
  }
  
  
  // 模組化組件：橫向佈局
  Widget _buildLandscapeLayout({
    required BuildContext context,
    required LanguageProvider lang,
    required AccessibilityProvider accessibility,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        
        // 車站列表
        Expanded(
          flex: 1,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                width: UIConstants.borderWidth,
              ),
            ),
            child: AnimatedSwitcher(
              duration: MotionConstants.contentTransition,
              switchInCurve: MotionConstants.standardEasing,
              child: _isSearching
                  ? KeyedSubtree(
                      key: const ValueKey('searchGrid'),
                      child: _buildSearchResults(accessibility),
                    )
                  : KeyedSubtree(
                      key: ValueKey('districtGrid_$_selectedDistrict'),
                      child: _buildDistrictGrid(accessibility),
                    ),
            ),
          ),
        ),
      ],
    );
  }
  
  // 模組化組件：直向佈局
  Widget _buildPortraitLayout({
    required BuildContext context,
    required LanguageProvider lang,
    required AccessibilityProvider accessibility,
  }) {
    return Column(
      children: [
        const SizedBox(height: 3),
        
        
        // 車站列表
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: UIConstants.borderWidth,
            ),
          ),
          child: AnimatedSwitcher(
            duration: MotionConstants.contentTransition,
            switchInCurve: MotionConstants.standardEasing,
            child: _isSearching
                ? KeyedSubtree(
                    key: const ValueKey('searchGrid'),
                    child: _buildSearchResults(accessibility),
                  )
                : KeyedSubtree(
                    key: ValueKey('districtGrid_$_selectedDistrict'),
                    child: _buildDistrictGrid(accessibility),
                  ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSearchResults(AccessibilityProvider accessibility) {
    final lang = context.watch<LanguageProvider>();
    
    if (_filteredStations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 32 * accessibility.iconScale,
                color: AppColors.getPrimaryTextColor(context),
              ),
              const SizedBox(height: 8),
              Text(
                lang.noStationsFound,
                style: TextStyle(
                  fontSize: 14 * accessibility.textScale,
                  color: AppColors.getPrimaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive grid based on available width
        int crossAxisCount = 2; // Default for narrow screens
        double aspectRatio = 1.3;
        double crossAxisSpacing = 6;
        double mainAxisSpacing = 6;
        
        // Responsive adjustments based on screen width
        if (constraints.maxWidth > 600) {
          crossAxisCount = 3; // 3 columns for medium screens
          aspectRatio = 1.4;
        }
        if (constraints.maxWidth > 900) {
          crossAxisCount = 4; // 4 columns for large screens
          aspectRatio = 1.5;
          crossAxisSpacing = 8;
          mainAxisSpacing = 8;
        }
        if (constraints.maxWidth > 1200) {
          crossAxisCount = 5; // 5 columns for extra large screens
          aspectRatio = 1.6;
          crossAxisSpacing = 10;
          mainAxisSpacing = 10;
        }
        
        // Calculate estimated rows based on item count and columns
        final estimatedRows = (_filteredStations.length / crossAxisCount).ceil();
        final gridWidth = constraints.maxWidth - 16; // Accounting for padding
        
        // Display grid with adaptive columns
        return Stack(
          children: [
            // Grid view
            GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
              ),
              itemCount: _filteredStations.length,
              itemBuilder: (context, index) {
                final station = _filteredStations[index];
                final isSelected = station.id == widget.stationProvider.selectedStationId;
                
                return _buildStationCard(station, isSelected, accessibility);
              },
            ),
            
            // Grid size debug label
            Positioned(
              top: 8,
              right: 8,
              child: Consumer<DeveloperSettingsProvider>(
                builder: (context, devSettings, _) {
                  // Only show grid info if the setting is enabled
                  if (!devSettings.showGridDebug) return const SizedBox.shrink();
                  
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${crossAxisCount}x$estimatedRows | W:${gridWidth.toInt()}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12 * accessibility.textScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildDistrictGrid(AccessibilityProvider accessibility) {
    final stations = _stationsByDistrict[_selectedDistrict] ?? [];
    
    if (stations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No stations in $_selectedDistrict',
            style: TextStyle(
              fontSize: 14 * accessibility.textScale,
              color: AppColors.getPrimaryTextColor(context),
            ),
          ),
        ),
      );
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive grid based on available width
        int crossAxisCount = 3; // Default for narrow screens
        double aspectRatio = 1.2;
        double crossAxisSpacing = 4;
        double mainAxisSpacing = 4;
        
        // Responsive adjustments based on screen width
        if (constraints.maxWidth > 600) {
          crossAxisCount = 4; // 4 columns for medium screens
          aspectRatio = 1.3;
        }
        if (constraints.maxWidth > 900) {
          crossAxisCount = 5; // 5 columns for large screens
          aspectRatio = 1.4;
          crossAxisSpacing = 6;
          mainAxisSpacing = 6;
        }
        if (constraints.maxWidth > 1200) {
          crossAxisCount = 6; // 6 columns for extra large screens
          aspectRatio = 1.5;
          crossAxisSpacing = 8;
          mainAxisSpacing = 8;
        }
        
        // Calculate estimated rows based on item count and columns
        final estimatedRows = (stations.length / crossAxisCount).ceil();
        final gridWidth = constraints.maxWidth - 16; // Accounting for padding
        
        return Stack(
          children: [
            // Grid view
            GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
              ),
              itemCount: stations.length,
              itemBuilder: (context, index) {
                final station = stations[index];
                final isSelected = station.id == widget.stationProvider.selectedStationId;
                
                return _buildStationCard(station, isSelected, accessibility);
              },
            ),
            
            // Grid size debug label
            Positioned(
              top: 8,
              right: 8,
              child: Consumer<DeveloperSettingsProvider>(
                builder: (context, devSettings, _) {
                  // Only show grid info if the setting is enabled
                  if (!devSettings.showGridDebug) return const SizedBox.shrink();
                  
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${crossAxisCount}x$estimatedRows | W:${gridWidth.toInt()}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12 * accessibility.textScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildStationCard(StationInfo station, bool isSelected, AccessibilityProvider accessibility) {
    return Consumer<DeveloperSettingsProvider>(
      builder: (context, devSettings, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectStation(station),
            onHighlightChanged: (v) {
              setState(() { _pressedStationId = v ? station.id : null; });
            },
            overlayColor: WidgetStateProperty.resolveWith((states) {
              final color = Theme.of(context).colorScheme.primary;
              if (states.contains(WidgetState.pressed)) return color.withValues(alpha: 0.10);
              if (states.contains(WidgetState.hovered)) return color.withValues(alpha: 0.06);
              if (states.contains(WidgetState.focused)) return color.withValues(alpha: 0.08);
              return null;
            }),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: (_pressedStationId == station.id) ? 0.98 : 1.0,
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isSelected 
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary 
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    if (_pressedStationId == station.id)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 車站ID圓形圖示（根據設定顯示或隱藏）
                      if (!devSettings.hideStationId) ...[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Theme.of(context).colorScheme.primary 
                                : Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (isSelected 
                                    ? Theme.of(context).colorScheme.primary 
                                    : Theme.of(context).colorScheme.primaryContainer).withValues(alpha: 0.3),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${station.id}',
                              style: TextStyle(
                                fontSize: 10 * accessibility.textScale,
                                fontWeight: FontWeight.bold,
                                color: isSelected 
                                    ? Theme.of(context).colorScheme.onPrimary 
                                    : Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      // 車站名稱（自適應縮放）
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            station.displayName(widget.isEnglish),
                            style: TextStyle(
                              fontSize: 12 * accessibility.textScale,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected 
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      // 車站群組名稱（自適應縮放）
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            station.groupName(widget.isEnglish),
                            style: TextStyle(
                              fontSize: 9 * accessibility.textScale,
                              fontWeight: FontWeight.w400,
                              color: AppColors.getPrimaryTextColor(context).withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      // 選中狀態指示器
                      if (isSelected) ...[
                        const SizedBox(height: 2),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
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
  
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final accessibility = context.watch<AccessibilityProvider>();
    final selectedStation = widget.stationProvider.stations[widget.stationProvider.selectedStationId];
    final selectedStationName = selectedStation != null 
        ? (widget.isEnglish ? selectedStation['en']! : selectedStation['zh']!)
        : lang.selectStation;
    
    // 檢測是否為橫向模式
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return AnimatedContainer(
      duration: MotionConstants.contentTransition,
      curve: MotionConstants.standardEasing,
      child: Column(
        children: [
          // 主選擇器按鈕 - 使用新的模組化組件
          _buildMainSelectorButton(
            context: context,
            lang: lang,
            accessibility: accessibility,
            selectedStationName: selectedStationName,
            isLandscape: isLandscape,
          ),
          
          // 展開的選擇器內容
          SizeTransition(
            sizeFactor: _animation,
            child: Stack(
              children: [
                Column(
                  children: [
                SizedBox(height: isLandscape ? 6 : 8),
                
                // 搜索框 - 僅在點擊搜尋按鈕後顯示
                AnimatedSwitcher(
                  duration: MotionConstants.contentTransition,
                  switchInCurve: MotionConstants.standardEasing,
                  child: _showSearch
                      ? _buildSearchField(
                          context: context,
                          lang: lang,
                          accessibility: accessibility,
                        )
                      : const SizedBox.shrink(),
                ),
                
                if (_showSearch) const SizedBox(height: 8),
                
                // 地區標籤頁選擇器 - 使用模組化組件
                if (!_isSearching && _districtNames.isNotEmpty)
                  _buildDistrictSelector(
                    context: context,
                    accessibility: accessibility,
                  ),
                
                const SizedBox(height: 8),
                
                // 響應式佈局：根據屏幕方向調整
                if (isLandscape)
                  _buildLandscapeLayout(
                    context: context,
                    lang: lang,
                    accessibility: accessibility,
                  )
                else
                  _buildPortraitLayout(
                    context: context,
                    lang: lang,
                    accessibility: accessibility,
                  ),
                  ],
                ),
                // 側邊索引條
                _buildSideIndexBar(context),
                // 拖動時中央浮標
                _buildIndexBubble(context),
                // 首次提示
                _buildIndexHint(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _getStationGroup(int stationId) {
    // --- Tin Shui Wai (精確分組) ---
    const tswNorth = {468, 480, 490, 500, 510, 520, 530, 540, 550}; // Chestwood..Tin Yat
    const tswAll = {
      430,435,445,448,450,455,460,490,500,510,520,530,540,550
    }; // All TSW IDs
    if (430 <= stationId && stationId <= 550) {
      if (tswNorth.contains(stationId)) return '天水圍北'; // North band
      if (tswAll.contains(stationId))   return '天水圍南'; // Remaining TSW
      return '天水圍區'; // Fallback
    }

    // --- Yuen Long (智能分組) ---
    const ylHungShuiKiu = {370, 380, 390}; // Chung Uk Tsuen, Hung Shui Kiu, Tong Fong Tsuen
    const ylPingShan    = {400, 425};      // Ping Shan, Hang Mei Tsuen
    const ylCentral     = {560, 570, 580, 590, 600}; // Shui Pin Wai → Yuen Long
    if (ylCentral.contains(stationId))     return '元朗市中心';   // Central spine
    if (ylPingShan.contains(stationId))    return '屏山段';       // Ping Shan Section
    if (ylHungShuiKiu.contains(stationId)) return '洪水橋段';     // HSK Section

    // --- Tuen Mun (重新分組 - 根據實際輕鐵路線) ---
    // 屯門碼頭區: 碼頭周邊及海翠路一帶
    const tmPier = {1,10,15,20,30,40,50,250,240,265,260,920}; // Ferry Pier area + Sam Shing
    // 屯門市中心: 屯門站周邊及市中心商業區
    const tmCent = {
      60,70,75,80,212,220,230,270,275,280,295,300,310,320,330,
    }; // Central corridor
    // 屯門北區: 兆康站以北的住宅區
    const tmNorth = {90,100,110,120,130,140,150,160,170,180,190,200,340,350,360}; // North estates
    if (tmPier.contains(stationId))   return '屯門碼頭(南)';
    if (tmCent.contains(stationId))   return '屯門中';
    if (tmNorth.contains(stationId))  return '屯門北';

    return '其他';
  }

  String _getStationGroupEn(int stationId) {
    // --- Tin Shui Wai (精確分組) ---
    const tswNorth = {468, 480, 490, 500, 510, 520, 530, 540, 550}; // Chestwood..Tin Yat
    const tswAll = {
      430,435,445,448,450,455,460,490,500,510,520,530,540,550
    }; // All TSW IDs
    if (430 <= stationId && stationId <= 550) {
      if (tswNorth.contains(stationId)) return 'Tin Shui Wai North'; // North band
      if (tswAll.contains(stationId))   return 'Tin Shui Wai South'; // Remaining TSW
      return 'Tin Shui Wai'; // Fallback
    }

    // --- Yuen Long (智能分組) ---
    const ylHungShuiKiu = {370, 380, 390}; // Chung Uk Tsuen, Hung Shui Kiu, Tong Fong Tsuen
    const ylPingShan    = {400, 425};      // Ping Shan, Hang Mei Tsuen
    const ylCentral     = {560, 570, 580, 590, 600}; // Shui Pin Wai → Yuen Long
    if (ylCentral.contains(stationId))     return 'Yuen Long Central';   // Central spine
    if (ylPingShan.contains(stationId))    return 'Ping Shan Section';       // Ping Shan Section
    if (ylHungShuiKiu.contains(stationId)) return 'Hung Shui Kiu Section';     // HSK Section

    // --- Tuen Mun (重新分組 - 根據實際輕鐵路線) ---
    // 屯門碼頭區: 碼頭周邊及海翠路一帶
    const tmPier = {1,10,15,20,30,40,50,250,240,265,260,920}; // Ferry Pier area + Sam Shing
    // 屯門市中心: 屯門站周邊及市中心商業區
    const tmCent = {
      60,70,75,80,212,220,230,270,275,280,295,300,310,320,330,
    }; // Central corridor
    // 屯門北區: 兆康站以北的住宅區
    const tmNorth = {90,100,110,120,130,140,150,160,170,180,190,200,340,350,360}; // North estates
    if (tmPier.contains(stationId))   return 'Tuen Mun Ferry Pier(South)';
    if (tmCent.contains(stationId))   return 'Tuen Mun Central';
    if (tmNorth.contains(stationId))  return 'Tuen Mun North';

    return 'Others';
  }
  
  
}

/* ========================= Simple Station Selector for Testing ========================= */

class SimpleStationSelector extends StatelessWidget {
  final StationProvider stationProvider;
  final Function(int) onStationSelected;
  final bool isEnglish;
  
  const SimpleStationSelector({
    super.key,
    required this.stationProvider,
    required this.onStationSelected,
    required this.isEnglish,
  });
  
  String _getStationGroup(int stationId) {
    // --- Tin Shui Wai (精確分組) ---
    const tswNorth = {490, 500, 510, 520, 530, 540, 550}; // Chestwood..Tin Yat
    const tswAll = {
      430, 435, 445, 448, 450, 455, 460, 468, 480, 490, 500, 510, 520, 530, 540, 550
    }; // All TSW IDs
    if (430 <= stationId && stationId <= 550) {
      if (tswNorth.contains(stationId)) return '天水圍北'; // North band
      if (tswAll.contains(stationId))   return '天水圍南'; // Remaining TSW
      return '天水圍區'; // Fallback
    }

    // --- Yuen Long (智能分組) ---
    const ylHungShuiKiu = {370, 380, 390}; // Chung Uk Tsuen, Hung Shui Kiu, Tong Fong Tsuen
    const ylPingShan    = {400, 425};       // Ping Shan, Hang Mei Tsuen
    const ylCentral     = {560, 570, 580, 590, 600}; // Shui Pin Wai → Yuen Long
    if (ylCentral.contains(stationId))     return '元朗市中心';   // Central spine
    if (ylPingShan.contains(stationId))    return '屏山段';       // Ping Shan Section
    if (ylHungShuiKiu.contains(stationId)) return '洪水橋段';     // HSK Section

    // --- Tuen Mun (重新分組 - 根據實際輕鐵路線) ---
    // 屯門碼頭區: 碼頭周邊及海翠路一帶
    const tmPier = {1, 10, 15, 20, 30, 40, 50, 920}; // Ferry Pier area + Sam Shing
    // 屯門市中心: 屯門站周邊及市中心商業區
    const tmCent = {
      60, 70, 75, 80, 90, 212, 220, 230, 240, 250, 260, 265, 270, 275, 280, 295, 300, 310, 320, 330, 340, 350, 360
    }; // Central corridor
    // 屯門北區: 兆康站以北的住宅區
    const tmNorth = {100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200}; // North estates
    if (tmPier.contains(stationId))   return '屯門碼頭區';
    if (tmCent.contains(stationId))   return '屯門市中心';
    if (tmNorth.contains(stationId))  return '屯門北區';

    return '其他';
    }

  String _getStationGroupEn(int stationId) {
    // --- Tin Shui Wai (精確分組) ---
    const tswNorth = {490, 500, 510, 520, 530, 540, 550}; // Chestwood..Tin Yat
    const tswAll = {
      430, 435, 445, 448, 450, 455, 460, 468, 480, 490, 500, 510, 520, 530, 540, 550
    }; // All TSW IDs
    if (430 <= stationId && stationId <= 550) {
      if (tswNorth.contains(stationId)) return 'Tin Shui Wai North'; // North band
      if (tswAll.contains(stationId))   return 'Tin Shui Wai South'; // Remaining TSW
      return 'Tin Shui Wai'; // Fallback
    }

    // --- Yuen Long (智能分組) ---
    const ylHungShuiKiu = {370, 380, 390}; // Chung Uk Tsuen, Hung Shui Kiu, Tong Fong Tsuen
    const ylPingShan    = {400, 425};       // Ping Shan, Hang Mei Tsuen
    const ylCentral     = {560, 570, 580, 590, 600}; // Shui Pin Wai → Yuen Long
    if (ylCentral.contains(stationId))     return 'Yuen Long Central';   // Central spine
    if (ylPingShan.contains(stationId))    return 'Ping Shan Section';   // Ping Shan Section
    if (ylHungShuiKiu.contains(stationId)) return 'Hung Shui Kiu Section'; // HSK Section

    // --- Tuen Mun (重新分組 - 根據實際輕鐵路線) ---
    // 屯門碼頭區: 碼頭周邊及海翠路一帶
    const tmPier = {1, 10, 15, 20, 30, 40, 50, 920}; // Ferry Pier area + Sam Shing
    // 屯門市中心: 屯門站周邊及市中心商業區
    const tmCent = {
      60, 70, 75, 80, 90, 212, 220, 230, 240, 250, 260, 265, 270, 275, 280, 295, 300, 310, 320, 330, 340, 350, 360
    }; // Central corridor
    // 屯門北區: 兆康站以北的住宅區
    const tmNorth = {100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200}; // North estates
    if (tmPier.contains(stationId))   return 'Tuen Mun Ferry Pier';
    if (tmCent.contains(stationId))   return 'Tuen Mun Central';
    if (tmNorth.contains(stationId))  return 'Tuen Mun North';

    return 'Others';
  }


  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    context.watch<AccessibilityProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(lang.selectStation),
      ),
      body: ListView.builder(
        itemCount: stationProvider.stations.length,
        itemBuilder: (context, index) {
          final entry = stationProvider.stations.entries.elementAt(index);
          final stationId = entry.key;
          final stationName = isEnglish ? entry.value['en']! : entry.value['zh']!;
          final isSelected = stationId == stationProvider.selectedStationId;
          
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected 
                  ? Theme.of(context).colorScheme.primary 
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                '$stationId',
                style: TextStyle(
                  color: isSelected 
                      ? Theme.of(context).colorScheme.onPrimary 
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              stationName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(isEnglish ? _getStationGroupEn(stationId) : _getStationGroup(stationId)),
            trailing: isSelected 
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : null,
            onTap: () {
              print('Simple selector: Station $stationId ($stationName) selected');
              onStationSelected(stationId);
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }
}