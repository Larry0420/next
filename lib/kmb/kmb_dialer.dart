import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lrt_next_train/optionalMarquee.dart';
import 'package:lrt_next_train/toTitleCase.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import '../kmb_route_status_page.dart';
import '../main.dart' show LanguageProvider;

import 'api/citybus.dart';
import 'api/kmb.dart';


class KmbDialer extends StatefulWidget {
  final void Function(String route)? onRouteSelected;
  // When true the dialer is positioned to favor right-hand one-handed use.
  final bool rightHanded;
  const KmbDialer({super.key, this.onRouteSelected, this.rightHanded = true});

  @override
  State<KmbDialer> createState() => _KmbDialerState();
}

class _KmbDialerState extends State<KmbDialer> {
  String input = '';
  List<String> routes = [];
  List<Map<String, dynamic>> searchResults = [];
  bool loading = false;
  String? error;
  Map<String, List<Map<String, dynamic>>>? _routeMap;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    setState(() { loading = true; error = null; });
    try {
      routes = await Kmb.fetchRoutes();
      // Start loading route->stops map in background so we can show bound/direction metadata
      Kmb.buildRouteToStopsMap().then((m) {
        setState(() { _routeMap = m; });
      }).catchError((_) {
        // ignore silently; directions are optional
      });
      // Also build the enhanced route index for better searching
      unawaited(Kmb.buildRouteIndex().catchError((_) {
        // ignore silently; enhanced search is optional
        return <String, Map<String, dynamic>>{};
      }));
    } catch (e) {
      error = e.toString();
    }
    setState(() { loading = false; });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { searchResults = []; });
      return;
    }

    try {
      final results = await Kmb.searchRoutes(query);
      
      // If no results from enhanced search, fall back to simple filtering
      if (results.isEmpty) {
        final filtered = routes.where((r) => r.toUpperCase().startsWith(query.toUpperCase())).toList();
        setState(() {
          searchResults = filtered.map((route) => {'route': route, 'search_text': route.toLowerCase()}).toList();
        });
        return;
      }
      
      // Group results by route number to combine inbound/outbound variants
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final result in results) {
        final route = result['route'] as String;
        grouped.putIfAbsent(route, () => []).add(result);
      }
      
      // Deduplicate variants by unique bound+serviceType combination and ensure origin/dest data
      final List<Map<String, dynamic>> enrichedResults = [];
      grouped.forEach((route, variants) {
        // Deduplicate by unique bound_serviceType key
        final Map<String, Map<String, dynamic>> uniqueVariants = {};
        for (final variant in variants) {
          final bound = variant['bound'] ?? '';
          final serviceType = variant['service_type'] ?? '';
          final key = '${bound}_$serviceType';
          
          // Keep the first occurrence or one with better data
          if (!uniqueVariants.containsKey(key)) {
            uniqueVariants[key] = variant;
          } else {
            // If new variant has origin/dest data and current doesn't, replace
            final current = uniqueVariants[key]!;
            final hasOrig = (variant['orig_en']?.toString().isNotEmpty ?? false) || 
                           (variant['orig_tc']?.toString().isNotEmpty ?? false);
            final hasDest = (variant['dest_en']?.toString().isNotEmpty ?? false) || 
                           (variant['dest_tc']?.toString().isNotEmpty ?? false);
            final currentHasOrig = (current['orig_en']?.toString().isNotEmpty ?? false) || 
                                  (current['orig_tc']?.toString().isNotEmpty ?? false);
            final currentHasDest = (current['dest_en']?.toString().isNotEmpty ?? false) || 
                                  (current['dest_tc']?.toString().isNotEmpty ?? false);
            
            if ((hasOrig && hasDest) && !(currentHasOrig && currentHasDest)) {
              uniqueVariants[key] = variant;
            }
          }
        }
        
        enrichedResults.addAll(uniqueVariants.values);
      });
      
      setState(() { searchResults = enrichedResults; });
    } catch (e) {
      // If enhanced search fails, fall back to simple filtering
      final filtered = routes.where((r) => r.toUpperCase().startsWith(query.toUpperCase())).toList();
      setState(() {
        searchResults = filtered.map((route) => {'route': route, 'search_text': route.toLowerCase()}).toList();
      });
    }
  }

  void _onKeyTap(String value) {
    setState(() {
      input += value;
      _performSearch(input);
    });
  }

  void _onBackspace() {
    setState(() {
      if (input.isNotEmpty) input = input.substring(0, input.length - 1);
      _performSearch(input);
    });
  }

  // Return a human-friendly direction label for a given route (e.g. 'Outbound', 'Inbound', or 'Inbound & Outbound').
  String? _directionLabelForRoute(String route) {
    if (_routeMap == null) return null;
    final r = route.trim().toUpperCase();
    final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
    final entries = _routeMap![r] ?? _routeMap![base] ?? [];
    if (entries.isEmpty) return null;

    String? normChar(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim().toUpperCase();
      if (s.isEmpty) return null;
      final c = s[0];
      if (c == 'I' || c == 'O') return c;
      return null;
    }

    final Set<String> dirs = {};
    for (final e in entries) {
      final b = normChar(e['bound']);
      if (b != null) dirs.add(b);
      if (dirs.length == 2) break;
    }
    if (dirs.isEmpty) return null;
    if (dirs.length == 2) return 'Inbound & Outbound';
    final only = dirs.first;
    return only == 'I' ? 'Inbound' : 'Outbound';
  }

  // Try to extract destination metadata for a route from the cached route->stops map.
  // Prefers English name when `isEnglish` is true, otherwise Traditional Chinese.
  String? _destinationForRoute(String route, bool isEnglish) {
    if (_routeMap == null) return null;
    final r = route.trim().toUpperCase();
    final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
    final entries = _routeMap![r] ?? _routeMap![base] ?? [];
    if (entries.isEmpty) return null;

    for (final e in entries) {
      // Accept common key variants: desten, desttc, dest
      final destEn = (e['desten'] ?? e['dest_en'] ?? e['dest'])?.toString();
      final destTc = (e['desttc'] ?? e['dest_tc'] ?? e['dest'])?.toString();
      if (isEnglish && destEn != null && destEn.isNotEmpty) return destEn;
      if (!isEnglish && destTc != null && destTc.isNotEmpty) return destTc;
      // fallback to whichever is present
      if (destEn != null && destEn.isNotEmpty) return destEn;
      if (destTc != null && destTc.isNotEmpty) return destTc;
    }
    return null;
  }

  // Return destination for a specific bound (e.g. 'O' or 'I').
  String? _destinationForRouteBound(String route, String bound, bool isEnglish) {
    if (_routeMap == null) return null;
    final r = route.trim().toUpperCase();
    final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1) ?? r;
    final entries = _routeMap![r] ?? _routeMap![base] ?? [];
    if (entries.isEmpty) return null;

    for (final e in entries) {
      final eb = (e['bound'] == null) ? null : e['bound'].toString().toUpperCase();
      if (eb == null || eb.isEmpty) continue;
      if (eb[0] != bound) continue;
      final destEn = (e['desten'] ?? e['dest_en'] ?? e['dest'])?.toString();
      final destTc = (e['desttc'] ?? e['dest_tc'] ?? e['dest'])?.toString();
      if (isEnglish && destEn != null && destEn.isNotEmpty) return destEn;
      if (!isEnglish && destTc != null && destTc.isNotEmpty) return destTc;
      if (destEn != null && destEn.isNotEmpty) return destEn;
      if (destTc != null && destTc.isNotEmpty) return destTc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<LanguageProvider>();
  final displayRoutes = input.isEmpty ? <Map<String, dynamic>>[] : searchResults;
  // Extract base for grouping: letter prefix (if any) + digits, e.g., 'N' from 'N170', '11' from '11A'
  final baseFromInput = RegExp(r'^([A-Z]?\d+)').firstMatch(input)?.group(1);
    // We'll use a Stack so the dialer can float in a one-handed position
    return Stack(
      children: [
        // Main column holds header and (conditionally visible) routes list
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(lang.isEnglish ? 'Enter Route:' : '輸入路線:', style: const TextStyle(fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(input, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),

            // status indicators
            if (loading) const Center(child: CircularProgressIndicator(year2023: false,)),
            if (error != null) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Text('${lang.isEnglish ? "Error" : "錯誤"}: $error', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _fetchRoutes,
                    child: Text(lang.isEnglish ? 'Retry' : '重試'),
                  ),
                ],
              ),
            ),

            /// AnimatedSwitcher for the routes list: hidden when input is empty
            // AnimatedSwitcher for the routes list: hidden when input is empty
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: (!loading && error == null && input.isNotEmpty)
                  ? LayoutBuilder(
                      key: const ValueKey('routes_list'),
                      builder: (context, constraints) {
                        final theme = Theme.of(context);
                        // Cap the list height to avoid overflow on tall/narrow screens (like 18:9)
                        final maxHeight = MediaQuery.of(context).size.height * 0.38;
                        
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: Builder(builder: (_) {
                            // --- Group Logic ---
                            final Map<String, List<Map<String, dynamic>>> groups = {};
                            final baseRe = RegExp(r'^([A-Z]?\d+)');
                            for (final routeData in displayRoutes) {
                              final route = routeData['route'] as String;
                              final m = baseRe.firstMatch(route);
                              final base = m != null ? m.group(1)! : route;
                              groups.putIfAbsent(base, () => []).add(routeData);
                            }

                            // --- Sorting Logic ---
                            final sortedBases = groups.keys.toList()
                              ..sort((a, b) {
                                final aMatch = RegExp(r'^([A-Z]?)(\d+)').firstMatch(a);
                                final bMatch = RegExp(r'^([A-Z]?)(\d+)').firstMatch(b);
                                if (aMatch == null || bMatch == null) return a.compareTo(b);
                                
                                final aPrefix = aMatch.group(1) ?? '';
                                final bPrefix = bMatch.group(1) ?? '';
                                final aNum = int.tryParse(aMatch.group(2) ?? '0') ?? 0;
                                final bNum = int.tryParse(bMatch.group(2) ?? '0') ?? 0;
                                
                                if (aPrefix.isNotEmpty && bPrefix.isNotEmpty) {
                                  final prefixCmp = aPrefix.compareTo(bPrefix);
                                  if (prefixCmp != 0) return prefixCmp;
                                  return aNum.compareTo(bNum);
                                }
                                if (aPrefix.isNotEmpty) return -1;
                                if (bPrefix.isNotEmpty) return 1;
                                return aNum.compareTo(bNum);
                              });

                            final isEnglish = lang.isEnglish;
                            final List<Widget> tiles = [];

                            for (final base in sortedBases) {
                              final variants = groups[base]!..sort((x, y) {
                                final routeX = x['route'] as String;
                                final routeY = y['route'] as String;
                                if (routeX == base && routeY != base) return -1;
                                if (routeY == base && routeX != base) return 1;
                                return routeX.compareTo(routeY);
                              });

                              // --- Case 1: Single Variant ---
                              if (variants.length == 1) {
                                final routeData = variants.first;
                                final route = routeData['route'] as String;
                                
                                // 獲取所有相關變體 (處理搜尋結果中同一路線的多個方向)
                                final routeVariants = displayRoutes.where((r) => r['route'] == route).toList();

                                tiles.add(
                                  Card.filled(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    clipBehavior: Clip.hardEdge,
                                    child: _buildRouteContent(
                                      context, 
                                      route: route, 
                                      variants: routeVariants, 
                                      isEnglish: isEnglish,
                                      input: input
                                    ),
                                  ),
                                );
                                continue;
                              }

                              // --- Case 2: Grouped Variants (ExpansionTile) ---
                              tiles.add(
                                Card.filled(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  clipBehavior: Clip.hardEdge,
                                  child: ExpansionTile(
                                    shape: const Border(), // M3: 移除邊框
                                    collapsedShape: const Border(),
                                    backgroundColor: theme.colorScheme.surfaceContainer, // 展開後的背景色
                                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    
                                    title: Text(
                                      '$base (${variants.length})', 
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      )
                                    ),
                                    
                                    // 自動展開邏輯
                                    initiallyExpanded: baseFromInput == base || sortedBases.length == 1,
                                    
                                    children: variants.map((routeData) {
                                      final route = routeData['route'] as String;
                                      // 這裡直接復用 _buildRouteContent 來處理子項目的複雜顯示邏輯
                                      // 注意：我們只傳入單個 variant，因為在展開列表中每個項目都是獨立的
                                      return _buildRouteContent(
                                        context,
                                        route: route,
                                        variants: [routeData],
                                        isEnglish: isEnglish,
                                        input: input,
                                      );
                                    }).toList(),
                                  ),
                                ),
                              );
                            }

                            if (tiles.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'No routes found',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.outline
                                    )
                                  ),
                                )
                              );
                            }

                            return ListView(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: tiles
                            );
                          }),
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),


            const SizedBox(height: 24), // smaller spacer to reduce overall vertical footprint
          ],
        ),

        // Floating one-hand dialer positioned bottom-left or bottom-right depending on handedness
        Positioned(
          left: widget.rightHanded ? null : 12,
          right: widget.rightHanded ? 12 : null,
          // Position above system navigation / safe area
          bottom: MediaQuery.of(context).padding.bottom + 12,
          child: _OneHandDialerContainer(
            child: _buildDialer(),
          ),
        ),
      ],
    );
  }
  // --- Helper Methods ---

  /// 構建路由卡片內部的具體內容 (處理單一變體與多目的地邏輯)
  Widget _buildRouteContent(
    BuildContext context, {
    required String route,
    required List<Map<String, dynamic>> variants,
    required bool isEnglish,
    required String input,
  }) {
    final theme = Theme.of(context);
    final List<Widget> tiles = [];

    // 1. 按目的地分組 (處理循環線與不同服務類型)
    final Map<String, List<Map<String, dynamic>>> routesByDestination = {};
    for (final variant in variants) {
      // 這裡做了安全處理，確保 null 值轉為空字串
      final orig = isEnglish 
          ? (variant['orig_en']?.toString().trim() ?? variant['orig_tc']?.toString().trim() ?? '')
          : (variant['orig_tc']?.toString().trim() ?? variant['orig_en']?.toString().trim() ?? '');
      final dest = isEnglish
          ? (variant['dest_en']?.toString().trim() ?? variant['dest_tc']?.toString().trim() ?? '')
          : (variant['dest_tc']?.toString().trim() ?? variant['dest_en']?.toString().trim() ?? '');
      
      final key = '$orig→$dest';
      routesByDestination.putIfAbsent(key, () => []).add(variant);
    }

    // 2. 判斷顯示模式
    // 如果有多個不同的目的地組合，或同一目的地有多個服務類型，則全部列出
    if (routesByDestination.length > 1 || (routesByDestination.length == 1 && routesByDestination.values.first.length > 1)) {
      
      for (final destEntry in routesByDestination.entries) {
        final destVariants = destEntry.value;

        for (final variant in destVariants) {
          final bound = variant['bound'] as String?;
          final serviceType = variant['service_type'] as String?;
          final direction = variant['direction'] as String?;

          // 重新提取一次 orig/dest 供顯示使用 (邏輯同上)
          final orig = isEnglish 
              ? (variant['orig_en']?.toString().trim() ?? variant['orig_tc']?.toString().trim() ?? '')
              : (variant['orig_tc']?.toString().trim() ?? variant['orig_en']?.toString().trim() ?? '');
          final dest = isEnglish
              ? (variant['dest_en']?.toString().trim() ?? variant['dest_tc']?.toString().trim() ?? '')
              : (variant['dest_tc']?.toString().trim() ?? variant['dest_en']?.toString().trim() ?? '');

          // 生成副標題
          String subtitleText;
          if (orig.isNotEmpty && dest.isNotEmpty) {
            final isCircular = (variant['orig_en'] == variant['dest_en'] && variant['orig_en'] != null) ||
                                (variant['orig_tc'] == variant['dest_tc'] && variant['orig_tc'] != null);
            
            if (isCircular) {
              final dirLabel = bound == 'O' 
                ? (isEnglish ? 'Outbound (Circular)' : '往程（循環線）')
                : bound == 'I'
                  ? (isEnglish ? 'Inbound (Circular)' : '返程（循環線）')
                  : (isEnglish ? 'Circular' : '循環線');
              subtitleText = serviceType != null && serviceType != '1' 
                ? '$dirLabel - Type $serviceType' : dirLabel;
            } else {
              subtitleText = serviceType != null && serviceType != '1'
                ? '$orig → $dest (Type $serviceType)'
                : '$orig → $dest';
            }
          } else {
            // Fallback: 如果沒有目的地資料，嘗試用方向或 bound
            final dirLabel = bound == 'O' 
              ? (isEnglish ? 'Outbound' : '往程')
              : bound == 'I' ? (isEnglish ? 'Inbound' : '返程') : (direction ?? '');
            subtitleText = serviceType != null && serviceType != '1'
              ? '$dirLabel (Type $serviceType)' : dirLabel;
          }

          tiles.add(_buildM3ListTile(
            context,
            title: _buildHighlightedText(route, input, theme),
            subtitle: Text(subtitleText),
            onTap: () {
              final r = route.toUpperCase();
              // 導航到狀態頁面
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => KmbRouteStatusPage(route: r, bound: bound, serviceType: serviceType)
              ));
              widget.onRouteSelected?.call(r);
            },
          ));
        }
      }
    } else {
      // 3. Fallback: 只有單一變體，顯示基本資訊
      final variant = variants.first;
      final bound = variant['bound'] as String?;
      // 服務類型處理
      final serviceType = variant['service_type'] as String?;
      final hasServiceType = serviceType != null && serviceType != '1';
      
      // 提取變數
      final origRaw = isEnglish 
          ? (variant['orig_en']?.toString().trim() ?? variant['orig_tc']?.toString().trim() ?? '')
          : (variant['orig_tc']?.toString().trim() ?? variant['orig_en']?.toString().trim() ?? '');
      final destRaw = isEnglish
          ? (variant['dest_en']?.toString().trim() ?? variant['dest_tc']?.toString().trim() ?? '')
          : (variant['dest_tc']?.toString().trim() ?? variant['dest_en']?.toString().trim() ?? '');

      // 套用 TitleCase (僅英文模式)
      final orig = isEnglish ? origRaw.toTitleCase() : origRaw;
      final dest = isEnglish ? destRaw.toTitleCase() : destRaw;
      
      // 構建子項目
      return _buildM3ListTile(
        context,
        title: _buildHighlightedText(route, input, Theme.of(context)),
        // 使用自定義的 Rich Subtitle Widget
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：起訖點佈局
              if (orig.isNotEmpty && dest.isNotEmpty)
                Row(
                  children: [
                    Flexible(
                      child: OptionalMarquee(
                        text: orig, 
                        style: TextStyle(letterSpacing: -0.05, fontSize: 12, fontWeight: FontWeight.w400,
                                      // height: 0, // ❌ 移除
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.88),
                                    ),)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
                    ),
                    Flexible(
                      child: OptionalMarquee(
                        text: dest, 
                        style: TextStyle(letterSpacing: -0.05, fontSize: 12, fontWeight: FontWeight.w400,
                                      // height: 0, // ❌ 移除
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.88),
                                    ),)),
                  ],
                )
              else
                Text(isEnglish ? "View Route" : "查看路線"),

              // 第二行：服務類型標籤 (如果有)
              if (hasServiceType)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isEnglish ? 'Special Departures($serviceType)' : '特別班次($serviceType)', // 或根據語言顯示 '類別 $serviceType'
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        onTap: () {
          final r = route.toUpperCase();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => KmbRouteStatusPage(route: r, bound: bound, serviceType: serviceType)
          ));
          widget.onRouteSelected?.call(r);
        },
        );
      }
      /*
      // 這裡簡化顯示：如果有資料就顯示起訖點，否則顯示方向
      String subtitleText = (orig.isNotEmpty && dest.isNotEmpty)
          ? "$orig → $dest" 
          : (isEnglish ? "View Route" : "查看路線");

      tiles.add(_buildM3ListTile(
        context,
        title: _buildHighlightedText(route, input, theme),
        subtitle: Text(subtitleText),
        onTap: () {
          final r = route.toUpperCase();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => KmbRouteStatusPage(route: r, bound: bound, serviceType: serviceType)
          ));
          widget.onRouteSelected?.call(r);
        },
      ));
    } */
    
    // 如果有多個 Tile，添加 M3 風格的分隔線
    if (tiles.length > 1) {
      final separatedTiles = <Widget>[];
      for (int i = 0; i < tiles.length; i++) {
        separatedTiles.add(tiles[i]);
        if (i < tiles.length - 1) {
          separatedTiles.add(Divider(
            height: 1, 
            thickness: 0.5, 
            indent: 16, 
            endIndent: 16, 
            color: theme.colorScheme.outlineVariant.withOpacity(0.5)
          ));
        }
      }
      return Column(children: separatedTiles);
    }

    return Column(children: tiles);
  }

  /// 標準 Material 3 風格的 ListTile
  Widget _buildM3ListTile(BuildContext context, {
    required Widget title, 
    Widget? subtitle, 
    required VoidCallback onTap
  }) {
    final theme = Theme.of(context);
    return ListTile(
      visualDensity: VisualDensity.compact, // 緊湊視圖
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      title: title,
      subtitle: subtitle != null ? DefaultTextStyle(
        style: theme.textTheme.bodySmall!.copyWith(
          color: theme.colorScheme.onSurfaceVariant
        ),
        child: subtitle
      ) : null,
      trailing: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // 點擊水波紋圓角
    );
  }

  /// 支援搜尋關鍵字高亮的文字組件
  Widget _buildHighlightedText(String text, String query, ThemeData theme) {
    if (query.isEmpty) return Text(text);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    
    if (!lowerText.contains(lowerQuery)) {
      return Text(text);
    }

    final startIndex = lowerText.indexOf(lowerQuery);
    final endIndex = startIndex + lowerQuery.length;

    return Text.rich(
      TextSpan(
        style: TextStyle(color: theme.colorScheme.onSurface), // 預設文字顏色
        children: [
          TextSpan(text: text.substring(0, startIndex)),
          TextSpan(
            text: text.substring(startIndex, endIndex),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary, // 高亮顏色使用 Primary
            ),
          ),
          TextSpan(text: text.substring(endIndex)),
        ],
      ),
    );
  }


  Widget _buildDialer() {
    final theme = Theme.of(context);
    // Build next possible keys based on actual routes and current input.
    // Avoid substring/index errors by using startsWith and checking lengths.
    final Set<String> nextKeys = {};

    final inputUpper = input.toUpperCase();
    for (final route in routes) {
      final routeUpper = route.toUpperCase();
      if (!routeUpper.startsWith(inputUpper)) continue;
      // If route equals input exactly, no next key from this route
      if (routeUpper.length == inputUpper.length) continue;
      // The next character after the input is a valid next key (digit or letter)
      final nextChar = route[input.length].toUpperCase();
      nextKeys.add(nextChar);
    }

    // When input is empty, show ALL possible first characters (letters and digits)
    // This allows users to start with B, N, A, E, etc. for special routes
    List<String> keys;
    if (input.isEmpty) {
      // Show both letters (like B, N, A, E) and digits as first-character options
      keys = nextKeys.toList()..sort((a, b) {
        // Sort: letters first (alphabetically), then digits (numerically)
        final aIsDigit = RegExp(r'^\d$').hasMatch(a);
        final bIsDigit = RegExp(r'^\d$').hasMatch(b);
        if (!aIsDigit && bIsDigit) return -1; // letters before digits
        if (aIsDigit && !bIsDigit) return 1;  // digits after letters
        if (aIsDigit && bIsDigit) return int.parse(a).compareTo(int.parse(b));
        return a.compareTo(b); // both letters: alphabetical
      });
    } else {
      // After first character, show all next possible keys (letters and digits)
      keys = nextKeys.toList()..sort((a, b) {
        final aIsDigit = RegExp(r'^\d$').hasMatch(a);
        final bIsDigit = RegExp(r'^\d$').hasMatch(b);
        if (aIsDigit && bIsDigit) return int.parse(a).compareTo(int.parse(b));
        if (!aIsDigit && !bIsDigit) return a.compareTo(b);
        // Mix of digits and letters: digits first for easier typing
        if (aIsDigit) return -1;
        return 1;
      });
    }

    // Separate keys into digits and letters/specials
    final List<String> digits = keys.where((k) => RegExp(r'^\d$').hasMatch(k)).toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    final List<String> letters = keys.where((k) => !RegExp(r'^\d$').hasMatch(k)).toList()..sort();
    final String backKey = '<';
    final String okKey = 'OK';

    const double btnSize = 48.0;
    const double gap = 8.0;

    // Build 4x3 grid (4 rows x 3 columns) for digits. Fill with placeholders if missing.
    final List<List<String>> digitGrid = List.generate(4, (_) => List.filled(3, ''));
    for (int i = 0; i < digits.length && i < 12; i++) {
      final r = i ~/ 3;
      final c = i % 3;
      digitGrid[r][c] = digits[i];
    }

    // Place backspace and OK in the bottom of the first column if space allows
    if (digits.length < 12) {
      // if there's a free slot, put back and ok
      final idx = digits.length;
      if (idx < 12) {
        final r = idx ~/ 3;
        final c = idx % 3;
        digitGrid[r][c] = backKey;
        if (idx + 1 < 12) {
          final r2 = (idx + 1) ~/ 3;
          final c2 = (idx + 1) % 3;
          digitGrid[r2][c2] = okKey;
        }
      }
    } else {
      // fallback: ensure back/ok exist in letters column
    }

    // Build UI: digits grid on left, letters column on right
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Digit grid
          Column(
            mainAxisSize: MainAxisSize.min,
            children: digitGrid.map((row) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: row.map((key) {
                  final bool isEmpty = key.isEmpty;
                  return Padding(
                    padding: const EdgeInsets.all(gap / 2),
                    child: SizedBox(
                      width: btnSize,
                      height: btnSize,
                      child: isEmpty
                          ? const SizedBox.shrink()
                          : ElevatedButton(
                              onPressed: () {
                                if (key == backKey) {
                                  _onBackspace();
                                } else if (key == okKey) {
                                  if (routes.contains(input)) {
                                    final r = input.trim().toUpperCase();
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r)));
                                    widget.onRouteSelected?.call(r);
                                  }
                                } else {
                                  _onKeyTap(key);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(btnSize, btnSize),
                              ),
                              child: Text(key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),

          const SizedBox(width: 8),

          // Letter grid: 2 columns x 4 rows (max 8 letters)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int r = 0; r < 4; r++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int c = 0; c < 2; c++)
                      Padding(
                        padding: const EdgeInsets.all(gap / 2),
                        child: SizedBox(
                          width: btnSize,
                          height: btnSize,
                          child: Builder(builder: (_) {
                            // fill letters column-major: top-to-bottom in first column, then second column
                            final rows = 4;
                            final idx = c * rows + r;
                            if (idx < letters.length) {
                              final letter = letters[idx];
                              return ElevatedButton(
                                onPressed: () => _onKeyTap(letter),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(btnSize, btnSize),
                                  elevation: 0,
                                ),
                                child: Text(letter, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              );
                            }

                            // If no letter for this cell, try to place back/OK here if needed
                            if (!digitGrid.any((row) => row.contains(backKey))) {
                              return ElevatedButton(
                                onPressed: _onBackspace,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: Icon(Icons.backspace_outlined, color: theme.colorScheme.onPrimaryContainer),
                              );
                            }
                            if (!digitGrid.any((row) => row.contains(okKey))) {
                              return ElevatedButton(
                                onPressed: () {
                                  if (routes.contains(input)) {
                                    final r = input.trim().toUpperCase();
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r)));
                                    widget.onRouteSelected?.call(r);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: Text('OK', style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
                              );
                            }

                            return const SizedBox.shrink();
                          }),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Highlight occurrences of [query] within [text], case-insensitive.
  Widget buildHighlightedText(String text, String query) {
    final theme = Theme.of(context);
  final defaultColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final highlightColor = theme.colorScheme.secondary; // use theme secondary instead of yellow
    if (query.isEmpty) return Text(text, style: TextStyle(color: defaultColor));
    final lcText = text.toLowerCase();
    final lcQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;
    while ((idx = lcText.indexOf(lcQuery, start)) != -1) {
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx), style: TextStyle(color: defaultColor)));
      spans.add(TextSpan(text: text.substring(idx, idx + query.length), style: TextStyle(fontWeight: FontWeight.bold, color: highlightColor)));
      start = idx + query.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: defaultColor)));
    return RichText(text: TextSpan(style: TextStyle(color: defaultColor, fontSize: 16), children: spans));
  }
}

// A small container that provides a frosted glass (liquid glass) background
// and a subtle entrance animation to make the dialer feel reachable for one-hand use.
class _OneHandDialerContainer extends StatefulWidget {
  final Widget child;
  const _OneHandDialerContainer({super.key, required this.child});

  @override
  State<_OneHandDialerContainer> createState() => _OneHandDialerContainerState();
}

class _OneHandDialerContainerState extends State<_OneHandDialerContainer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 1. Layer 必須包裹在 Stack 或類似結構中，通常用於管理背景折射
    return LiquidGlassLayer(
      settings: LiquidGlassSettings(
        blur: 3,  // 對應 ImageFilter.blur
        glassColor: colorScheme.surface.withOpacity(0.7), // 對應 decoration color
        thickness: 20, // 模擬玻璃厚度，增強折射感
        lightIntensity: 0.5, // 調整光照以配合 Material 3 風格
      ),
      // 2. 使用 ScaleTransition 包裹 LiquidGlass
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
        child: LiquidGlass(
          // 3. 使用 iOS/M3 風格的 Superellipse 形狀
          shape: LiquidRoundedSuperellipse(borderRadius: 20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
