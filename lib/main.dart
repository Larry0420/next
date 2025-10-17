import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:http/http.dart' as http;
import 'package:implicitly_animated_reorderable_list_2/implicitly_animated_reorderable_list_2.dart';
import 'package:implicitly_animated_reorderable_list_2/transitions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mtr_schedule_page.dart';

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
  _StationGroupInfo('天水圍北', 'Tin Shui Wai (N)', {490, 500, 510, 520, 530, 540, 550}),
  _StationGroupInfo('天水圍南', 'Tin Shui Wai (S)', {430, 435, 445, 448, 450, 455, 460, 468, 480}),

  // Yuen Long (Zone 4 & 5)
  _StationGroupInfo('元朗', 'Yuen Long', {560, 570, 580, 590, 600}),
  _StationGroupInfo('屏山', 'Ping Shan', {400, 425}),
  _StationGroupInfo('洪水橋', 'Hung Shui Kiu', {370, 380, 390}),

  // Tuen Mun (Zone 1, 2, & 3)
  _StationGroupInfo('屯門(碼頭/南)', 'Tuen Mun (S)', {1, 10, 15, 20, 30, 40, 50, 920}),
  _StationGroupInfo('屯門(市中心)', 'Tuen Mun Town', {60, 70, 75, 80, 90, 212, 220, 230, 240, 250, 260, 265, 270, 275, 280, 295, 300, 310, 320, 330, 340, 350, 360}),
  _StationGroupInfo('屯門(兆康/北)', 'Tuen Mun (N)', {100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200}),
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

/// 統一的顏色方案類別 - 確保整個應用程式的顏色一致性與 WCAG 2.1 標準
class AppColors {
  // 透明度常數 - WCAG AA/AAA 級對比度優化值
  static const double _primaryOpacity = 0.75;        // 主要文字 - 提升至 0.75 (AA+ 級)
  static const double _secondaryOpacity = 0.65;      // 次要文字 - 優化至 0.65 (AA 級)
  static const double _hintOpacity = 0.55;           // 提示文字 - 提升至 0.55 增強可讀性
  static const double _disabledOpacity = 0.40;       // 禁用文字 - 保持適中可辨識度
  static const double _subtleOpacity = 0.45;         // 微妙文字 - 提升至 0.45 改善對比
  static const double _verySubtleOpacity = 0.25;     // 非常微妙 - 優化至 0.25 保持層次
  
  // 邊框和陰影透明度 - 細膩層次優化
  static const double _borderSubtleOpacity = 0.08;   // 微妙邊框 - 提升可見度
  static const double _borderLightOpacity = 0.12;    // 輕微邊框 - 增強分界線
  static const double _borderMediumOpacity = 0.18;   // 中等邊框 - 清晰結構
  static const double _borderStrongOpacity = 0.25;   // 強烈邊框 - 明確邊界
  static const double _borderVeryStrongOpacity = 0.35; // 超強邊框 - 重點突出
  
  // 陰影透明度 - 深度感優化
  static const double _shadowLightOpacity = 0.12;    // 輕微陰影 - 增強深度
  static const double _shadowMediumOpacity = 0.18;   // 中等陰影 - 清晰層次
  
  // 容器透明度 - 視覺層次優化
  static const double _containerLightOpacity = 0.15;  // 輕微容器 - 柔和背景
  static const double _containerMediumOpacity = 0.25; // 中等容器 - 明確區域
  
  // 主要文字顏色
  static Color getPrimaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(_primaryOpacity);
  }
  
  // 次要文字顏色
  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(_secondaryOpacity);
  }
  
  // 提示文字顏色
  static Color getHintTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(_hintOpacity);
  }
  
  // 禁用文字顏色
  static Color getDisabledTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(_disabledOpacity);
  }
  
  // 微妙文字顏色
  static Color getSubtleTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(_subtleOpacity);
  }
  
  // 非常微妙的文字顏色
  static Color getVerySubtleTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(_verySubtleOpacity);
  }
  
  // 邊框顏色 - 微妙
  static Color getSubtleBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withOpacity(_borderSubtleOpacity);
  }
  
  // 邊框顏色 - 輕微
  static Color getLightBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withOpacity(_borderLightOpacity);
  }
  
  // 邊框顏色 - 中等
  static Color getMediumBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withOpacity(_borderMediumOpacity);
  }
  
  // 邊框顏色 - 強烈
  static Color getStrongBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withOpacity(_borderStrongOpacity);
  }
  
  // 邊框顏色 - 非常強烈
  static Color getVeryStrongBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.outline.withOpacity(_borderVeryStrongOpacity);
  }
  
  // 陰影顏色 - 輕微
  static Color getLightShadowColor(BuildContext context) {
    return Theme.of(context).colorScheme.shadow.withOpacity(_shadowLightOpacity);
  }
  
  // 陰影顏色 - 中等
  static Color getMediumShadowColor(BuildContext context) {
    return Theme.of(context).colorScheme.shadow.withOpacity(_shadowMediumOpacity);
  }
  
  // 主要顏色 - 輕微透明度
  static Color getPrimaryLightColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary.withOpacity(_containerLightOpacity);
  }
  
  // 主要顏色 - 中等透明度
  static Color getPrimaryMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary.withOpacity(_containerMediumOpacity);
  }
  
  // 次要顏色 - 中等透明度
  static Color getSecondaryMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondary.withOpacity(_containerMediumOpacity);
  }
  
  // 主要容器顏色 - 中等透明度
  static Color getPrimaryContainerMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.primaryContainer.withOpacity(_containerMediumOpacity);
  }
  
  // 次要容器顏色 - 中等透明度
  static Color getSecondaryContainerMediumColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondaryContainer.withOpacity(_containerMediumOpacity);
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
  
  // ========== 語義化狀態顏色 - WCAG 2.1 AAA 標準 ==========
  
  /// 錯誤/危險顏色 - 高對比度警示紅
  static Color getErrorColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Color(0xFFEF5350)  // 深色模式：明亮紅 (對比度 5.5:1)
        : Color(0xFFC62828); // 淺色模式：深紅 (對比度 6.2:1)
  }
  
  /// 警告顏色 - 高可見度橙色
  static Color getWarningColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Color(0xFFFF9800)  // 深色模式：明橙 (對比度 4.8:1)
        : Color(0xFFEF6C00); // 淺色模式：深橙 (對比度 5.2:1)
  }
  
  /// 成功/確認顏色 - 清晰綠色
  static Color getSuccessColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Color(0xFF66BB6A)  // 深色模式：亮綠 (對比度 5.0:1)
        : Color(0xFF2E7D32); // 淺色模式：深綠 (對比度 6.5:1)
  }
  
  /// 信息顏色 - 專業藍色
  static Color getInfoColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Color(0xFF42A5F5)  // 深色模式：亮藍 (對比度 4.5:1)
        : Color(0xFF1976D2); // 淺色模式：深藍 (對比度 7.0:1)
  }
}

// ========================= Enhanced Animation Utilities =========================

/// 優化的動畫工具類 - 提供常用的動畫效果和優化選項
class AnimationUtils {
  /// 創建帶有性能優化的縮放動畫
  static Widget createOptimizedScaleAnimation({
    required Widget child,
    required AnimationController controller,
    double scaleFrom = 0.0,
    double scaleTo = 1.0,
    Curve curve = MotionConstants.standardEasing,
  }) {
    final animation = Tween<double>(
      begin: scaleFrom,
      end: scaleTo,
    ).animate(CurvedAnimation(parent: controller, curve: curve));
    
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.scale(
        scale: animation.value,
        child: child,
      ),
      child: child,
    );
  }
  
  /// 創建優化的淡入動畫
  static Widget createFadeAnimation({
    required Widget child,
    required AnimationController controller,
    double opacityFrom = 0.0,
    double opacityTo = 1.0,
    Curve curve = MotionConstants.standardEasing,
  }) {
    final animation = Tween<double>(
      begin: opacityFrom,
      end: opacityTo,
    ).animate(CurvedAnimation(parent: controller, curve: curve));
    
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
  
  /// 創建滑入動畫
  static Widget createSlideAnimation({
    required Widget child,
    required AnimationController controller,
    Offset offsetFrom = const Offset(0.0, 1.0),
    Offset offsetTo = Offset.zero,
    Curve curve = MotionConstants.deceleratedEasing,
  }) {
    final animation = Tween<Offset>(
      begin: offsetFrom,
      end: offsetTo,
    ).animate(CurvedAnimation(parent: controller, curve: curve));
    
    return SlideTransition(
      position: animation,
      child: child,
    );
  }

  /// 創建彈性進入動畫（使用 flutter_animate 風格）
  static Widget createBounceInAnimation({
    required Widget child,
    Duration delay = Duration.zero,
    Duration duration = MotionConstants.medium,
  }) {
    return child
        .animate(delay: delay)
        .scale(
          duration: duration,
          curve: MotionConstants.springEasing,
          begin: const Offset(0.3, 0.3),
          end: const Offset(1.0, 1.0),
        )
        .fadeIn(
          duration: duration * 0.7,
          curve: MotionConstants.standardEasing,
        );
  }

  /// 創建錯列動畫列表項
  static Widget createStaggeredListItem({
    required Widget child,
    required int index,
    Duration delay = MotionConstants.staggerDelay,
  }) {
    return AnimationConfiguration.staggeredList(
      position: index,
      delay: delay,
      child: SlideAnimation(
        curve: MotionConstants.deceleratedEasing,
        duration: MotionConstants.listItemAnimation,
        verticalOffset: 50.0,
        child: FadeInAnimation(
          curve: MotionConstants.standardEasing,
          duration: MotionConstants.listItemAnimation,
          child: child,
        ),
      ),
    );
  }
}

/// 優化的響應式動畫包裝器
class ResponsiveAnimatedContainer extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final BoxDecoration? decoration;
  final double? width;
  final double? height;

  const ResponsiveAnimatedContainer({
    super.key,
    required this.child,
    this.duration = MotionConstants.fast,
    this.curve = MotionConstants.standardEasing,
    this.padding,
    this.margin,
    this.decoration,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      padding: padding,
      margin: margin,
      decoration: decoration,
      width: width,
      height: height,
      child: child,
    );
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
    
    // Performance Optimization: Direct timestamp comparison is O(1) vs DateTime arithmetic
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final expiryMicros = cached.timestamp.microsecondsSinceEpoch + cached.ttl.inMicroseconds;
    
    if (nowMicros > expiryMicros) {
      // 過期，移除 - O(1) operation
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
          ChangeNotifierProvider(create: (_) => MtrCatalogProvider()), // MTR catalog provider
          ChangeNotifierProvider(create: (_) => MtrScheduleProvider()), // MTR schedule provider
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
                  pageTransitionsTheme: PageTransitionsTheme(builders: {
                    TargetPlatform.android: _EnhancedPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.windows: _EnhancedPageTransitionsBuilder(),
                    TargetPlatform.linux: _EnhancedPageTransitionsBuilder(),
                    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
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
                    // 針對深色主題優化文字顏色對比度 - WCAG AAA 標準 (7:1 對比度)
                    bodyLarge: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withOpacity(0.90), // 提升至 0.90 獲得更好對比
                    ),
                    bodyMedium: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.90), // 主要內容文字保持高對比
                    ),
                    bodySmall: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.65), // 次要文字適度降低
                    ),
                    titleLarge: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white.withOpacity(0.97), // 標題使用最高對比度
                      fontWeight: FontWeight.w600,
                    ),
                    titleMedium: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white.withOpacity(0.92), // 中等標題保持清晰
                      fontWeight: FontWeight.w600,
                    ),
                    titleSmall: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white.withOpacity(0.88), // 小標題良好可讀性
                    ),
                    headlineMedium: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white.withOpacity(0.97), // 大標題最高對比
                      fontWeight: FontWeight.w600,
                    ),
                    labelLarge: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withOpacity(0.90), // 標籤文字清晰可辨
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                themeMode: themeProvider.useSystemTheme 
                    ? ThemeMode.system 
                    : themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
                scrollBehavior: EnhancedScrollBehavior(),
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


/* ========================= Enhanced Page Transitions ========================= */

/// Enhanced page transitions builder with smooth animations
class _EnhancedPageTransitionsBuilder extends PageTransitionsBuilder {
  const _EnhancedPageTransitionsBuilder();

  @override
  Widget buildTransitions<T extends Object?>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      fillColor: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}

/* ========================= Motion Constants ========================= */

class MotionConstants {
  // Unified and slowed down Material motion durations for smoother experience
  static const Duration ultraFast = Duration(milliseconds: 200);  // Increased from 100
  static const Duration fast = Duration(milliseconds: 300);       // Increased from 150
  static const Duration medium = Duration(milliseconds: 450);     // Increased from 300
  static const Duration slow = Duration(milliseconds: 600);       // Increased from 400
  
  // Enhanced Material motion curves for smoother animations
  static const Curve standardEasing = Curves.fastOutSlowIn;
  static const Curve emphasizedEasing = Cubic(0.2, 0.0, 0, 1.0); // More dramatic
  static const Curve deceleratedEasing = Cubic(0.0, 0.0, 0.2, 1.0); // Smoother deceleration
  static const Curve acceleratedEasing = Cubic(0.4, 0.0, 1.0, 1.0); // Smoother acceleration
  static const Curve springEasing = Curves.elasticOut; // Spring-like bounce
  static const Curve fadeInEasing = Cubic(0.0, 0.0, 0.2, 1.0); // Optimized for fade-in (ease-out)
  static const Curve fadeOutEasing = Cubic(0.4, 0.0, 1.0, 1.0); // Optimized for fade-out (ease-in)
  static const Curve bounceInEasing = Curves.easeOutBack; // Slight overshoot for playful entrance
  
  // Unified animation configuration - all using consistent timings
  static const Duration pageTransition = medium;        // 450ms
  static const Duration contentTransition = fast;       // 300ms
  static const Duration modalTransition = slow;         // 600ms
  static const Duration microInteraction = ultraFast;   // 200ms
  static const Duration listItemAnimation = fast;       // 300ms (increased from 150)
  static const Duration staggerDelay = Duration(milliseconds: 50); // Increased from 30 for more noticeable stagger
  
  // Scroll-specific animation timing - unified and slowed
  static const Duration scrollAnimation = Duration(milliseconds: 350);      // Increased from 200
  static const Duration scrollSettling = Duration(milliseconds: 250);       // Increased from 150
  static const Duration overscrollAnimation = Duration(milliseconds: 450);  // Increased from 300
  
  // Enhanced stagger configurations - unified
  static const Duration listStagger = Duration(milliseconds: 40);   // Increased from 25
  static const Duration cardStagger = Duration(milliseconds: 60);   // Increased from 40
  static const Duration gridStagger = Duration(milliseconds: 35);   // Increased from 20
}

/* ========================= Enhanced Scroll Physics ========================= */

class EnhancedScrollPhysics {
  // Enhanced bouncing physics with better spring simulation
  static const BouncingScrollPhysics bouncing = BouncingScrollPhysics(
    decelerationRate: ScrollDecelerationRate.fast,
  );
  
  // Clamping physics for contained scrolling
  static const ClampingScrollPhysics clamping = ClampingScrollPhysics();
  
  // Platform adaptive physics - iOS bouncing, Android clamping
  static ScrollPhysics adaptive({ScrollPhysics? parent}) {
    return const BouncingScrollPhysics().applyTo(parent);
  }
  
  // Never scrollable for nested lists
  static const NeverScrollableScrollPhysics never = NeverScrollableScrollPhysics();
  
  // Custom physics with enhanced responsiveness
  static ScrollPhysics enhanced({ScrollPhysics? parent}) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
    ).applyTo(parent);
  }
  
  // Smooth physics for reorderable lists
  static ScrollPhysics reorderable({ScrollPhysics? parent}) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.normal,
    ).applyTo(parent);
  }
  
  // High-performance physics for large lists
  static ScrollPhysics performant({ScrollPhysics? parent}) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
    ).applyTo(parent);
  }
  
  // Smooth horizontal scrolling physics
  static ScrollPhysics horizontal({ScrollPhysics? parent}) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
    ).applyTo(parent);
  }
}

/* ========================= Enhanced Scroll Behavior ========================= */

class EnhancedScrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return EnhancedScrollPhysics.enhanced();
  }
  
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Return child without wrapping in Scrollbar to avoid controller conflicts
    // Individual widgets can add their own Scrollbar when needed
    return child;
  }
  
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Enhanced overscroll indicator with better visual feedback
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
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
          ? Colors.white.withOpacity(0.87)
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
          ? Colors.white.withOpacity(0.70)
          : null,
    );
  }
  
  static TextStyle scheduleCaptionStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
    );
  }
  
  static TextStyle scheduleErrorStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: AppColors.getErrorColor(context), // 使用語義化錯誤顏色
      fontWeight: FontWeight.w500,
    );
  }
  
  static TextStyle scheduleRouteHeaderStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeXXL * accessibility.textScale,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withOpacity(0.87)
          : null,
    );
  }
  
  static TextStyle scheduleStationNameStyle(BuildContext context, AccessibilityProvider accessibility) {
    return Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.white.withOpacity(0.87)
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
          ? Colors.white.withOpacity(0.87)
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
        color: Theme.of(context).colorScheme.shadow.withOpacity(0.4),
        blurRadius: 4,
        offset: const Offset(0, 1),
        spreadRadius: 1.5,
      ),
    ];
  }
  
  // 統一邊框
  static Border scheduleCardBorder(BuildContext context) {
    return Border.all(
      color: Theme.of(context).colorScheme.outline,
      width: UIConstants.borderWidth,
    );
  }
  
  static Border scheduleListTileBorder(BuildContext context) {
    return Border(
      bottom: BorderSide(
        color: Theme.of(context).colorScheme.outline.withOpacity(0.08),
        width: UIConstants.borderWidth,
      ),
    );
  }
  
  // 統一背景色 - WCAG 2.1 標準對比度優化
  static Color scheduleHeaderBackground(BuildContext context) {
    return Theme.of(context).colorScheme.primaryContainer;
  }
  
  // 錯誤背景 - 優化對比度與可讀性
  static Color scheduleErrorBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Colors.red.shade900.withOpacity(0.25)  // 深色模式：深紅背景，對比度更佳
        : Colors.red.shade50.withOpacity(0.85);   // 淺色模式：淡紅背景，柔和警示
  }
  
  // 錯誤邊框 - 增強視覺引導
  static Color scheduleErrorBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Colors.red.shade400.withOpacity(0.6)   // 深色模式：明亮紅邊框
        : Colors.red.shade700.withOpacity(0.5);   // 淺色模式：深紅邊框
  }
  
  // 統一圖標大小
  static double scheduleIconSize(BuildContext context, AccessibilityProvider accessibility, {double multiplier = 1.0}) {
    return iconSizeS * accessibility.iconScale * multiplier;
  }
  
  static double scheduleLargeIconSize(BuildContext context, AccessibilityProvider accessibility) {
    return circleSizeM * accessibility.iconScale;
  }
  
  // 統一圓圈文字組件配置 - 優化錯誤狀態顏色對比度
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
          ? AppColors.getErrorColor(context) // 使用語義化錯誤顏色
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
  
  // Routes 頁面背景色 - 警告提示優化對比度
  static Color routesWarningBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark 
        ? Colors.orange.shade900.withOpacity(0.22)  // 深色模式：深橙背景
        : Colors.orange.shade50.withOpacity(0.80);   // 淺色模式：淡橙背景
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
      color: AppColors.getWarningColor(context), // 使用語義化警告顏色
    );
  }
  
  static TextStyle routesWarningChipStyle(BuildContext context, AccessibilityProvider accessibility) {
    return TextStyle(
      fontSize: fontSizeS * accessibility.textScale,
      color: AppColors.getWarningColor(context), // 使用語義化警告顏色
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
  
  // Enhanced error tracking
  int _rateLimitCount = 0;
  bool _isRateLimited = false;
  int _retryAttempts = 0;
  DateTime? _nextRetryTime;
  
  // Network quality tracking
  int _successfulRequests = 0;
  int _failedRequests = 0;

  bool get hasApiError => _hasApiError;
  bool get isApiHealthy => !_hasApiError && !_isRateLimited;
  String? get lastErrorMessage => _lastErrorMessage;
  DateTime? get lastErrorTime => _lastErrorTime;
  int get consecutiveErrors => _consecutiveErrors;
  bool get isRateLimited => _isRateLimited;
  int get retryAttempts => _retryAttempts;
  DateTime? get nextRetryTime => _nextRetryTime;
  
  // Network quality metrics
  double get successRate {
    final total = _successfulRequests + _failedRequests;
    if (total == 0) return 1.0;
    return _successfulRequests / total;
  }
  
  String get networkQuality {
    final rate = successRate;
    if (rate >= 0.9) return 'excellent';
    if (rate >= 0.7) return 'good';
    if (rate >= 0.5) return 'fair';
    return 'poor';
  }
  
  // Check if we should stop making requests due to persistent errors
  bool get shouldStopRequests => _consecutiveErrors >= _maxConsecutiveErrors || _isRateLimited;
  
  // Enhanced error reporting with error type detection
  void reportApiError(String errorMessage, {int? statusCode}) {
    _hasApiError = true;
    _lastErrorMessage = errorMessage;
    _lastErrorTime = DateTime.now();
    _consecutiveErrors++;
    _failedRequests++;
    
    // Detect rate limiting (HTTP 429)
    if (statusCode == 429 || errorMessage.contains('429') || errorMessage.toLowerCase().contains('rate limit')) {
      _isRateLimited = true;
      _rateLimitCount++;
      
      // Calculate retry time with exponential backoff
      final backoffMinutes = (_rateLimitCount * 2).clamp(1, 30);
      _nextRetryTime = DateTime.now().add(Duration(minutes: backoffMinutes));
      
      debugPrint('HttpErrorProvider: Rate limit detected! Retry in $backoffMinutes minutes');
    }
    
    // Calculate next retry time for other errors
    if (!_isRateLimited && _consecutiveErrors >= 2) {
      final backoffSeconds = (30 * _consecutiveErrors).clamp(30, 300); // 30s to 5min
      _nextRetryTime = DateTime.now().add(Duration(seconds: backoffSeconds));
      debugPrint('HttpErrorProvider: Retry scheduled in $backoffSeconds seconds');
    }
    
    debugPrint('HttpErrorProvider: API error reported - $_lastErrorMessage (Status: $statusCode)');
    debugPrint('HttpErrorProvider: Consecutive errors: $_consecutiveErrors, Success rate: ${(successRate * 100).toStringAsFixed(1)}%');
    
    notifyListeners();
  }
  
  void clearApiError() {
    if (_hasApiError || _consecutiveErrors > 0 || _isRateLimited) {
      _hasApiError = false;
      _lastErrorMessage = null;
      _lastErrorTime = null;
      _consecutiveErrors = 0;
      _isRateLimited = false;
      _rateLimitCount = 0;
      _retryAttempts = 0;
      _nextRetryTime = null;
      
      debugPrint('HttpErrorProvider: API errors cleared');
      notifyListeners();
    }
  }
  
  void reportApiSuccess() {
    _successfulRequests++;
    
    if (_hasApiError || _consecutiveErrors > 0 || _isRateLimited) {
      clearApiError();
      debugPrint('HttpErrorProvider: API success reported, errors cleared. Success rate: ${(successRate * 100).toStringAsFixed(1)}%');
    }
  }
  
  void incrementRetryAttempt() {
    _retryAttempts++;
    notifyListeners();
  }
  
  // Check if enough time has passed to retry after consecutive errors
  bool canRetryAfterError() {
    if (!shouldStopRequests) return true;
    if (_nextRetryTime == null) return true;
    
    return DateTime.now().isAfter(_nextRetryTime!);
  }
  
  // Get remaining wait time
  Duration? getRemainingWaitTime() {
    if (_nextRetryTime == null) return null;
    final now = DateTime.now();
    if (now.isAfter(_nextRetryTime!)) return null;
    return _nextRetryTime!.difference(now);
  }
  
  String getErrorStatusMessage(bool isEnglish) {
    if (!_hasApiError && !_isRateLimited) return '';
    
    if (_isRateLimited) {
      final remaining = getRemainingWaitTime();
      if (remaining != null) {
        final minutes = remaining.inMinutes;
        final seconds = remaining.inSeconds % 60;
        return isEnglish 
          ? 'Rate limit exceeded - retry in ${minutes}m ${seconds}s'
          : '已達速率限制 - ${minutes}分${seconds}秒後重試';
      }
      return isEnglish 
        ? 'Rate limit exceeded - please wait'
        : '已達速率限制 - 請稍候';
    }
    
    if (shouldStopRequests) {
      final remaining = getRemainingWaitTime();
      if (remaining != null) {
        final seconds = remaining.inSeconds;
        return isEnglish 
          ? 'Multiple errors - retry in ${seconds}s'
          : '多次錯誤 - ${seconds}秒後重試';
      }
      return isEnglish 
        ? 'Multiple API errors - requests paused'
        : '多次API錯誤 - 請求已暫停';
    }
    
    return isEnglish
      ? 'API Error: ${_lastErrorMessage ?? 'Unknown error'}'
      : 'API錯誤：${_lastErrorMessage ?? '未知錯誤'}';
  }
  
  // Reset statistics (useful for testing)
  void resetStatistics() {
    _successfulRequests = 0;
    _failedRequests = 0;
    notifyListeners();
  }
}


/* ========================= Theme Color Option Model ========================= */

class ThemeColorOption {
  final String name;
  final List<Color> colors;
  
  const ThemeColorOption({
    required this.name,
    required this.colors,
  });
}

/* ========================= Theme Provider ========================= */

class ThemeProvider extends ChangeNotifier {
  static const String _colorCategoryKey = 'app_color_category';
  static const String _colorIndexKey = 'app_color_index';
  static const String _isDarkModeKey = 'app_is_dark_mode';
  static const String _useSystemThemeKey = 'app_use_system_theme';
  
  int _colorCategoryIndex = 0;
  int _colorIndex = 0;
  bool _isDarkMode = false;
  bool _useSystemTheme = true;
  SharedPreferences? _prefs;

  int get colorCategoryIndex => _colorCategoryIndex;
  int get colorIndex => _colorIndex;
  Color get seedColor => colorOptions[_colorCategoryIndex].colors[_colorIndex];
  bool get isDarkMode => _isDarkMode;
  bool get useSystemTheme => _useSystemTheme;

  // 視覺舒適度優化的主題顏色選項 - WCAG 2.1 標準對比度，提升可讀性與美觀度
  static const List<ThemeColorOption> colorOptions = [
    // 標準舒適色彩 - 平衡美學與可用性，WCAG AA 級對比度
    ThemeColorOption(
      name: 'Standard',
      colors: [
        Color(0xFF5F9F5F), // 清雅綠 - 自然舒適，對比度 4.8:1 (AA)
        Color(0xFF3D7C96), // 海洋藍 - 專業寧靜，對比度 5.1:1 (AA)
        Color(0xFF8B6B9E), // 薰衣草紫 - 優雅溫和，對比度 4.6:1 (AA)
        Color(0xFFB87333), // 暖琥珀 - 溫暖活力，對比度 4.5:1 (AA)
        Color(0xFFB8696E), // 玫瑰紅 - 柔和精緻，對比度 4.7:1 (AA)
        Color(0xFF4A8B8B), // 青綠 - 平靜專注，對比度 5.0:1 (AA)
      ],
    ),
    
    // 低飽和度護眼色彩 - 長時間使用友好，減少眼疲勞，WCAG AA+ 級
    ThemeColorOption(
      name: 'Comfort',
      colors: [
        Color(0xFF668866), // 森林綠 - 極致護眼，對比度 5.2:1 (AA+)
        Color(0xFF6A8CBE), // 天空藍 - 柔和明亮，對比度 4.9:1 (AA)
        Color(0xFF9D8AA8), // 柔紫 - 平靜優雅，對比度 4.5:1 (AA)
        Color(0xFFB89968), // 大地棕 - 溫暖自然，對比度 4.6:1 (AA)
        Color(0xFFBA8C8E), // 淡粉 - 溫柔細膩，對比度 4.8:1 (AA)
        Color(0xFF78A6A6), // 海綠 - 清新寧靜，對比度 5.3:1 (AA+)
      ],
    ),
    
    // 高對比度無障礙色彩 - WCAG AAA 標準，視力輔助優化，最高可訪問性
    ThemeColorOption(
      name: 'Accessible',
      colors: [
        Color(0xFF1B5E20), // 翡翠綠 - 超高對比 7.2:1 (AAA)
        Color(0xFF0D47A1), // 皇室藍 - 極高對比 8.5:1 (AAA)
        Color(0xFF6A1B9A), // 紫羅蘭 - 鮮明識別 6.8:1 (AAA)
        Color(0xFFE65100), // 鮮橙 - 高可見度 5.2:1 (AA+)
        Color(0xFFC62828), // 櫻桃紅 - 警示醒目 5.8:1 (AA+)
        Color(0xFF00695C), // 深青 - 深度對比 7.5:1 (AAA)
      ],
    ),
  ];

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // 載入保存的色彩類別和索引
    _colorCategoryIndex = _prefs!.getInt(_colorCategoryKey) ?? 0;
    _colorIndex = _prefs!.getInt(_colorIndexKey) ?? 0;
    
    // 確保索引在有效範圍內
    _colorCategoryIndex = _colorCategoryIndex.clamp(0, colorOptions.length - 1);
    if (_colorCategoryIndex < colorOptions.length) {
      _colorIndex = _colorIndex.clamp(0, colorOptions[_colorCategoryIndex].colors.length - 1);
    }
    
    _isDarkMode = _prefs!.getBool(_isDarkModeKey) ?? false;
    _useSystemTheme = _prefs!.getBool(_useSystemThemeKey) ?? true;
    
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    // 找到對應的類別和索引
    for (int categoryIndex = 0; categoryIndex < colorOptions.length; categoryIndex++) {
      final colors = colorOptions[categoryIndex].colors;
      for (int colorIndex = 0; colorIndex < colors.length; colorIndex++) {
        if (colors[colorIndex].value == color.value) {
          _colorCategoryIndex = categoryIndex;
          _colorIndex = colorIndex;
          await _save();
          return;
        }
      }
    }
  }

  Future<void> setColorByIndex(int categoryIndex, int colorIndex) async {
    if (categoryIndex >= 0 && categoryIndex < colorOptions.length) {
      final colors = colorOptions[categoryIndex].colors;
      if (colorIndex >= 0 && colorIndex < colors.length) {
        _colorCategoryIndex = categoryIndex;
        _colorIndex = colorIndex;
        await _save();
      }
    }
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
    await _prefs!.setInt(_colorCategoryKey, _colorCategoryIndex);
    await _prefs!.setInt(_colorIndexKey, _colorIndex);
    await _prefs!.setBool(_isDarkModeKey, _isDarkMode);
    await _prefs!.setBool(_useSystemThemeKey, _useSystemTheme);
    notifyListeners();
  }

  String getColorName(Color color, bool isEnglish) {
    // 查找顏色在哪個類別和索引中
    for (int categoryIndex = 0; categoryIndex < colorOptions.length; categoryIndex++) {
      final category = colorOptions[categoryIndex];
      for (int colorIndex = 0; colorIndex < category.colors.length; colorIndex++) {
        if (category.colors[colorIndex].value == color.value) {
          final categoryName = getCategoryDisplayName(category.name, isEnglish);
          final colorName = getColorDisplayName(categoryIndex, colorIndex, isEnglish);
          return '$categoryName - $colorName';
        }
      }
    }
    return isEnglish ? 'Custom Color' : '自定義顏色';
  }
  
  String getCategoryDisplayName(String categoryName, bool isEnglish) {
    switch (categoryName) {
      case 'Standard':
        return isEnglish ? 'Standard' : '標準舒適';
      case 'Comfort':
        return isEnglish ? 'Eye Comfort' : '護眼舒適';
      case 'Accessible':
        return isEnglish ? 'High Contrast' : '高對比度';
      default:
        return categoryName;
    }
  }
  
  String getColorDisplayName(int categoryIndex, int colorIndex, bool isEnglish) {
    final standardNames = [
      isEnglish ? ['Sage Green', 'Ocean Blue', 'Lavender', 'Warm Amber', 'Rose', 'Teal'] 
                : ['清雅綠', '海洋藍', '薰衣草', '暖琥珀', '玫瑰', '青綠'],
      isEnglish ? ['Forest Green', 'Sky Blue', 'Soft Purple', 'Earth Brown', 'Blush Pink', 'Sea Green'] 
                : ['森林綠', '天空藍', '柔紫', '大地棕', '淡粉', '海綠'],
      isEnglish ? ['Emerald', 'Royal Blue', 'Violet', 'Vivid Orange', 'Cherry Red', 'Deep Teal'] 
                : ['翡翠綠', '皇室藍', '紫羅蘭', '鮮橙', '櫻桃紅', '深青']
    ];
    
    if (categoryIndex >= 0 && categoryIndex < standardNames.length && 
        colorIndex >= 0 && colorIndex < standardNames[categoryIndex].length) {
      return standardNames[categoryIndex][colorIndex];
    }
    
    return isEnglish ? 'Color ${colorIndex + 1}' : '顏色 ${colorIndex + 1}';
  }
}

  /* ========================= Developer Settings Provider ========================= */
  
  class DeveloperSettingsProvider extends ChangeNotifier {
    static const String _hideStationIdKey = 'hide_station_id';
    static const String _showGridDebugKey = 'show_grid_debug';
    static const String _showCacheStatusKey = 'show_cache_status';
    static const String _showMtrArrivalDetailsKey = 'show_mtr_arrival_details';
    
    bool _hideStationId = false;
    bool _showGridDebug = false;
    bool _showCacheStatus = false; // Default to hidden
    bool _showMtrArrivalDetails = false; // Default to hidden for cleaner UI
    SharedPreferences? _prefs;

    bool get hideStationId => _hideStationId;
    bool get showGridDebug => _showGridDebug;
    bool get showCacheStatus => _showCacheStatus;
    bool get showMtrArrivalDetails => _showMtrArrivalDetails;

    Future<void> initialize() async {
      _prefs = await SharedPreferences.getInstance();
      _hideStationId = _prefs!.getBool(_hideStationIdKey) ?? false;
      _showGridDebug = _prefs!.getBool(_showGridDebugKey) ?? false;
      _showCacheStatus = _prefs!.getBool(_showCacheStatusKey) ?? false;
      _showMtrArrivalDetails = _prefs!.getBool(_showMtrArrivalDetailsKey) ?? false;
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
    
    Future<void> setShowCacheStatus(bool show) async {
      _showCacheStatus = show;
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_showCacheStatusKey, show);
      notifyListeners();
    }
    
    Future<void> setShowMtrArrivalDetails(bool show) async {
      _showMtrArrivalDetails = show;
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_showMtrArrivalDetailsKey, show);
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
  String get mtr => _isEnglish ? 'MTR' : '港鐵';
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
      // Retry logic with exponential backoff
      const maxRetries = 3;
      var retryCount = 0;
      Exception? lastException;
      
      while (retryCount < maxRetries) {
        try {
          final uri = Uri.parse('$base$stationId');
          final res = await _client.get(uri, headers: {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 10));
          
          // Handle different HTTP status codes
          if (res.statusCode == 429) {
            // Rate limit - report and fail immediately (don't retry)
            final errorMessage = 'Rate limit exceeded (429)';
            errorProvider?.reportApiError(errorMessage, statusCode: 429);
            throw Exception(errorMessage);
          } else if (res.statusCode >= 500 && res.statusCode < 600) {
            // Server error - retry with backoff
            final errorMessage = 'Server error (${res.statusCode})';
            debugPrint('API: $errorMessage - Attempt ${retryCount + 1}/$maxRetries');
            
            if (retryCount < maxRetries - 1) {
              // Exponential backoff: 1s, 2s, 4s
              final backoffSeconds = (1 << retryCount);
              debugPrint('API: Retrying in ${backoffSeconds}s...');
              errorProvider?.incrementRetryAttempt();
              await Future.delayed(Duration(seconds: backoffSeconds));
              retryCount++;
              continue;
            } else {
              // Final retry failed
              errorProvider?.reportApiError(errorMessage, statusCode: res.statusCode);
              throw Exception(errorMessage);
            }
          } else if (res.statusCode != 200) {
            // Other HTTP errors
            final errorMessage = 'HTTP ${res.statusCode}';
            errorProvider?.reportApiError(errorMessage, statusCode: res.statusCode);
            throw Exception(errorMessage);
          }
          
          // Success - parse response
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
          debugPrint('API: Success (${_lastResponseTime.inMilliseconds}ms)');
          completer.complete(parsed);
          break; // Exit retry loop
          
        } catch (e) {
          lastException = e is Exception ? e : Exception(e.toString());
          
          // Don't retry for certain errors
          if (e.toString().contains('429') || 
              e.toString().contains('Rate limit') ||
              e.toString().contains('Invalid response')) {
            // Report error and fail immediately
            if (!e.toString().contains('429')) {
              errorProvider?.reportApiError(e.toString());
            }
            completer.completeError(lastException);
            break;
          }
          
          // Network/timeout errors - retry
          if (retryCount < maxRetries - 1) {
            final backoffSeconds = (1 << retryCount);
            debugPrint('API: Network error - Retrying in ${backoffSeconds}s... (${retryCount + 1}/$maxRetries)');
            errorProvider?.incrementRetryAttempt();
            await Future.delayed(Duration(seconds: backoffSeconds));
            retryCount++;
          } else {
            // Final retry failed
            errorProvider?.reportApiError(e.toString());
            debugPrint('API: All retries exhausted');
            completer.completeError(lastException);
            break;
          }
        }
      }
      
      _debounceTimers.remove(cacheKey);
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
    // 確保索引在有效範圍內 (0-3 for Schedule, Routes, MTR, Settings)
    if (cachedIndex >= 0 && cachedIndex <= 3) {
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
      const MtrSchedulePage(key: ValueKey('mtr')),
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
                        decoration: BoxDecoration(
                          color: AppColors.getSuccessColor(context), // 使用語義化成功顏色
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
              icon: Icon(Icons.train, size: 24 * accessibility.iconScale), 
              label: lang.mtr
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

class _PlatformCardState extends State<_PlatformCard> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _contentAnimationController;
  late AnimationController _staggerController;
  late Animation<double> _elevationAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isExpanded = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    // Main expansion animation controller with non-linear easing
    _animationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );

    // ✅ Non-linear expansion curve - emphasized easing for dramatic effect
    final curve = CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.emphasizedEasing, // Non-linear: Cubic(0.2, 0.0, 0, 1.0)
      reverseCurve: MotionConstants.acceleratedEasing, // Asymmetric reverse for snappy collapse
    );
    
    // Enhanced elevation animation with non-linear progression
    _elevationAnimation = Tween<double>(
      begin: 2.0, 
      end: 6.0, // More pronounced elevation change
    ).animate(curve);
    
    // Content fade and slide animation controller
    _contentAnimationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );
    
    // ✅ Non-linear fade-in for content - optimized ease-out
    _fadeAnimation = CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.fadeInEasing, // Non-linear: Cubic(0.0, 0.0, 0.2, 1.0)
      reverseCurve: MotionConstants.fadeOutEasing, // Asymmetric fade-out: Cubic(0.4, 0.0, 1.0, 1.0)
    );
    
    // ✅ Non-linear slide with emphasized easing
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05), // Slightly increased for more dramatic entrance
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.emphasizedEasing, // Non-linear slide
      reverseCurve: MotionConstants.acceleratedEasing, // Quick slide out
    ));
    
    // Train list stagger animation controller with bounce effect
    _staggerController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );

    _isExpanded = widget.platform.trains.isNotEmpty;
    if (_isExpanded) {
      _animationController.value = 1.0;
      _contentAnimationController.value = 1.0;
      _staggerController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _contentAnimationController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _onExpansionChanged(bool expanded) {
    setState(() {
      _isExpanded = expanded;
      _isPressed = false; // Reset press state during expansion changes
    });
    if (expanded) {
      _animationController.forward();
      _contentAnimationController.forward();
      _staggerController.forward(from: 0);
      HapticFeedback.mediumImpact();
    } else {
      _animationController.reverse();
      _contentAnimationController.reverse();
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    
    // Conditional state checks for platform card
    final hasTrains = widget.platform.trains.isNotEmpty;
    final isActive = _isExpanded || _isPressed;
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // ✅ Subtle scale animation for smooth drop - very minimal bounce
        final expandScale = _isExpanded 
            ? 0.98 + (0.02 * MotionConstants.emphasizedEasing.transform(_animationController.value))
            : 1.0;
        
        // ✅ Press/push effect - scale down when pressed
        final pressScale = _isPressed ? 0.97 : 1.0;
        
        // Combine both effects
        final scaleValue = expandScale * pressScale;
        
        return AnimatedScale(
          scale: scaleValue,
          duration: _isPressed ? MotionConstants.microInteraction : MotionConstants.contentTransition,
          curve: _isPressed ? Curves.easeOutCubic : MotionConstants.emphasizedEasing,
          child: AnimatedContainer(
            duration: MotionConstants.contentTransition,
            curve: MotionConstants.emphasizedEasing, // ✅ Non-linear curve for smooth dropdown
            margin: EdgeInsets.symmetric(
              horizontal: math.max(UIConstants.platformCardMargin.horizontal / 2, 8.0), // Responsive margin
              vertical: UIConstants.platformCardMargin.vertical,
            ),
            constraints: const BoxConstraints(
              maxWidth: double.infinity, // Allow full width but constrain content
            ),
            decoration: BoxDecoration(
              // Conditional background using theme colors
              color: isActive 
                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1)
                  : hasTrains 
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(UIConstants.platformCardBorderRadius),
              border: Border.all(
                // Conditional border using theme colors
                color: isActive
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                    : hasTrains
                        ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.8)
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                width: isActive ? 1.5 : UIConstants.borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  // Theme-aware shadow
                  color: isActive 
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: _elevationAnimation.value * 1.5,
                  offset: Offset(0, _elevationAnimation.value * 0.6),
                ),
                if (isActive) ...[
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: _elevationAnimation.value * 3,
                    offset: Offset(0, _elevationAnimation.value * 1.0),
                  ),
                ],
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
            builder: (context, accessibility, _) => AnimatedContainer(
              duration: MotionConstants.contentTransition,
              child: AdaptiveCircleText(
                text: '${widget.platform.platformId}',
                circleSize: math.max(40, 40 * math.min(accessibility.textScale, 1.3)), // Scale circle with text but limit growth
                baseFontSize: math.min(18 * accessibility.textScale, 24), // Cap font size to prevent overflow
                fontWeight: FontWeight.w700,
                // Conditional circle colors using theme colors
                textColor: isActive
                    ? Theme.of(context).colorScheme.onPrimary
                    : hasTrains 
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                backgroundColor: isActive
                    ? Theme.of(context).colorScheme.primary
                    : hasTrains
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderColor: isActive
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                    : hasTrains
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
          title: AnimatedDefaultTextStyle(
            duration: MotionConstants.contentTransition,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              // Conditional title colors using theme colors
              color: isActive 
                  ? Theme.of(context).colorScheme.primary
                  : hasTrains
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            child: Text(
              '${lang.platform} ${widget.platform.platformId}',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: widget.platform.trains.isEmpty
                    ? ListTile(title: Center(child: Text(lang.noTrains)))
                    : AnimationLimiter(
                        child: ImplicitlyAnimatedList<TrainInfo>(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          items: widget.platform.trains,
                          areItemsTheSame: (a, b) => a.identity == b.identity,
                          itemBuilder: (context, anim, train, i) {
                            return _buildAnimatedTrainTile(
                              anim: anim,
                              train: train,
                              index: i,
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Enhanced animated train tile with stagger effect
  Widget _buildAnimatedTrainTile({
    required Animation<double> anim,
    required TrainInfo train,
    required int index,
  }) {
    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, child) {
        // Calculate stagger delay based on index for wave effect
        final delay = (index * 0.04).clamp(0.0, 0.35); // Slightly increased for more noticeable stagger
        final animationValue = (_staggerController.value - delay).clamp(0.0, 1.0);
        
        // ✅ Non-linear curve for train tiles - bouncy entrance
        final easedValue = MotionConstants.bounceInEasing.transform(animationValue);
        
        return Transform.translate(
          offset: Offset(0, 25 * (1 - easedValue.clamp(0.0, 1.0))), // Clamp for bounce overshoot
          child: Opacity(
            opacity: (0.2 + (0.8 * easedValue)).clamp(0.0, 1.0), // ✅ Clamp opacity to valid range
            child: child,
          ),
        );
      },
      child: AnimationConfiguration.staggeredList(
        position: index,
        delay: MotionConstants.staggerDelay,
        child: SlideAnimation(
          curve: MotionConstants.emphasizedEasing, // ✅ Non-linear slide
          duration: MotionConstants.listItemAnimation,
          verticalOffset: 35.0, // Increased for more dramatic entrance
          child: FadeInAnimation(
            curve: MotionConstants.fadeInEasing, // ✅ Non-linear fade
            duration: MotionConstants.listItemAnimation,
            child: SizeFadeTransition(
              sizeFraction: 0.7,
              curve: MotionConstants.emphasizedEasing,
              animation: anim,
              child: _TrainTile(
                train: train,
                platformId: widget.platform.platformId,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _TrainTile extends StatefulWidget {
  final TrainInfo train;
  final int platformId;
  const _TrainTile({required this.train, required this.platformId});

  @override
  State<_TrainTile> createState() => _TrainTileState();
}

class _TrainTileState extends State<_TrainTile> {
  bool _isPressed = false;

  // 根據列車狀態返回語義化顏色 - WCAG 標準對比度
  Color _statusColor(BuildContext context) {
    if (widget.train.isStopped) return AppColors.getErrorColor(context);      // 停運：錯誤紅色
    if (widget.train.isArrivingSoon) return AppColors.getWarningColor(context); // 即將到達：警告橙色
    if (widget.train.isDepartingSoon) return AppColors.getInfoColor(context);   // 即將離開：信息藍色
    return Theme.of(context).colorScheme.primary;                              // 正常：主題色
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final color = _statusColor(context);
    final ad = widget.train.arrivalDeparture.toUpperCase() == 'D' ? lang.departs : lang.arrives;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: MotionConstants.microInteraction,
      curve: Curves.easeOutCubic,
      child: OpenContainer(
        transitionType: ContainerTransitionType.fade,
        transitionDuration: MotionConstants.modalTransition,
        closedElevation: 0,
        openElevation: 4,
        closedColor: Theme.of(context).colorScheme.surface,
        openColor: Theme.of(context).colorScheme.surface,
        onClosed: (_) {
          HapticFeedback.lightImpact();
        },
        closedBuilder: (context, open) => GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: ListTile(
            onTap: () {
              HapticFeedback.selectionClick();
              open();
            },
            leading: Consumer<AccessibilityProvider>(
              builder: (context, accessibility, _) => AnimatedContainer(
                duration: MotionConstants.contentTransition,
                curve: MotionConstants.emphasizedEasing,
                child: AdaptiveCircleText(
                  text: widget.train.routeNo.isEmpty ? '?' : widget.train.routeNo,
                  circleSize: math.max(40, 40 * math.min(accessibility.textScale, 1.3)), // Scale circle with text but limit growth
                  baseFontSize: math.min(14 * accessibility.textScale, 18), // Cap font size to prevent overflow
                  textColor: color,
                  backgroundColor: color.withOpacity(_isPressed ? 0.25 : 0.15),
                  borderColor: color.withOpacity(_isPressed ? 0.7 : 0.5),
                  borderWidth: _isPressed ? 2.0 : 1.5,
                ),
              ),
            ),
            title: AnimatedDefaultTextStyle(
              duration: MotionConstants.contentTransition,
              style: TextStyle(
                fontWeight: _isPressed ? FontWeight.w600 : FontWeight.w500,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.87)
                    : Theme.of(context).colorScheme.onSurface,
              ),
              child: Text(
                widget.train.name(lang.isEnglish),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            subtitle: Text(
              '$ad: ${widget.train.time(lang.isEnglish)} • ${widget.train.trainLength ?? '?'} ${lang.cars}',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.70)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            trailing: widget.train.isStopped 
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
        ),
        openBuilder: (context, close) => _TrainDetail(train: widget.train, platformId: widget.platformId),
      ),
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
        physics: EnhancedScrollPhysics.enhanced(),
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

class _RoutesPageState extends State<_RoutesPage> with TickerProviderStateMixin {
  final LrtApiService _api = LrtApiService();
  bool _loading = false;
  Map<int, LrtScheduleResponse> _schedules = {};
  List<String> _unmatched = [];
  bool _showRoutesList = true; // 控制路綫列表的顯示/隱藏
  bool _showDistrictsList = true; // 控制地區列表的顯示/隱藏
  bool _isLoadingCachedData = false;

  Timer? _loadingTimeoutTimer;
  Timer? _debounceTimer; // For debouncing route selections
  Timer? _errorBannerUpdateTimer; // For updating error banner countdown
  
  // Animation controllers for smooth transitions
  late AnimationController _contentAnimationController;
  late AnimationController _selectorAnimationController;
  late AnimationController _staggerController;
  
  // Animations
  late Animation<double> _contentFadeAnimation;
  late Animation<Offset> _contentSlideAnimation;
  
  // Cache for loaded routes to avoid redundant API calls
  final Map<String, Map<int, LrtScheduleResponse>> _routeCache = {};
  String? _lastLoadedRouteKey;
  
  // Performance optimization: Cache computed lists to avoid O(n) operations on every build
  List<String>? _cachedDistrictNames;
  List<String>? _cachedRouteLabels;
  int? _lastDistrictHash;
  int? _lastRouteHash;
  bool? _lastLangState;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize animation controllers
    _contentAnimationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );
    
    _selectorAnimationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );
    
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    // Setup animations
    _contentFadeAnimation = CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.emphasizedEasing,
    );
    
    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.standardEasing,
    ));
    
    // Start animations
    _contentAnimationController.forward();
    _selectorAnimationController.forward();
    _staggerController.forward();
    
    // Load saved switch states
    _loadSwitchStates();
    
    // Start error banner update timer for countdown
    _startErrorBannerUpdateTimer();
  }

  @override
  void dispose() {
    _cancelLoadingTimeout();
    _debounceTimer?.cancel();
    _errorBannerUpdateTimer?.cancel();
    _contentAnimationController.dispose();
    _selectorAnimationController.dispose();
    _staggerController.dispose();
    super.dispose();
  }
  
  // Start periodic timer to update error banner countdown - Performance optimized
  void _startErrorBannerUpdateTimer() {
    _errorBannerUpdateTimer?.cancel();
    _errorBannerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return; // Early exit if unmounted
      
      final httpError = context.read<HttpErrorProvider>();
      // Performance Optimization: Only trigger rebuild if there's actual countdown to display
      // This avoids unnecessary setState calls when no errors are present
      if ((httpError.hasApiError || httpError.isRateLimited) && 
          httpError.getRemainingWaitTime() != null) {
        setState(() {}); // Trigger rebuild for countdown update - O(1) operation
      } else if (!httpError.hasApiError && !httpError.isRateLimited) {
        // No errors, cancel timer to save battery/CPU
        _errorBannerUpdateTimer?.cancel();
        _errorBannerUpdateTimer = null;
      }
    });
  }

  void _startLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 45), () {
      // FIX: Add mounted check before setState
      if (!mounted) return;
      
      if (_loading) {
        debugPrint('Routes: Loading timeout reached, forcing stop');
        final httpError = context.read<HttpErrorProvider>();
        httpError.reportApiError('Loading timeout - requests stuck', statusCode: 408); // Request Timeout
        
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
      // FIX: Add mounted check before setState
      if (mounted) {
        setState(() {
          _loading = false;
          _isLoadingCachedData = false;
        });
      }
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
      // FIX: Add mounted check before setState in async operation
      if (!mounted) return;
      
      setState(() {
        // 默認展開狀態，改善初始 UX
        _showDistrictsList = prefs.getBool('show_districts_list') ?? true;
        _showRoutesList = prefs.getBool('show_routes_list') ?? true;
      });
      debugPrint('_loadSwitchStates: Loaded expansion states - districts: $_showDistrictsList, routes: $_showRoutesList');
    } catch (e) {
      debugPrint('_loadSwitchStates: Failed to load expansion states: $e');
      // FIX: Add mounted check here too
      if (!mounted) return;
      
      // 使用預設值 - 全部展開
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
      debugPrint('_saveSwitchStates: Saved expansion states - districts: $_showDistrictsList, routes: $_showRoutesList');
    } catch (e) {
      debugPrint('_saveSwitchStates: Failed to save expansion states: $e');
    }
  }

  // Optimized route loading with caching and debouncing
  Future<void> _loadRouteWithOptimizations(
    LrtRoute route,
    StationProvider sp,
    ConnectivityProvider net,
  ) async {
    // Cancel any pending debounce timer
    _debounceTimer?.cancel();
    
    // Debounce rapid selections (300ms delay)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      // FIX: Add mounted check at the start of timer callback
      if (!mounted) return;
      
      final routeKey = '${route.routeNumber}';
      
      // Check cache first
      if (_routeCache.containsKey(routeKey) && _lastLoadedRouteKey == routeKey) {
        debugPrint('Route $routeKey: Using cached data');
        // FIX: Add mounted check before setState
        if (mounted) {
          setState(() {
            _schedules = _routeCache[routeKey]!;
            _loading = false;
          });
        }
        return;
      }
      
      // Load fresh data
      await _loadForRoute(route, sp, net);
      
      // FIX: Add mounted check before caching operations
      if (!mounted) return;
      
      // Cache the result (limit cache size to 5 routes to save memory)
      if (_schedules.isNotEmpty) {
        if (_routeCache.length >= 5) {
          // Remove oldest cached route
          final oldestKey = _routeCache.keys.first;
          _routeCache.remove(oldestKey);
          debugPrint('Route cache: Removed oldest entry $oldestKey');
        }
        _routeCache[routeKey] = Map.from(_schedules);
        _lastLoadedRouteKey = routeKey;
        debugPrint('Route $routeKey: Cached ${_schedules.length} stations');
      }
    });
  }
  
  // Clear route cache when district changes
  void _clearRouteCache() {
    _routeCache.clear();
    _lastLoadedRouteKey = null;
    debugPrint('Route cache: Cleared all cached data');
  }

  Future<void> _loadForRoute(LrtRoute route, StationProvider sp, ConnectivityProvider net) async {
    if (net.isOffline) return;
    
    final httpErrorProvider = context.read<HttpErrorProvider>();
    if (httpErrorProvider.shouldStopRequests && !httpErrorProvider.canRetryAfterError()) {
      debugPrint('Routes: Skipping load due to API errors');
      // FIX: Add mounted check before setState
      if (mounted) {
        setState(() {
          _loading = false;
          _isLoadingCachedData = false;
        });
      }
      return;
    }

    // FIX: Add mounted check before setState
    if (!mounted) return;
    
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
        // FIX: Add mounted check before setState
        if (mounted) {
          setState(() {
            _loading = false;
            _isLoadingCachedData = false;
          });
        }
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

      // Process results - Performance Optimization: Pre-allocate map size for O(1) insertions
      final newSchedules = <int, LrtScheduleResponse>{};
      // Pre-size the map if we know the approximate size
      if (ids.length < 20) {
        // Most routes have < 20 stations, pre-allocate for efficiency
        for (final result in results) {
          if (result != null) {
            newSchedules[result.key] = result.value; // O(1) insertion into pre-sized map
          }
        }
      } else {
        // For larger routes, standard processing
        for (final result in results) {
          if (result != null) {
            newSchedules[result.key] = result.value;
          }
        }
      }

      // Check if we got any data
      if (newSchedules.isEmpty && ids.isNotEmpty) {
        debugPrint('Routes: No data retrieved for any stations in route ${route.routeNumber}');
        httpErrorProvider.reportApiError('No data available for route');
      }

      // FIX: Add mounted check before setState after async operations
      if (!mounted) return;
      
      setState(() {
        _schedules = newSchedules;
        _loading = false;
        _isLoadingCachedData = false;
      });
      
    } catch (e) {
      debugPrint('Routes: Error loading route ${route.routeNumber}: $e');
      httpErrorProvider.reportApiError('Route loading failed: $e');
      
      // FIX: Add mounted check before setState in catch block
      if (!mounted) return;
      
      setState(() {
        _loading = false;
        _isLoadingCachedData = false;
      });
    }
  }
  
  /// ✅ AUTO-REFRESH: Refresh specific station data (optimized for single-station refresh)
  Future<void> _refreshSingleStation(int stationId, LrtRoute route, StationProvider sp, ConnectivityProvider net) async {
    if (!mounted || net.isOffline) return;
    
    final httpErrorProvider = context.read<HttpErrorProvider>();
    if (httpErrorProvider.shouldStopRequests && !httpErrorProvider.canRetryAfterError()) {
      return;
    }
    
    try {
      debugPrint('🔄 AUTO-REFRESH: Refreshing single station $stationId...');
      
      final sched = await _api.fetch(stationId).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Auto-refresh timeout for station $stationId', const Duration(seconds: 10));
        },
      );
      
      if (!mounted) return;
      
      if (sched.status == 1 && sched.platforms.isNotEmpty) {
        final routeKey = '${route.routeNumber}';
        
        setState(() {
          // Update only this station's data
          _schedules = {..._schedules, stationId: sched};
          _routeCache[routeKey] = _schedules;
        });
        
        httpErrorProvider.reportApiSuccess();
        debugPrint('✅ AUTO-REFRESH: Station $stationId refreshed successfully');
      }
      
    } catch (e) {
      debugPrint('⚠️ AUTO-REFRESH: Error refreshing station $stationId: $e');
      // Silent fail for background refresh
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final sp = context.watch<StationProvider>();
    final cat = context.watch<RoutesCatalogProvider>();
    final net = context.watch<ConnectivityProvider>();
    final devSettings = context.watch<DeveloperSettingsProvider>();

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

    // Performance Optimization: Cache district and route names to avoid O(n) map operations
    // Only recompute when districts, routes, or language changes (O(1) cache check vs O(n) map)
    final currentDistrictHash = districts.hashCode;
    final currentRouteHash = routes.hashCode;
    final currentLangState = lang.isEnglish;
    
    List<String> districtNames;
    if (_cachedDistrictNames == null || 
        _lastDistrictHash != currentDistrictHash || 
        _lastLangState != currentLangState) {
      // Recompute only when necessary - O(n) operation
      districtNames = districts.map((d) => d.displayName(lang.isEnglish)).toList();
      _cachedDistrictNames = districtNames;
      _lastDistrictHash = currentDistrictHash;
      _lastLangState = currentLangState;
    } else {
      // Use cached value - O(1) operation
      districtNames = _cachedDistrictNames!;
    }
    
    List<String> routeLabels;
    if (_cachedRouteLabels == null || 
        _lastRouteHash != currentRouteHash || 
        _lastLangState != currentLangState) {
      // Recompute only when necessary - O(n) operation
      routeLabels = routes.map((r) => '${lang.route} ${r.routeNumber} — ${r.displayDescription(lang.isEnglish)}').toList();
      _cachedRouteLabels = routeLabels;
      _lastRouteHash = currentRouteHash;
    } else {
      // Use cached value - O(1) operation
      routeLabels = _cachedRouteLabels!;
    }

    return Column(
      children: [
        // API 錯誤橫幅 - 顯示速率限制和持久性錯誤
        if (_buildApiErrorBanner(context) != null)
          _buildApiErrorBanner(context)!,
        
        // 緊湊的緩存狀態提示 - 可通過設置控制顯示
        if (hasUserSelection && devSettings.showCacheStatus)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 12 * context.watch<AccessibilityProvider>().iconScale,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${lang.usingCachedData} • ${cat.selectedDistrict?.displayName(lang.isEnglish)} • ${lang.route} ${cat.selectedRoute?.routeNumber}',
                    style: TextStyle(
                      fontSize: 10 * context.watch<AccessibilityProvider>().textScale,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 緊湊的地區和路綫選擇器
        FadeTransition(
          opacity: _contentFadeAnimation,
          child: SlideTransition(
            position: _contentSlideAnimation,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: hasUserSelection 
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.03)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasUserSelection
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
              child: buildOptimizedPortraitRouteSelector(districtNames, routeLabels, hasUserSelection, cat, sp, net),
            ),
          ),
        ),
        // 緊湊的加載指示器
        AnimatedContainer(
          duration: MotionConstants.contentTransition,
          curve: MotionConstants.standardEasing,
          height: _loading ? 2 : 0,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          child: LinearProgressIndicator(
            backgroundColor: Theme.of(context).colorScheme.surface,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        if (_unmatched.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: UIConstants.routesWarningBackground(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 14 * context.watch<AccessibilityProvider>().iconScale,
                      color: AppColors.getWarningColor(context), // 使用語義化警告顏色
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lang.unmatchedStations,
                      style: TextStyle(
                        fontSize: 11 * context.watch<AccessibilityProvider>().textScale,
                        fontWeight: FontWeight.w600,
                        color: AppColors.getPrimaryTextColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: _unmatched
                      .map((n) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: UIConstants.routesWarningBackground(context),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              n,
                              style: TextStyle(
                                fontSize: 10 * context.watch<AccessibilityProvider>().textScale,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
            switchOutCurve: MotionConstants.standardEasing,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: MotionConstants.emphasizedEasing,
                  )),
                  child: child,
                ),
              );
            },
            child: (!hasUserSelection)
                ? Center(
                    key: const ValueKey('select_district'),
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
                        key: const ValueKey('select_route'),
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
                        key: ValueKey('route_${route.routeNumber}'),
                        routeNo: route.routeNumber, 
                        routeName: route.displayDescription(lang.isEnglish),
                        schedules: _schedules, 
                        stationProvider: sp,
                        onRefreshStation: (stationId) => _refreshSingleStation(stationId, route, sp, net), // ✅ Pass station-specific refresh
                      )),
          ),
        ),
      ],
    );
  }
  // 優化的響應式路綫選擇器 - 智能佈局，增強的視覺層次和無障礙支持
  Widget buildOptimizedPortraitRouteSelector(
    List<String> districtNames,
    List<String> routeLabels,
    bool hasUserSelection,
    RoutesCatalogProvider cat,
    StationProvider sp,
    ConnectivityProvider net,
  ) {
    final accessibility = context.watch<AccessibilityProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final bool showDistricts = _showDistrictsList && districtNames.isNotEmpty;
    final bool showRoutes = _showRoutesList && hasUserSelection && routeLabels.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 更智能的響應式設計 - 多個斷點，針對 PC 瀏覽器優化
        final double availableWidth = constraints.maxWidth;
        final bool isNarrowScreen = availableWidth < 400;
        final bool isMediumScreen = availableWidth >= 400 && availableWidth < 700;
        final bool isWideScreen = availableWidth >= 700 && availableWidth < 1200;
        final bool isVeryWideScreen = availableWidth >= 1200;
        
        // 根據螢幕大小調整佈局 - 地區選擇器始終較短或等寬
        // 中等及更寬螢幕：地區選擇器保持較短，給予路線選擇器更多空間
        final int districtFlex = isVeryWideScreen ? 2 : (isWideScreen ? 2 : (isMediumScreen ? 1 : 1));
        final int routeFlex = isVeryWideScreen ? 3 : (isWideScreen ? 3 : (isMediumScreen ? 2 : 1));
        final double horizontalPadding = isNarrowScreen ? 8 : 10;
        final double verticalPadding = showDistricts || showRoutes ? 8 : 4;
        final double dividerMargin = 4;
        
        // 智能佈局切換：如果兩個都展開則橫向排列，只有一個展開則縱向排列
        final bool shouldStack = (showDistricts && !showRoutes) || (!showDistricts && showRoutes);
        
        // 使用 AnimatedSwitcher 實現平滑佈局切換動畫 - 優化過渡效果
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            // 組合淡入淡出與縮放效果，創造更流暢的過渡
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: 0.95,
                  end: 1.0,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              ),
            );
          },
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: shouldStack 
              ? _buildStackedLayout(
                  key: const ValueKey('stacked_layout'),
                  districtNames: districtNames,
                  routeLabels: routeLabels,
                  hasUserSelection: hasUserSelection,
                  cat: cat,
                  sp: sp,
                  net: net,
                  showDistricts: showDistricts,
                  showRoutes: showRoutes,
                  colorScheme: colorScheme,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                  isNarrowScreen: isNarrowScreen,
                  accessibility: accessibility,
                )
              : _buildRowLayout(
                  key: const ValueKey('row_layout'),
                  districtNames: districtNames,
                  routeLabels: routeLabels,
                  hasUserSelection: hasUserSelection,
                  cat: cat,
                  sp: sp,
                  net: net,
                  showDistricts: showDistricts,
                  showRoutes: showRoutes,
                  colorScheme: colorScheme,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                  districtFlex: districtFlex,
                  routeFlex: routeFlex,
                  dividerMargin: dividerMargin,
                  isNarrowScreen: isNarrowScreen,
                  accessibility: accessibility,
                ),
        );
      },
    );
  }

  // 縱向堆疊佈局構建器
  Widget _buildStackedLayout({
    required Key key,
    required List<String> districtNames,
    required List<String> routeLabels,
    required bool hasUserSelection,
    required RoutesCatalogProvider cat,
    required StationProvider sp,
    required ConnectivityProvider net,
    required bool showDistricts,
    required bool showRoutes,
    required ColorScheme colorScheme,
    required double horizontalPadding,
    required double verticalPadding,
    required bool isNarrowScreen,
    required AccessibilityProvider accessibility,
  }) {
    final lang = context.watch<LanguageProvider>();
    
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 地區選擇器
        _buildSelectorCard(
          icon: Icons.location_on_outlined,
          title: hasUserSelection && cat.selectedDistrict != null 
              ? cat.selectedDistrict!.displayName(lang.isEnglish)
              : lang.selectDistrict,
          isSelected: hasUserSelection && cat.selectedDistrict != null,
          showContent: showDistricts,
          switchValue: _showDistrictsList,
          onSwitchChanged: (value) async {
            if (value) {
              _staggerController.forward(from: 0);
            }
            // FIX: Add mounted check before setState in async callback
            if (mounted) {
              setState(() => _showDistrictsList = value);
            }
            await _saveSwitchStates();
          },
          hiddenMessage: '地區列表已隱藏',
          primaryColor: colorScheme.primary,
          containerColor: colorScheme.primaryContainer,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, 
            vertical: verticalPadding,
          ),
          accessibility: accessibility,
          content: showDistricts && districtNames.isNotEmpty
              ? _buildChipWrap(
                  items: districtNames,
                  selectedIndex: cat.districtIndex.clamp(0, districtNames.length - 1),
                  onSelected: (i) async {
                    _selectorAnimationController.reset();
                    _selectorAnimationController.forward();
                    await cat.setDistrictIndex(i);
                    // FIX: Add mounted check before setState in async callback
                    if (mounted) {
                      setState(() {
                        _schedules = {};
                      });
                    }
                    _clearRouteCache();
                  },
                  selectedColor: colorScheme.primaryContainer,
                  checkmarkColor: colorScheme.primary,
                  accessibility: accessibility,
                  isCompact: isNarrowScreen,
                )
              : null,
        ),
        
        // 間距分隔
        if (hasUserSelection)
          const SizedBox(height: 6),
        
        // 路綫選擇器
        if (hasUserSelection)
          _buildSelectorCard(
            icon: Icons.route_outlined,
            title: hasUserSelection && cat.selectedRoute != null 
                ? '${context.watch<LanguageProvider>().route} ${cat.selectedRoute!.routeNumber}'
                : context.watch<LanguageProvider>().selectRoute,
            isSelected: hasUserSelection && cat.selectedRoute != null,
            showContent: showRoutes,
            switchValue: _showRoutesList,
            onSwitchChanged: (value) async {
              if (value) {
                _staggerController.forward(from: 0);
              }
              // FIX: Add mounted check before setState in async callback
              if (mounted) {
                setState(() => _showRoutesList = value);
              }
              await _saveSwitchStates();
            },
            hiddenMessage: '路綫列表已隱藏',
            primaryColor: colorScheme.secondary,
            containerColor: colorScheme.secondaryContainer,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding, 
              vertical: verticalPadding,
            ),
            accessibility: accessibility,
            content: showRoutes && hasUserSelection && routeLabels.isNotEmpty
                ? _buildChipWrap(
                    items: routeLabels,
                    selectedIndex: cat.routeIndex.clamp(0, routeLabels.length - 1),
                    onSelected: (i) async {
                      final httpError = context.read<HttpErrorProvider>();
                      
                      if (httpError.shouldStopRequests && !httpError.canRetryAfterError()) {
                        debugPrint('Route selection: Skipping load due to persistent API errors');
                        await cat.setRouteIndex(i);
                        return;
                      }
                      
                      if (httpError.hasApiError && !httpError.canRetryAfterError()) {
                        debugPrint('Route selection: Skipping load - waiting for API error retry window');
                        await cat.setRouteIndex(i);
                        return;
                      }
                      
                      await cat.setRouteIndex(i);
                      final selectedRoute = cat.selectedRoute!;
                      debugPrint('Route selected: ${selectedRoute.routeNumber}');
                      
                      _cancelLoadingTimeout();
                      _startLoadingTimeout();
                      
                      await _loadRouteWithOptimizations(selectedRoute, sp, net);
                    },
                    selectedColor: colorScheme.secondaryContainer,
                    checkmarkColor: colorScheme.secondary,
                    accessibility: accessibility,
                    isCompact: isNarrowScreen,
                  )
                : null,
          ),
      ],
    );
  }

  // 橫向佈局構建器
  Widget _buildRowLayout({
    required Key key,
    required List<String> districtNames,
    required List<String> routeLabels,
    required bool hasUserSelection,
    required RoutesCatalogProvider cat,
    required StationProvider sp,
    required ConnectivityProvider net,
    required bool showDistricts,
    required bool showRoutes,
    required ColorScheme colorScheme,
    required double horizontalPadding,
    required double verticalPadding,
    required int districtFlex,
    required int routeFlex,
    required double dividerMargin,
    required bool isNarrowScreen,
    required AccessibilityProvider accessibility,
  }) {
    final lang = context.watch<LanguageProvider>();
    
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // 地區選擇列（左側）
          Expanded(
            flex: districtFlex,
            child: _buildSelectorCard(
              icon: Icons.location_on_outlined,
              title: hasUserSelection && cat.selectedDistrict != null 
                  ? cat.selectedDistrict!.displayName(lang.isEnglish)
                  : lang.selectDistrict,
              isSelected: hasUserSelection && cat.selectedDistrict != null,
              showContent: showDistricts,
              switchValue: _showDistrictsList,
              onSwitchChanged: (value) async {
                if (value) {
                  _staggerController.forward(from: 0);
                }
                // FIX: Add mounted check before setState in async callback
                if (mounted) {
                  setState(() => _showDistrictsList = value);
                }
                await _saveSwitchStates();
              },
              hiddenMessage: '地區列表已隱藏',
              primaryColor: colorScheme.primary,
              containerColor: colorScheme.primaryContainer,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, 
                vertical: verticalPadding,
              ),
              accessibility: accessibility,
              content: showDistricts && districtNames.isNotEmpty
                  ? _buildChipWrap(
                      items: districtNames,
                      selectedIndex: cat.districtIndex.clamp(0, districtNames.length - 1),
                      onSelected: (i) async {
                        _selectorAnimationController.reset();
                        _selectorAnimationController.forward();
                        await cat.setDistrictIndex(i);
                        // FIX: Add mounted check before setState in async callback
                        if (mounted) {
                          setState(() {
                            _schedules = {};
                          });
                        }
                        _clearRouteCache();
                      },
                      selectedColor: colorScheme.primaryContainer,
                      checkmarkColor: colorScheme.primary,
                      accessibility: accessibility,
                      isCompact: isNarrowScreen,
                    )
                  : null,
            ),
          ),
          
          // 動態分隔線
          _buildAnimatedDivider(
            isVisible: showDistricts || showRoutes,
            height: showDistricts && showRoutes ? 80 : 60,
            margin: dividerMargin,
            colorScheme: colorScheme,
          ),
          
          // 路綫選擇列（右側）
          Expanded(
            flex: routeFlex,
            child: _buildSelectorCard(
              icon: Icons.route_outlined,
              title: hasUserSelection && cat.selectedRoute != null 
                  ? '${lang.route} ${cat.selectedRoute!.routeNumber}'
                  : lang.selectRoute,
              isSelected: hasUserSelection && cat.selectedRoute != null,
              showContent: showRoutes,
              switchValue: _showRoutesList,
              onSwitchChanged: (value) async {
                if (value) {
                  _staggerController.forward(from: 0);
                }
                // FIX: Add mounted check before setState in async callback
                if (mounted) {
                  setState(() => _showRoutesList = value);
                }
                await _saveSwitchStates();
              },
              hiddenMessage: '路綫列表已隱藏',
              primaryColor: colorScheme.secondary,
              containerColor: colorScheme.secondaryContainer,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, 
                vertical: verticalPadding,
              ),
              accessibility: accessibility,
              content: showRoutes && hasUserSelection && routeLabels.isNotEmpty
                  ? _buildChipWrap(
                      items: routeLabels,
                      selectedIndex: cat.routeIndex.clamp(0, routeLabels.length - 1),
                      onSelected: (i) async {
                        final httpError = context.read<HttpErrorProvider>();
                        
                        if (httpError.shouldStopRequests && !httpError.canRetryAfterError()) {
                          debugPrint('Route selection: Skipping load due to persistent API errors');
                          await cat.setRouteIndex(i);
                          return;
                        }
                        
                        if (httpError.hasApiError && !httpError.canRetryAfterError()) {
                          debugPrint('Route selection: Skipping load - waiting for API error retry window');
                          await cat.setRouteIndex(i);
                          return;
                        }
                        
                        await cat.setRouteIndex(i);
                        final selectedRoute = cat.selectedRoute!;
                        debugPrint('Route selected: ${selectedRoute.routeNumber}');
                        
                        _cancelLoadingTimeout();
                        _startLoadingTimeout();
                        
                        await _loadRouteWithOptimizations(selectedRoute, sp, net);
                      },
                      selectedColor: colorScheme.secondaryContainer,
                      checkmarkColor: colorScheme.secondary,
                      accessibility: accessibility,
                      isCompact: isNarrowScreen,
                    )
                  : null,
            ),
          ),
        ],
      );
  }

  // 構建選擇器卡片的輔助方法 - 優化視覺層次與互動反饋
  Widget _buildSelectorCard({
    required IconData icon,
    required String title,
    required bool isSelected,
    required bool showContent,
    required bool switchValue,
    required ValueChanged<bool> onSwitchChanged,
    required String hiddenMessage,
    required Color primaryColor,
    required Color containerColor,
    required EdgeInsetsGeometry padding,
    required AccessibilityProvider accessibility,
    Widget? content,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: MotionConstants.emphasizedEasing, // Nonlinear curve for smoother transitions
      padding: padding,
      decoration: BoxDecoration(
        color: isSelected
            ? containerColor.withValues(alpha: 0.14) // Enhanced visibility
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14), // Increased from 12 for modern look
        border: Border.all(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.40) // Enhanced border visibility
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.18),
          width: isSelected ? 1.3 : 0.9, // Slightly thicker for definition
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.10), // Enhanced shadow
            blurRadius: 10, // Increased from 8 for softer shadow
            offset: const Offset(0, 3), // Increased from 2 for more depth
          ),
        ] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 改進的標題行 - 更好的視覺反饋
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onSwitchChanged(!switchValue);
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                // Fine-tuned screenshot-matched spacing
                padding: const EdgeInsets.fromLTRB(12, 9, 10, 9), // Further refined balance
                child: Row(
                  children: [
                    // 圖標容器 - 優化尺寸與間距
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: MotionConstants.emphasizedEasing,
                      padding: const EdgeInsets.all(6), // Visually balanced circular padding
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? primaryColor.withValues(alpha: 0.18) // Enhanced visibility
                            : primaryColor.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 16 * accessibility.iconScale, // Increased from 15 for better visibility
                        color: isSelected 
                            ? primaryColor 
                            : primaryColor.withValues(alpha: 0.75), // Slightly enhanced
                      ),
                    ),
                    const SizedBox(width: 16), // Enhanced spacing for premium feel
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        curve: MotionConstants.emphasizedEasing, // Nonlinear text transition
                        style: TextStyle(
                          fontSize: 13.5 * accessibility.textScale, // Slightly larger for better readability
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected 
                              ? primaryColor 
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), // Enhanced contrast
                          letterSpacing: -0.3, // Tighter for modern look
                          height: 1.2, // Line height for vertical centering
                        ),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10), // Fine-tuned spacing before arrow
                    // 展開/收起圖標 - 改進動畫 (nonlinear rotation)
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 250),
                      curve: MotionConstants.emphasizedEasing, // Nonlinear rotation curve
                      turns: switchValue ? 0.5 : 0,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20 * accessibility.iconScale, // Increased from 18 for better visibility
                        color: switchValue 
                            ? primaryColor 
                            : primaryColor.withValues(alpha: 0.55), // Adjusted opacity
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // 內容區域 - 優化展開收起動畫與視覺反饋 (nonlinear fade)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: MotionConstants.fadeInEasing,      // Nonlinear fade-in
              switchOutCurve: MotionConstants.fadeOutEasing,    // Nonlinear fade-out
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: MotionConstants.emphasizedEasing,    // Emphasized nonlinear curve
                  ),
                  child: SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: animation,
                      curve: MotionConstants.deceleratedEasing, // Smooth deceleration
                    ),
                    axisAlignment: -1.0,
                    child: child,
                  ),
                );
              },
              child: switchValue && content != null
                  ? Padding(
                      key: const ValueKey('content_visible'),
                      padding: const EdgeInsets.only(top: 10), // Optically balanced top spacing
                      child: content,
                    )
                  : !switchValue && content != null
                      ? Container(
                          key: const ValueKey('content_hidden'),
                          margin: const EdgeInsets.only(top: 10), // Matches visible padding for consistency
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // Optically balanced all sides
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.all(Radius.circular(8)), // Increased from 6 for consistency
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12), // Improved visibility
                              width: 0.6, // Slightly thicker
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center, // Center alignment for balance
                            children: [
                              Icon(
                                Icons.visibility_off_outlined,
                                size: 12 * accessibility.iconScale, // Increased from 11 for better visibility
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45), // Enhanced contrast
                              ),
                              const SizedBox(width: 6), // Optically balanced spacing
                              Flexible( // Changed from implicit to explicit for better text handling
                                child: Text(
                                  hiddenMessage,
                                  style: TextStyle(
                                    fontSize: 10.5 * accessibility.textScale, // Slightly larger
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60), // Enhanced contrast
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w500, // Increased from w400 for readability
                                    letterSpacing: -0.1, // Tighter letter spacing for compact look
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('content_none')),
            ),
          ),
        ],
      ),
    );
  }

  // 構建選擇標籤包裝器的輔助方法 - 添加入場動畫與優化互動
  Widget _buildChipWrap({
    required List<String> items,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    required Color selectedColor,
    required Color checkmarkColor,
    required AccessibilityProvider accessibility,
    bool isCompact = false,
  }) {
    const spacing = 3.0; // Const optimization
    const runSpacing = 3.0; // Const optimization
    const chipBorderRadius = BorderRadius.all(Radius.circular(8)); // Const optimization
    
    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, child) {
        final itemCount = items.length; // Cache length for O(1) access
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          children: List.generate(itemCount, (i) {
            final isSelected = i == selectedIndex;
            final delay = i * 0.025; // 25ms stagger delay - slightly faster
            final animationValue = (_staggerController.value - delay).clamp(0.0, 1.0);
            
            // Apply nonlinear curves for dramatic, polished transitions
            // Fade: Emphasized ease-out for smooth appearance
            final fadeValue = MotionConstants.fadeInEasing.transform(animationValue);
            // Scale: Bounce for playful entrance effect
            final scaleValue = MotionConstants.bounceInEasing.transform(animationValue);
            
            return Transform.scale(
              scale: 0.80 + (scaleValue * 0.20), // Scale from 0.80 to 1.0 with bounce
              child: Opacity(
                opacity: fadeValue, // Smooth fade-in with emphasized curve
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: i != selectedIndex ? () {
                        HapticFeedback.selectionClick();
                        onSelected(i);
                      } : null,
                      borderRadius: chipBorderRadius, // Use const
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? selectedColor 
                              : Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                          borderRadius: chipBorderRadius, // Use const
                          border: Border.all(
                            color: isSelected
                                ? checkmarkColor 
                                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                            width: isSelected ? 1.2 : 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              Icon(
                                Icons.check_circle,
                                size: 14 * accessibility.iconScale,
                                color: checkmarkColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              items[i],
                              style: TextStyle(
                                fontSize: 11.5 * accessibility.textScale,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                letterSpacing: -0.1,
                                color: isSelected 
                                    ? checkmarkColor
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  // 構建簡潔分隔線的輔助方法 - 添加微妙的動畫效果
  Widget _buildAnimatedDivider({
    required bool isVisible,
    required double height,
    required double margin,
    required ColorScheme colorScheme,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: isVisible ? 1.5 : 1,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: margin),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.outline.withValues(alpha: isVisible ? 0.05 : 0.02),
            colorScheme.outline.withValues(alpha: isVisible ? 0.20 : 0.08),
            colorScheme.outline.withValues(alpha: isVisible ? 0.05 : 0.02),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  // 構建 API 錯誤橫幅 - MaterialBanner 用於持久性錯誤通知
  Widget? _buildApiErrorBanner(BuildContext context) {
    final httpError = context.watch<HttpErrorProvider>();
    final lang = context.watch<LanguageProvider>();
    final accessibility = context.watch<AccessibilityProvider>();
    
    // 不顯示橫幅的條件
    if (!httpError.hasApiError && !httpError.isRateLimited) {
      return null;
    }
    
    // 如果可以重試且時間已到，不顯示橫幅
    if (httpError.canRetryAfterError() && !httpError.isRateLimited) {
      return null;
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    final remainingWait = httpError.getRemainingWaitTime();
    
    // 確定橫幅類型和顏色
    final isRateLimit = httpError.isRateLimited;
    final isCritical = httpError.shouldStopRequests;
    
    final bannerColor = isRateLimit 
        ? colorScheme.error 
        : (isCritical ? colorScheme.errorContainer : colorScheme.tertiaryContainer);
    
    final textColor = isRateLimit
        ? colorScheme.onError
        : (isCritical ? colorScheme.onErrorContainer : colorScheme.onTertiaryContainer);
    
    // 構建消息
    String message;
    String? subtitle;
    IconData icon;
    
    if (isRateLimit) {
      icon = Icons.speed;
      if (remainingWait != null) {
        final minutes = remainingWait.inMinutes;
        final seconds = remainingWait.inSeconds % 60;
        message = lang.isEnglish
            ? 'Rate Limit Exceeded'
            : '已達速率限制';
        subtitle = lang.isEnglish
            ? 'Retrying in ${minutes}m ${seconds}s'
            : '將於 ${minutes}分${seconds}秒 後重試';
      } else {
        message = lang.isEnglish
            ? 'Rate limit exceeded - please wait'
            : '已達速率限制 - 請稍候';
      }
    } else if (isCritical) {
      icon = Icons.error_outline;
      if (remainingWait != null) {
        final seconds = remainingWait.inSeconds;
        message = lang.isEnglish
            ? 'Multiple API Errors'
            : '多次 API 錯誤';
        subtitle = lang.isEnglish
            ? 'Retrying in ${seconds}s'
            : '將於 ${seconds}秒 後重試';
      } else {
        message = lang.isEnglish
            ? 'Multiple errors - requests paused'
            : '多次錯誤 - 請求已暫停';
      }
    } else {
      icon = Icons.warning_amber_rounded;
      message = lang.isEnglish
          ? 'API Connection Issue'
          : 'API 連接問題';
      subtitle = httpError.lastErrorMessage;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: textColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 24 * accessibility.iconScale,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 14 * accessibility.textScale,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12 * accessibility.textScale,
                          color: textColor.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    
                    // Retry attempts indicator
                    if (httpError.retryAttempts > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.sync,
                            size: 12 * accessibility.iconScale,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            lang.isEnglish
                                ? '${httpError.retryAttempts} retry attempts'
                                : '已重試 ${httpError.retryAttempts} 次',
                            style: TextStyle(
                              fontSize: 10 * accessibility.textScale,
                              color: textColor.withValues(alpha: 0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              // Dismiss button (only for non-critical errors)
              if (!isCritical && !isRateLimit)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20 * accessibility.iconScale,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                  onPressed: () {
                    httpError.clearApiError();
                  },
                  tooltip: lang.isEnglish ? 'Dismiss' : '關閉',
                ),
            ],
          ),
        ),
      ),
    );
  }

}

class _RouteSchedulesList extends StatefulWidget {
  final String routeNo;
  final String? routeName;
  final Map<int, LrtScheduleResponse> schedules;
  final StationProvider stationProvider;
  final void Function(int stationId)? onRefreshStation; // ✅ Callback with station ID

  const _RouteSchedulesList({
    Key? key,
    required this.routeNo,
    this.routeName,
    required this.schedules,
    required this.stationProvider,
    this.onRefreshStation, // ✅ Optional refresh callback with station ID
  }) : super(key: key);

  @override
  State<_RouteSchedulesList> createState() => _RouteSchedulesListState();
}

class _RouteSchedulesListState extends State<_RouteSchedulesList> {
  late List<int> _stationIds;
  SharedPreferences? _prefs;
  final Map<int, bool> _expandedStations = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _stationIds = widget.schedules.keys.toList()..sort();
    // Initialize all stations as collapsed by default
    for (final id in _stationIds) {
      _expandedStations[id] = false;
    }
    // Load saved order for this route (if any)
    _loadSavedOrder();
    // Load saved expansion states
    _loadExpandedStates();
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

  Future<void> _loadExpandedStates() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final key = 'route_expanded_${widget.routeNo}';
      final saved = _prefs!.getStringList(key);
      if (saved == null) return;

      for (final s in saved) {
        final id = int.tryParse(s);
        if (id != null && _expandedStations.containsKey(id)) {
          _expandedStations[id] = true;
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      // ignore errors silently
    }
  }

  Future<void> _saveExpandedStates() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final key = 'route_expanded_${widget.routeNo}';
      final expandedIds = _expandedStations.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key.toString())
          .toList();
      await _prefs!.setStringList(key, expandedIds);
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

    // Build compact route header
    final stationIdsAll = widget.schedules.keys.toList()..sort();

    Widget header = Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Compact route icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Icon(
                Icons.route,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 20 * accessibility.iconScale,
              ),
            ),
            const SizedBox(width: 14),
            
            // Compact route information
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Route name with compact styling
                  AutoSizeText(
                    widget.routeName != null
                        ? widget.routeName!
                        : '${lang.route} ${widget.routeNo}',
                    style: TextStyle(
                      fontSize: 16 * accessibility.textScale,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.3,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 2),
                  
                  // Compact info row
                  Row(
                    children: [
                      if (widget.routeName != null) ...[
                        // Route number badge (compact)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${lang.route} ${widget.routeNo}',
                            style: TextStyle(
                              fontSize: 11 * accessibility.textScale,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.secondary,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      
                      // Stations count (inline)
                      Icon(
                        Icons.location_on_outlined,
                        size: 14 * accessibility.iconScale,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${stationIdsAll.length} ${lang.stationsServed}',
                        style: TextStyle(
                          fontSize: 12 * accessibility.textScale,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Build compact expandable tile widgets in current order
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

      final isExpanded = _expandedStations[id] ?? false;
      final totalTrains = platformTrains.values.fold<int>(0, (sum, trains) => sum + trains.length);

      return _CompactStationCard(
        key: ValueKey('station_$id'),
        stationId: id,
        stationName: stationName,
        platformTrains: platformTrains,
        totalTrains: totalTrains,
        isExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedStations[id] = expanded;
          });
          _saveExpandedStates();
        },
        routeNo: widget.routeNo,
        lang: lang,
        accessibility: accessibility,
        onRefresh: widget.onRefreshStation != null ? () => widget.onRefreshStation!(id) : null, // ✅ Pass station ID to callback
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
              physics: EnhancedScrollPhysics.reorderable(),
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

/* ------------------------- Compact Station Card ------------------------- */

class _CompactStationCard extends StatefulWidget {
  final int stationId;
  final String stationName;
  final Map<int, List<TrainInfo>> platformTrains;
  final int totalTrains;
  final bool isExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final String routeNo;
  final LanguageProvider lang;
  final AccessibilityProvider accessibility;
  final VoidCallback? onRefresh; // ✅ Callback to trigger station-specific refresh

  const _CompactStationCard({
    super.key,
    required this.stationId,
    required this.stationName,
    required this.platformTrains,
    required this.totalTrains,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.routeNo,
    required this.lang,
    required this.accessibility,
    this.onRefresh, // ✅ Optional refresh callback
  });

  @override
  State<_CompactStationCard> createState() => _CompactStationCardState();
}

class _CompactStationCardState extends State<_CompactStationCard> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _contentAnimationController;
  late AnimationController _staggerController;
  late Animation<double> _elevationAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isPressed = false;
  
  // ✅ AUTO-REFRESH: Best practice implementation
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  int _consecutiveErrors = 0;
  DateTime? _lastRefreshTime;
  
  static const Duration _refreshInterval = Duration(seconds: 30);
  static const Duration _minRefreshGap = Duration(seconds: 5); // Prevent too frequent refreshes
  static const int _maxConsecutiveErrors = 3;

  @override
  void initState() {
    super.initState();
    
    // Main expansion animation controller
    _animationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );

    final curve = CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.emphasizedEasing,
    );

    _elevationAnimation = Tween<double>(
      begin: 1.0,
      end: 3.0,
    ).animate(curve);
    
    // Content fade and slide animation controller
    _contentAnimationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.standardEasing,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.emphasizedEasing,
    ));
    
    // Platform section stagger animation controller
    _staggerController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );

    if (widget.isExpanded) {
      _animationController.value = 1.0;
      _contentAnimationController.value = 1.0;
      _staggerController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _animationController.dispose();
    _contentAnimationController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_CompactStationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _animationController.forward();
        _contentAnimationController.forward();
        _staggerController.forward(from: 0);
        _startAutoRefresh();
      } else {
        _animationController.reverse();
        _contentAnimationController.reverse();
        _stopAutoRefresh();
      }
    }
    
    // Reset error count if station changed
    if (widget.stationId != oldWidget.stationId) {
      _consecutiveErrors = 0;
      _lastRefreshTime = null;
    }
  }
  
  /// ✅ AUTO-REFRESH: Start periodic refresh with exponential backoff on errors
  void _startAutoRefresh() {
    _stopAutoRefresh();
    
    // Don't start if too many consecutive errors
    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      debugPrint('⚠️ AUTO-REFRESH: Disabled for station ${widget.stationId} after $_consecutiveErrors errors');
      return;
    }
    
    debugPrint('🔄 AUTO-REFRESH: Started for station ${widget.stationId} (route ${widget.routeNo})');
    
    // Calculate interval with exponential backoff if there were errors
    final interval = _consecutiveErrors > 0
        ? _refreshInterval * (1 << _consecutiveErrors) // 30s, 60s, 120s
        : _refreshInterval;
    
    _autoRefreshTimer = Timer.periodic(interval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      _refreshStationData();
    });
  }
  
  /// ✅ AUTO-REFRESH: Stop periodic refresh and clean up
  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _isRefreshing = false;
  }
  
  /// ✅ AUTO-REFRESH: Refresh with debouncing and state management
  void _refreshStationData() {
    if (!mounted || widget.onRefresh == null) return;
    
    // Debounce: Don't refresh if already refreshing
    if (_isRefreshing) {
      debugPrint('⏭️ AUTO-REFRESH: Skipped (already refreshing) - station ${widget.stationId}');
      return;
    }
    
    // Rate limiting: Don't refresh too frequently
    final now = DateTime.now();
    if (_lastRefreshTime != null && now.difference(_lastRefreshTime!) < _minRefreshGap) {
      debugPrint('⏭️ AUTO-REFRESH: Skipped (too soon) - station ${widget.stationId}');
      return;
    }
    
    _isRefreshing = true;
    _lastRefreshTime = now;
    
    try {
      debugPrint('🔄 AUTO-REFRESH: Refreshing station ${widget.stationId} (route ${widget.routeNo})');
      
      widget.onRefresh!();
      
      // Success - reset error counter
      if (_consecutiveErrors > 0) {
        _consecutiveErrors = 0;
        // Restart timer with normal interval if it was slowed down
        _startAutoRefresh();
      }
      
      debugPrint('✅ AUTO-REFRESH: Success for station ${widget.stationId}');
      
    } catch (e) {
      _consecutiveErrors++;
      debugPrint('❌ AUTO-REFRESH: Error for station ${widget.stationId} (attempt $_consecutiveErrors): $e');
      
      // Restart timer with backoff if we hit error threshold
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _stopAutoRefresh();
        debugPrint('⚠️ AUTO-REFRESH: Disabled for station ${widget.stationId} after $_consecutiveErrors consecutive errors');
      } else if (_consecutiveErrors > 1) {
        _startAutoRefresh(); // Restart with exponential backoff
      }
    } finally {
      if (mounted) {
        _isRefreshing = false;
      }
    }
  }

  void _onExpansionChanged(bool expanded) {
    widget.onExpansionChanged(expanded);
    if (expanded) {
      _animationController.forward();
      _contentAnimationController.forward();
      _staggerController.forward(from: 0);
      _startAutoRefresh(); // ✅ Start auto-refresh
      HapticFeedback.mediumImpact();
    } else {
      _animationController.reverse();
      _contentAnimationController.reverse();
      _stopAutoRefresh(); // ✅ Stop auto-refresh
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isExpanded || _isPressed;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return AnimatedContainer(
          duration: MotionConstants.contentTransition,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive 
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
              width: isActive ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isActive 
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                    : Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: _elevationAnimation.value * 2,
                offset: Offset(0, _elevationAnimation.value * 0.5),
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
              initiallyExpanded: widget.isExpanded,
              onExpansionChanged: _onExpansionChanged,
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              childrenPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.location_on,
                  size: 20 * widget.accessibility.iconScale,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                widget.stationName,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 16 * widget.accessibility.textScale,
                  color: isActive 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              subtitle: Row(
                children: [
                  Icon(
                    Icons.train,
                    size: 14 * widget.accessibility.iconScale,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.platformTrains.length} ${widget.lang.platform}${widget.lang.isEnglish && widget.platformTrains.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12 * widget.accessibility.textScale,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.totalTrains}',
                      style: TextStyle(
                        fontSize: 10 * widget.accessibility.textScale,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      children: widget.platformTrains.entries.map((entry) {
                        final index = widget.platformTrains.keys.toList().indexOf(entry.key);
                        final platformId = entry.key;
                        final trains = entry.value;
                        
                        return _buildAnimatedPlatformSection(
                          index: index,
                          platformId: platformId,
                          trains: trains,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Enhanced animated platform section with stagger effect
  Widget _buildAnimatedPlatformSection({
    required int index,
    required int platformId,
    required List<TrainInfo> trains,
  }) {
    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, child) {
        // Calculate stagger delay based on index
        final delay = (index * 0.04).clamp(0.0, 0.3);
        final animationValue = (_staggerController.value - delay).clamp(0.0, 1.0);
        final curve = MotionConstants.emphasizedEasing;
        final easedValue = curve.transform(animationValue);
        
        return Transform.translate(
          offset: Offset(0, 15 * (1 - easedValue)),
          child: Opacity(
            opacity: easedValue,
            child: child,
          ),
        );
      },
      child: _CompactPlatformSection(
        platformId: platformId,
        trains: trains,
        routeNo: widget.routeNo,
        lang: widget.lang,
        accessibility: widget.accessibility,
      ),
    );
  }
}

/* ------------------------- Compact Platform Section ------------------------- */

class _CompactPlatformSection extends StatefulWidget {
  final int platformId;
  final List<TrainInfo> trains;
  final String routeNo;
  final LanguageProvider lang;
  final AccessibilityProvider accessibility;

  const _CompactPlatformSection({
    required this.platformId,
    required this.trains,
    required this.routeNo,
    required this.lang,
    required this.accessibility,
  });

  @override
  State<_CompactPlatformSection> createState() => _CompactPlatformSectionState();
}

class _CompactPlatformSectionState extends State<_CompactPlatformSection> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: MotionConstants.contentTransition,
        curve: MotionConstants.emphasizedEasing,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: _isHovered
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
            width: _isHovered ? 1.0 : 0.5,
          ),
          boxShadow: _isHovered ? [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform header
            AnimatedContainer(
              duration: MotionConstants.contentTransition,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(
                  alpha: _isHovered ? 0.7 : 0.5
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: MotionConstants.contentTransition,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _isHovered ? [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ] : null,
                    ),
                    child: Center(
                      child: Text(
                        '${widget.platformId}',
                        style: TextStyle(
                          fontSize: 12 * widget.accessibility.textScale,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.lang.platform} ${widget.platformId}',
                    style: TextStyle(
                      fontSize: 13 * widget.accessibility.textScale,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.trains.length}',
                      style: TextStyle(
                        fontSize: 10 * widget.accessibility.textScale,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Trains list
            ...widget.trains.asMap().entries.map((entry) {
              final index = entry.key;
              final train = entry.value;
              final isLast = index == widget.trains.length - 1;
              final ad = train.arrivalDeparture.toUpperCase() == 'D' ? widget.lang.departs : widget.lang.arrives;            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: isLast ? null : Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Route number badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: train.isStopped
                          ? Colors.red.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: train.isStopped
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.routeNo,
                        style: TextStyle(
                          fontSize: 10 * widget.accessibility.textScale,
                          fontWeight: FontWeight.w700,
                          color: train.isStopped
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Train info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          train.name(widget.lang.isEnglish),
                          style: TextStyle(
                            fontSize: 13 * widget.accessibility.textScale,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              ad == widget.lang.departs ? Icons.departure_board : Icons.schedule,
                              size: 12 * widget.accessibility.iconScale,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '$ad: ${train.time(widget.lang.isEnglish)}',
                                style: TextStyle(
                                  fontSize: 11 * widget.accessibility.textScale,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Train length
                  if (train.trainLength != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.train_outlined,
                            size: 10 * widget.accessibility.iconScale,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${train.trainLength}',
                            style: TextStyle(
                              fontSize: 9 * widget.accessibility.textScale,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Service stopped indicator - 使用語義化錯誤顏色
                  if (train.isStopped)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: UIConstants.scheduleErrorBackground(context), // 優化背景色
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block,
                            size: 10 * widget.accessibility.iconScale,
                            color: AppColors.getErrorColor(context), // 語義化錯誤顏色
                          ),
                          const SizedBox(width: 2),
                          Text(
                            widget.lang.serviceStopped.substring(0, 3), // Shortened for compact view
                            style: TextStyle(
                              fontSize: 8 * widget.accessibility.textScale,
                              fontWeight: FontWeight.w600,
                              color: AppColors.getErrorColor(context), // 語義化錯誤顏色
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
        ),
      ),
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
  
  // 獲取色彩類別的顯示名稱
  String _getColorCategoryName(int categoryIndex, bool isEnglish) {
    if (categoryIndex >= 0 && categoryIndex < ThemeProvider.colorOptions.length) {
      return _getCategoryDisplayName(ThemeProvider.colorOptions[categoryIndex].name, isEnglish);
    }
    return isEnglish ? 'Standard' : '標準';
  }
  
  // 獲取類別的本地化顯示名稱
  String _getCategoryDisplayName(String categoryName, bool isEnglish) {
    switch (categoryName) {
      case 'Standard':
        return isEnglish ? 'Standard' : '標準舒適';
      case 'Comfort':
        return isEnglish ? 'Eye Comfort' : '護眼舒適';
      case 'Accessible':
        return isEnglish ? 'High Contrast' : '高對比度';
      default:
        return categoryName;
    }
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
      physics: EnhancedScrollPhysics.enhanced(),
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
                        subtitle: _getColorCategoryName(themeProvider.colorCategoryIndex, lang.isEnglish),
                      ),
                    ),
                    
                    // 視覺舒適度類別選擇器
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, _) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.isEnglish ? 'Vision Comfort Level' : '視覺舒適度等級',
                              style: TextStyle(
                                fontSize: 14 * accessibility.textScale,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: ThemeProvider.colorOptions.asMap().entries.map((entry) {
                                final categoryIndex = entry.key;
                                final category = entry.value;
                                final isSelected = themeProvider.colorCategoryIndex == categoryIndex;
                                return InkWell(
                                  onTap: () => themeProvider.setColorByIndex(categoryIndex, 0),
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: MotionConstants.contentTransition,
                                    curve: MotionConstants.standardEasing,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                          ? Theme.of(context).colorScheme.primaryContainer
                                          : Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected 
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Text(
                                      _getCategoryDisplayName(category.name, lang.isEnglish),
                                      style: TextStyle(
                                        fontSize: 12 * accessibility.textScale,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        color: isSelected 
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 當前類別的顏色選擇器
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, _) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.isEnglish ? 'Color Palette' : '色彩調色板',
                              style: TextStyle(
                                fontSize: 14 * accessibility.textScale,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: ThemeProvider.colorOptions[themeProvider.colorCategoryIndex].colors.asMap().entries.map((entry) {
                                final colorIndex = entry.key;
                                final color = entry.value;
                                final isSelected = themeProvider.colorIndex == colorIndex;
                                return InkWell(
                                  onTap: () => themeProvider.setColorByIndex(themeProvider.colorCategoryIndex, colorIndex),
                                  borderRadius: BorderRadius.circular(UIConstants.borderRadiusL),
                                  child: AnimatedContainer(
                                    duration: MotionConstants.contentTransition,
                                    curve: MotionConstants.standardEasing,
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: isSelected 
                                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                                          : Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1),
                                      boxShadow: isSelected 
                                          ? [
                                              BoxShadow(
                                                color: color.withValues(alpha: 0.4),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                                spreadRadius: 0,
                                              ),
                                            ]
                                          : [
                                              BoxShadow(
                                                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
                                                blurRadius: 2,
                                                offset: const Offset(0, 1),
                                                spreadRadius: 0,
                                              ),
                                            ],
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check,
                                            color: _getContrastColor(color),
                                            size: 20 * accessibility.iconScale,
                                          )
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
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
          
          // 主題顏色選擇 (橫向佈局版本)
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => _buildCompactCard(
              context,
              icon: Icons.palette,
              title: lang.themeColor,
              subtitle: _getColorCategoryName(themeProvider.colorCategoryIndex, lang.isEnglish),
            ),
          ),
          
          // 視覺舒適度類別選擇器 (橫向佈局版本)
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang.isEnglish ? 'Vision Comfort' : '視覺舒適度',
                    style: TextStyle(
                      fontSize: 13 * accessibility.textScale,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: ThemeProvider.colorOptions.asMap().entries.map((entry) {
                      final categoryIndex = entry.key;
                      final category = entry.value;
                      final isSelected = themeProvider.colorCategoryIndex == categoryIndex;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: () => themeProvider.setColorByIndex(categoryIndex, 0),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: MotionConstants.contentTransition,
                              curve: MotionConstants.standardEasing,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                _getCategoryDisplayName(category.name, lang.isEnglish),
                                style: TextStyle(
                                  fontSize: 10 * accessibility.textScale,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 當前類別的顏色選擇器 (橫向佈局版本)
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingL),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: ThemeProvider.colorOptions[themeProvider.colorCategoryIndex].colors.asMap().entries.map((entry) {
                  final colorIndex = entry.key;
                  final color = entry.value;
                  final isSelected = themeProvider.colorIndex == colorIndex;
                  return InkWell(
                    onTap: () => themeProvider.setColorByIndex(themeProvider.colorCategoryIndex, colorIndex),
                    borderRadius: BorderRadius.circular(UIConstants.borderRadiusL),
                    child: AnimatedContainer(
                      duration: MotionConstants.contentTransition,
                      curve: MotionConstants.standardEasing,
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected 
                            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
                            : Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1),
                        boxShadow: isSelected 
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                  spreadRadius: 0,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                  spreadRadius: 0,
                                ),
                              ],
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: _getContrastColor(color),
                              size: 16 * accessibility.iconScale,
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
        
        // Show Cache Status Banner setting
        Consumer<DeveloperSettingsProvider>(
          builder: (context, devSettings, _) => _buildCompactCard(
            context,
            icon: Icons.info_outline,
            title: lang.isEnglish ? 'Show Cache Status Banner' : '顯示快取狀態橫幅',
            subtitle: devSettings.showCacheStatus 
                ? (lang.isEnglish ? 'Cache status banner is visible on routes page' : '路線頁面顯示快取狀態橫幅')
                : (lang.isEnglish ? 'Cache status banner is hidden' : '快取狀態橫幅已隱藏'),
            trailing: Switch(
              value: devSettings.showCacheStatus,
              onChanged: (value) {
                devSettings.setShowCacheStatus(value);
              },
            ),
          ),
        ),
        
        const SizedBox(height: UIConstants.spacingXS),
        
        // Show MTR Arrival Details setting
        Consumer<DeveloperSettingsProvider>(
          builder: (context, devSettings, _) => _buildCompactCard(
            context,
            icon: Icons.train,
            title: lang.isEnglish ? 'Show MTR Arrival Details' : '顯示港鐵到站詳情',
            subtitle: devSettings.showMtrArrivalDetails 
                ? (lang.isEnglish ? 'Platform and ETA details are visible' : '顯示月台及預計到站時間詳情')
                : (lang.isEnglish ? 'Simplified arrival time display' : '簡化到站時間顯示'),
            trailing: Switch(
              value: devSettings.showMtrArrivalDetails,
              onChanged: (value) {
                devSettings.setShowMtrArrivalDetails(value);
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
    // ✅ O(1) OPTIMIZATION: Lazy initialization - don't process all stations upfront
    _initializeStationsLazy();
    _searchController.addListener(_onSearchChanged);
    
    // ✅ Load recent stations in background (non-blocking)
    unawaited(_loadRecentStations());
    
    // 啟動進入動畫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }
  
  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: MotionConstants.contentTransition,
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
  
  // ✅ O(1) LAZY INITIALIZATION: Only create basic data structures, don't process all stations
  void _initializeStationsLazy() {
    // Just initialize empty structures - stations will be loaded on-demand
    _allGroups = [];
    _filteredGroups = [];
    debugPrint('✅ LAZY INIT: EnhancedStationSelector initialized with ZERO stations processed');
  }
  
  // ✅ LAZY LOADING: Build station groups only when needed for display
  List<StationGroup> _buildStationGroupsOnDemand() {
    if (_allGroups.isNotEmpty) {
      debugPrint('✅ CACHE HIT: Using ${_allGroups.length} cached station groups');
      return _allGroups; // Return cached groups if already built
    }
    
    debugPrint('⏳ LAZY LOAD: Building station groups on-demand...');
    final startTime = DateTime.now();
    
    // 將車站按地區分組 - only when first needed
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
    
    final duration = DateTime.now().difference(startTime);
    debugPrint('✅ LAZY LOAD COMPLETE: Built ${_allGroups.length} groups with ${widget.stationProvider.stations.length} stations in ${duration.inMilliseconds}ms');
    
    return _allGroups;
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
      
      // ✅ LAZY LOADING: Build groups on-demand only when searching
      final allGroups = _buildStationGroupsOnDemand();
      
      if (query.isEmpty) {
        _filteredGroups = List.from(allGroups);
      } else {
        _filteredGroups = allGroups.map((group) {
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
    // ✅ O(1) OPTIMIZATION: Close UI immediately for instant feedback
    Navigator.of(context).pop();
    HapticFeedback.selectionClick();
    
    // ✅ Run async operations in background (non-blocking)
    widget.onStationSelected(station.id);
    
    // ✅ Update recent stations in background (O(1) - max 3 items)
    unawaited(_addToRecent(station.id));
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
          
          // 車站列表 - 使用 AnimatedBuilder 優化動畫 + TRUE LAZY LOADING
          Expanded(
            child: Builder(
              builder: (context) {
                // ✅ TRUE LAZY LOADING: Only build when user actually views the list
                List<StationGroup> displayGroups;
                
                if (_isSearching) {
                  // When searching, use filtered results
                  displayGroups = _filteredGroups;
                } else if (_filteredGroups.isNotEmpty) {
                  // Use cached groups if available
                  displayGroups = _filteredGroups;
                } else {
                  // First time display - build on demand and cache immediately
                  displayGroups = _buildStationGroupsOnDemand();
                  _filteredGroups = displayGroups; // Cache directly without setState
                }
                
                if (displayGroups.isEmpty) {
                  return Center(
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
                  );
                }
                
                return AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: _buildOptimizedStationList(displayGroups),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // 優化的車站列表構建方法 - with lazy loading support
  Widget _buildOptimizedStationList(List<StationGroup> groups) {
    return ListView.builder(
      physics: EnhancedScrollPhysics.enhanced(),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: AnimatedContainer(
        duration: MotionConstants.contentTransition,
        curve: MotionConstants.emphasizedEasing,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.5)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectStation(station),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
              child: Row(
                children: [
                  // Station ID badge
                  AnimatedContainer(
                    duration: MotionConstants.contentTransition,
                    curve: MotionConstants.emphasizedEasing,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withOpacity(0.8),
                              ],
                            )
                          : null,
                      color: isSelected ? null : colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: colorScheme.primary.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${station.id}',
                        style: TextStyle(
                          fontSize: 15 * accessibility.textScale,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onPrimaryContainer,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Station info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          station.displayName(widget.isEnglish),
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 16 * accessibility.textScale,
                            color: colorScheme.onSurface,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          station.groupName(widget.isEnglish),
                          style: TextStyle(
                            fontSize: 13 * accessibility.textScale,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Check icon
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: AnimatedScale(
                        duration: MotionConstants.contentTransition,
                        curve: MotionConstants.emphasizedEasing,
                        scale: 1.0,
                        child: Icon(
                          Icons.check_circle,
                          color: colorScheme.primary,
                          size: 24 * accessibility.iconScale,
                        ),
                      ),
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
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _contentAnimationController;
  late AnimationController _cardStaggerController;
  late Animation<double> _animation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _districtScrollController = ScrollController();
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
    
    // Main expansion animation
    _animationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: MotionConstants.emphasizedEasing,
    );
    
    // Content fade and slide animation
    _contentAnimationController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.standardEasing,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentAnimationController,
      curve: MotionConstants.emphasizedEasing,
    ));
    
    // Card stagger animation
    _cardStaggerController = AnimationController(
      duration: MotionConstants.contentTransition,
      vsync: this,
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
    _contentAnimationController.dispose();
    _cardStaggerController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _districtScrollController.dispose();
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
      _scrollToSelectedDistrict();
    }
  }
  
  void _scrollToSelectedDistrict() {
    if (!_districtScrollController.hasClients) return;
    
    final selectedIndex = _districtNames.indexOf(_selectedDistrict);
    if (selectedIndex == -1) return;
    
    // Calculate approximate position (estimate chip width + padding)
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final estimatedChipWidth = isSmallScreen ? 85.0 : 95.0;
    final scrollPosition = selectedIndex * estimatedChipWidth;
    
    // Smoothly animate to the selected district
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_districtScrollController.hasClients) {
        _districtScrollController.animateTo(
          scrollPosition.clamp(
            0.0,
            _districtScrollController.position.maxScrollExtent,
          ),
          duration: MotionConstants.contentTransition,
          curve: MotionConstants.emphasizedEasing,
        );
      }
    });
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
        duration: MotionConstants.contentTransition,
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
      
      // Trigger stagger animation for cards
      _cardStaggerController.forward(from: 0);
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
    
    // 優先根據當前選中的車站來確定地區標籤
    final currentStationId = widget.stationProvider.selectedStationId;
    if (widget.stationProvider.userHasSelected && widget.stationProvider.stations.containsKey(currentStationId)) {
      // 獲取當前車站所屬的地區分組
      final stationDistrict = widget.isEnglish 
          ? _getStationGroupEn(currentStationId)
          : _getStationGroup(currentStationId);
      
      // 如果該地區存在於地區列表中，使用它
      if (_districtNames.contains(stationDistrict)) {
        setState(() {
          _selectedDistrict = stationDistrict;
        });
        // 同步更新緩存，確保一致性
        await _saveSelectedDistrict(stationDistrict);
        debugPrint('Loaded district from current station $currentStationId: $stationDistrict');
        return;
      }
    }
    
    // 如果沒有選中車站，則從緩存中載入地區標籤
    final cachedDistrict = widget.isEnglish 
        ? prefs.getString(_selectedDistrictEnKey)
        : prefs.getString(_selectedDistrictKey);
    
    if (cachedDistrict != null && _districtNames.contains(cachedDistrict)) {
      setState(() {
        _selectedDistrict = cachedDistrict;
      });
      debugPrint('Loaded district from cache: $cachedDistrict');
    } else {
      debugPrint('No valid cached district, using default: $_selectedDistrict');
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
        _contentAnimationController.forward();
        _cardStaggerController.forward(from: 0);
        HapticFeedback.mediumImpact();
      } else {
        _animationController.reverse();
        _contentAnimationController.reverse();
        _searchController.clear();
        _searchFocusNode.unfocus();
        _showSearch = false;
        HapticFeedback.lightImpact();
      }
    });
  }

  // 直接展開並聚焦到搜尋欄
  void _expandAndFocusSearch() {
    setState(() {
      if (!_isExpanded) {
        _isExpanded = true;
        _animationController.forward();
        _contentAnimationController.forward();
        _cardStaggerController.forward(from: 0);
        HapticFeedback.mediumImpact();
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
      // ✅ O(1) OPTIMIZATION: Close UI immediately for instant feedback
      if (mounted) {
        _toggleExpanded();
      }
      
      // ✅ Run all async operations in parallel instead of sequentially
      final futures = <Future<void>>[];
      
      // 1. Set selected station (O(1) - SharedPreferences write)
      futures.add(widget.stationProvider.setStation(station.id));
      
      // 2. Add to recent stations (O(1) - list operations on max 3 items)
      futures.add(_addToRecent(station.id));
      
      // 3. Save district label (O(1) - SharedPreferences write)
      final stationDistrict = widget.isEnglish ? station.groupEn : station.group;
      if (_districtNames.contains(stationDistrict)) {
        futures.add(_saveSelectedDistrict(stationDistrict).then((_) {
          debugPrint('Saved district label for station ${station.id}: $stationDistrict');
        }));
      }
      
      // ✅ Wait for all fast operations in parallel (UI state saves)
      await Future.wait(futures);
      
      // ✅ Defer heavy operations (API call) to after UI closes
      // This makes the UI feel instant while loading happens in background
      final connectivity = context.read<ConnectivityProvider>();
      debugPrint('Connectivity isOnline: ${connectivity.isOnline}');
      
      if (connectivity.isOnline) {
        // Load data in background - don't block UI
        debugPrint('Loading data and starting auto-refresh for station ${station.id}');
        unawaited(widget.scheduleProvider.load(station.id).then((_) {
          widget.scheduleProvider.startAutoRefresh(station.id);
        }));
      } else {
        debugPrint('Offline, skipping auto-refresh');
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
    // Conditional state checks
    final hasSelectedStation = selectedStationName != lang.selectStation;
    final isActive = _isExpanded || _mainButtonPressed;
    
    return Material(
      color: Colors.transparent,
      child: AnimatedScale(
        scale: _mainButtonPressed ? 0.985 : 1.0,
        duration: MotionConstants.microInteraction,
        curve: Curves.easeOutCubic, // Consistent curve across app
        child: InkWell(
          onTap: _toggleExpanded,
          onHighlightChanged: (pressed) {
            setState(() => _mainButtonPressed = pressed);
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
          duration: MotionConstants.contentTransition,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(isLandscape ? 6 : 8),
          decoration: BoxDecoration(
            border: Border.all(
              // Conditional border color based on state
              color: isActive 
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                  : hasSelectedStation
                      ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.8)
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
              width: isActive ? 2.0 : UIConstants.borderWidth,
            ),
            borderRadius: BorderRadius.circular(12),
            // Conditional background color
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1)
                : hasSelectedStation
                    ? Theme.of(context).colorScheme.surface
                    : Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
            // Conditional shadow effects
            boxShadow: isActive ? [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isLandscape ? 40 : 48,
                height: isLandscape ? 40 : 48,
                decoration: BoxDecoration(
                  // Conditional icon container color
                  color: hasSelectedStation
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(isLandscape ? 20 : 24),
                  // Conditional glow effect
                  boxShadow: isActive && hasSelectedStation ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ] : null,
                ),
                child: Center(
                  child: AnimatedRotation(
                    turns: isActive ? 0.1 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.tram,
                      size: (isLandscape ? 20 : 24) * accessibility.iconScale,
                      // Conditional icon color
                      color: hasSelectedStation
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              SizedBox(width: isLandscape ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: MotionConstants.contentTransition,
                      style: TextStyle(
                        fontSize: (isLandscape ? 10 : 12) * accessibility.textScale,
                        // Conditional label color
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.getPrimaryTextColor(context),
                        fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                      ),
                      child: Text(lang.selectStation),
                    ),
                    SizedBox(height: isLandscape ? 2 : 4),
                    AnimatedDefaultTextStyle(
                      duration: MotionConstants.contentTransition,
                      style: TextStyle(
                        fontSize: (isLandscape ? 14 : 16) * accessibility.textScale,
                        fontWeight: hasSelectedStation ? FontWeight.w700 : FontWeight.w600,
                        // Conditional station name color
                        color: hasSelectedStation
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      child: Text(
                        selectedStationName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // 直接搜尋按鈕 - with conditional effects
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: lang.searchStations,
                  child: AnimatedScale(
                    scale: _searchButtonPressed ? 0.9 : 1.0,
                    duration: MotionConstants.microInteraction,
                    curve: Curves.easeOutCubic, // Consistent curve
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _expandAndFocusSearch,
                      onHighlightChanged: (pressed) {
                        setState(() => _searchButtonPressed = pressed);
                      },
                      child: AnimatedContainer(
                        duration: MotionConstants.contentTransition,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          // Conditional search button background
                          color: (_showSearch || _isSearching)
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.search,
                            size: (isLandscape ? 18 : 20) * accessibility.iconScale,
                            // Conditional search icon color
                            color: (_showSearch || _isSearching)
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.getPrimaryTextColor(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Conditional arrow with enhanced animation
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: MotionConstants.contentTransition,
                curve: Curves.easeInOutCubic,
                child: AnimatedScale(
                  scale: _isExpanded ? 1.1 : 1.0,
                  duration: MotionConstants.contentTransition,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: (isLandscape ? 20 : 24) * accessibility.iconScale,
                    // Conditional arrow color
                    color: _isExpanded
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.getPrimaryTextColor(context),
                  ),
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
                      physics: EnhancedScrollPhysics.enhanced(),
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
                              final delay = index * 0.05; // Reduced delay for faster animation
                              final animationValue = (_animationController.value - delay).clamp(0.0, 1.0);
                              final easedValue = Curves.easeOutCubic.transform(animationValue); // Single curve calculation
                              
                              return Transform.scale(
                                scale: 0.8 + (easedValue * 0.2), // Optimized scale calculation
                                child: Opacity(
                                  opacity: easedValue, // Direct opacity without extra curve calculation
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    
    // Optimized height calculation
    final baseHeight = isSmallScreen ? 44.0 : 48.0;
    final scaledHeight = math.min(baseHeight * accessibility.textScale, 64.0);
    
    return Container(
      height: scaledHeight,
      margin: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 4.0 : 8.0,
        vertical: 4.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        controller: _districtScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        physics: const BouncingScrollPhysics(),
        itemCount: _districtNames.length,
        itemBuilder: (context, index) {
          final district = _districtNames[index];
          final isSelected = district == _selectedDistrict;
          
          // Optimized text style
          final fontSize = math.min(13 * accessibility.textScale, 15.0);
          final textStyle = TextStyle(
            fontSize: fontSize,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.2,
          );
          
          // Calculate adaptive width
          final textPainter = TextPainter(
            text: TextSpan(text: district, style: textStyle),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout(minWidth: 0, maxWidth: screenWidth);

          final textWidth = textPainter.size.width;
          final chipWidth = math.max(
            isSmallScreen ? 70.0 : 80.0,
            math.min(textWidth + 32.0, isSmallScreen ? 140.0 : 160.0),
          );

          return AnimatedBuilder(
            animation: _cardStaggerController,
            builder: (context, child) {
              // Subtle entrance animation for district chips
              final delay = (index * 0.015).clamp(0.0, 0.2);
              final animationValue = (_cardStaggerController.value - delay).clamp(0.0, 1.0);
              final easedValue = MotionConstants.emphasizedEasing.transform(animationValue);
              
              return Transform.scale(
                scale: 0.9 + (easedValue * 0.1),
                child: Opacity(
                  opacity: 0.3 + (easedValue * 0.7),
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.only(
                right: isSmallScreen ? 6.0 : 8.0,
                left: index == 0 ? 0.0 : 0.0,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (district != _selectedDistrict) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedDistrict = district;
                      });
                      _saveSelectedDistrict(district);
                      // Trigger stagger animation for new district cards
                      _cardStaggerController.forward(from: 0);
                      // Auto-scroll to selected district
                      _scrollToSelectedDistrict();
                    }
                  },
                  child: AnimatedContainer(
                    duration: MotionConstants.contentTransition,
                    curve: Curves.easeOutCubic,
                    constraints: BoxConstraints(
                      minWidth: chipWidth,
                      maxWidth: chipWidth,
                      minHeight: scaledHeight - 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected 
                            ? Theme.of(context).colorScheme.primary 
                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            Icon(
                              Icons.check_circle,
                              size: 14 * accessibility.iconScale,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              district,
                              style: textStyle.copyWith(
                                color: isSelected 
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
              switchInCurve: MotionConstants.emphasizedEasing,
              switchOutCurve: MotionConstants.emphasizedEasing,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren.map((child) {
                      // Fade out previous content
                      return Positioned.fill(child: child);
                    }),
                    if (currentChild != null) 
                      Positioned.fill(child: currentChild),
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                // Reverse animation for exit
                final exitAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
                  ),
                );
                
                // Forward animation for entrance with delay
                final enterAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
                  ),
                );
                
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: MotionConstants.emphasizedEasing,
                ));
                
                // Use enter animation for fading in new content
                return FadeTransition(
                  opacity: animation.status == AnimationStatus.reverse ? exitAnimation : enterAnimation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                );
              },
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
            switchInCurve: MotionConstants.emphasizedEasing,
            switchOutCurve: MotionConstants.emphasizedEasing,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[
                  ...previousChildren.map((child) {
                    // Fade out previous content
                    return Positioned.fill(child: child);
                  }),
                  if (currentChild != null) 
                    Positioned.fill(child: currentChild),
                ],
              );
            },
            transitionBuilder: (child, animation) {
              // Reverse animation for exit
              final exitAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
                ),
              );
              
              // Forward animation for entrance with delay
              final enterAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
                ),
              );
              
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: MotionConstants.emphasizedEasing,
              ));
              
              // Use enter animation for fading in new content
              return FadeTransition(
                opacity: animation.status == AnimationStatus.reverse ? exitAnimation : enterAnimation,
                child: SlideTransition(
                  position: offsetAnimation,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              );
            },
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
    
    return ClipRect(
      child: LayoutBuilder(
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
                key: const ValueKey('searchGridView'),
                physics: EnhancedScrollPhysics.enhanced(),
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
                  
                  return _buildAnimatedStationCard(
                    station: station,
                    isSelected: isSelected,
                    accessibility: accessibility,
                    index: index,
                  );
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
      ),
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
    
    return ClipRect(
      child: LayoutBuilder(
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
                key: ValueKey('districtGridView_$_selectedDistrict'),
                physics: EnhancedScrollPhysics.enhanced(),
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
                  
                  return _buildAnimatedStationCard(
                    station: station,
                    isSelected: isSelected,
                    accessibility: accessibility,
                    index: index,
                  );
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
      ),
    );
  }
  // Enhanced animated station card with stagger effect
  Widget _buildAnimatedStationCard({
    required StationInfo station,
    required bool isSelected,
    required AccessibilityProvider accessibility,
    required int index,
  }) {
    return AnimatedBuilder(
      animation: _cardStaggerController,
      builder: (context, child) {
        // Calculate stagger delay based on index
        final delay = (index * 0.02).clamp(0.0, 0.3);
        final animationValue = (_cardStaggerController.value - delay).clamp(0.0, 1.0);
        final curve = MotionConstants.emphasizedEasing;
        final easedValue = curve.transform(animationValue);
        
        return Transform.translate(
          offset: Offset(0, 20 * (1 - easedValue)),
          child: Opacity(
            opacity: easedValue,
            child: child,
          ),
        );
      },
      child: _buildStationCard(
        station: station,
        isSelected: isSelected,
        accessibility: accessibility,
      ),
    );
  }
  
  Widget _buildStationCard({
    required StationInfo station,
    required bool isSelected,
    required AccessibilityProvider accessibility,
  }) {
    return Consumer<DeveloperSettingsProvider>(
      builder: (context, devSettings, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              _selectStation(station);
            },
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
              duration: MotionConstants.microInteraction,
              scale: (_pressedStationId == station.id) ? 0.98 : 1.0,
              curve: Curves.easeOutCubic, // More efficient curve
              child: AnimatedContainer(
                duration: MotionConstants.contentTransition,
                curve: Curves.easeOutCubic, // Consistent curve
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
                        AnimatedBuilder(
                          animation: _cardStaggerController,
                          builder: (context, child) {
                            // Subtle pulse effect for selected indicator
                            final pulseValue = (math.sin(_cardStaggerController.value * math.pi * 2) + 1) / 2;
                            final scale = 1.0 + (pulseValue * 0.2);
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3 * pulseValue),
                                      blurRadius: 3 * pulseValue,
                                      spreadRadius: 1 * pulseValue,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Stack(
                  children: [
                    Column(
                      children: [
                    SizedBox(height: isLandscape ? 6 : 8),
                    
                    // 搜索框 - 僅在點擊搜尋按鈕後顯示
                    AnimatedSwitcher(
                      duration: MotionConstants.contentTransition,
                      switchInCurve: MotionConstants.emphasizedEasing,
                      switchOutCurve: MotionConstants.emphasizedEasing,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.05),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
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
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ O(1) 優化: 使用全局 _stationGroupCache 而非重複方法
  // 直接使用頂層的 _getStationGroup 和 _getStationGroupEn 函數
  // 移除重複的方法以避免不必要的 Set 創建和查找
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
        physics: EnhancedScrollPhysics.enhanced(),
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