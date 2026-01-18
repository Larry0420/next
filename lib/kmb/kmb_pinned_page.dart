import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'api/kmb.dart';
import '../kmb_route_status_page.dart';
import '../main.dart' show LanguageProvider;

import '../toTitleCase.dart';

class KmbPinnedPage extends StatefulWidget {
  const KmbPinnedPage({super.key});

  @override
  State<KmbPinnedPage> createState() => _KmbPinnedPageState();
}

class _KmbPinnedPageState extends State<KmbPinnedPage> with SingleTickerProviderStateMixin {
  static const String _pinnedTabKey = 'kmb_pinned_tab_index';

  late TabController _tabController;
  List<Map<String, dynamic>> _pinnedRoutes = [];
  List<Map<String, dynamic>> _pinnedStops = [];
  List<Map<String, dynamic>> _historyRoutes = [];
  bool _loading = true;
  bool _isInitializing = true; // 新增
  
  @override
  void initState() {
    super.initState();
    _loadSavedTabIndex(); // 修改
  }

  // 新增方法
  Future<void> _loadSavedTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = (prefs.getInt(_pinnedTabKey) ?? 0).clamp(0, 2);
    
    if (mounted) {
      setState(() {
        _tabController = TabController(length: 3, vsync: this, initialIndex: savedIndex);
        _tabController.addListener(_saveTabIndex);
        _isInitializing = false;
      });
      _loadData();
    }
  }

  // 新增方法
  Future<void> _saveTabIndex() async {
    if (!_tabController.indexIsChanging) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pinnedTabKey, _tabController.index);
    }
  }

  @override
  void dispose() {
    if (!_isInitializing) {
      _tabController.removeListener(_saveTabIndex);
      _tabController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final pinned = await Kmb.getPinnedRoutes();
      final pinnedStops = await Kmb.getPinnedStops();
      final history = await Kmb.getRouteHistory();

      final enrichedRoutes = await _enrichWithDestination(pinned);
      final enrichedStops = await _enrichStopsWithDestination(pinnedStops);

      setState(() {
        _pinnedRoutes = enrichedRoutes;
        _pinnedStops = enrichedStops;
        _historyRoutes = history;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _enrichWithDestination(List<Map<String, dynamic>> items) async {
    try {
      final routeIndex = await Kmb.buildRouteIndex();
      final enriched = <Map<String, dynamic>>[];
      for (final item in items) {
        final route = item['route']?.toString().trim().toUpperCase();
        final direction = item['direction']?.toString() ?? 'O';
        final serviceType = item['serviceType']?.toString() ?? '1';
        if (route != null && route.isNotEmpty) {
          final indexKey = '${route}_${direction}_$serviceType';
          final routeData = routeIndex[indexKey];
          if (routeData != null) {
            final enrichedItem = Map<String, dynamic>.from(item);
            enrichedItem['destEn'] = routeData['dest_en'];
            enrichedItem['destTc'] = routeData['dest_tc'];
            enrichedItem['origEn'] = routeData['orig_en'];
            enrichedItem['origTc'] = routeData['orig_tc'];
            enriched.add(enrichedItem);
            continue;
          }
        }
        enriched.add(item);
      }
      return enriched;
    } catch (e) {
      return items;
    }
  }

  Future<List<Map<String, dynamic>>> _enrichStopsWithDestination(List<Map<String, dynamic>> stops) async {
    try {
      final routeIndex = await Kmb.buildRouteIndex();
      final enriched = <Map<String, dynamic>>[];
      for (final stop in stops) {
        final route = stop['route']?.toString().trim().toUpperCase();
        final direction = stop['direction']?.toString() ?? 'O';
        final serviceType = stop['serviceType']?.toString() ?? '1';

        if (stop['destEn'] != null || stop['destTc'] != null) {
          enriched.add(stop);
          continue;
        }

        if (route != null && route.isNotEmpty) {
          final indexKey = '${route}_${direction}_$serviceType';
          final routeData = routeIndex[indexKey];
          if (routeData != null) {
            final enrichedStop = Map<String, dynamic>.from(stop);
            enrichedStop['destEn'] = routeData['dest_en'];
            enrichedStop['destTc'] = routeData['dest_tc'];
            enriched.add(enrichedStop);
            continue;
          }
        }
        enriched.add(stop);
      }
      return enriched;
    } catch (e) {
      return stops;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Add this check! 
    // If we are still initializing the controller, show a loading spinner.
    // This prevents the app from trying to use _tabController before it exists.
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(year2023: false,)),
      );
    }
    
    
    final lang = context.watch<LanguageProvider>();
    return Scaffold(
      body: Stack(
        children: [
          // 1. 底層內容 (背景)
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator(year2023: false))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPinnedTab(lang),
                      _buildPinnedStopsTab(lang),
                      _buildHistoryTab(lang),
                    ],
                  ),
          ),

          // 2. 上層 Liquid Glass 效果
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: true,
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12, 
                  8, 
                  12, 
                  MediaQuery.of(context).padding.bottom + 12
                ),
                
                // --- 替換開始 ---
                // 使用 LiquidGlassLayer 包裹 LiquidGlass
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings(
                    thickness: 20, // 玻璃厚度/折射強度 (取代 blur 效果)
                    blur: 10,      // 背景模糊程度
                    glassColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    // 你可以調整這些參數來匹配原本的邊框/光影
                    lightIntensity: 0.1,
                  ),
                  child: LiquidGlass(
                    // 使用 LiquidRoundedSuperellipse 取代 BorderRadius.circular(50)
                    // 這會產生更滑順的 "Squircle" 形狀，更像 iOS 風格
                    shape: LiquidRoundedSuperellipse(borderRadius: 50),
                    
                    // 如果需要原本的邊框線，LiquidGlass 本身有 outlineIntensity
                    // 但如果需要完全自定義邊框，可能需要疊加一個 Container
                    // 2. 加入 Material 層來控制水波紋 (Splash) 的邊界
                    child: Material(
                      color: Colors.transparent, // 保持透明，讓下方玻璃效果透出來
                      
                      // 關鍵：這裡必須設定與 LiquidGlass 相同的形狀
                      shape: LiquidRoundedSuperellipse(borderRadius: 50),
                      
                      // 關鍵：開啟裁切，這會把水波紋限制在形狀內
                      clipBehavior: Clip.antiAlias, 

                    child: TabBar(
                      controller: _tabController,
                       // 使用 ShapeDecoration 來支援非標準圓角 (Squircle)
                      indicator: ShapeDecoration(
                        // 關鍵：這裡必須使用與外層 LiquidGlass 完全相同的形狀和參數
                        shape: LiquidRoundedSuperellipse(borderRadius: 50), 
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.6),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(4),
                      labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(icon: const Icon(Icons.push_pin, size: 20), text: lang.pinnedRoutes, height: 52),
                        Tab(icon: const Icon(Icons.location_on, size: 20), text: lang.isEnglish ? 'Stops' : '站點', height: 52),
                        Tab(icon: const Icon(Icons.history, size: 20), text: lang.history, height: 52),
                      ],
                    ),
                    ),
                  ),
                ),
                // --- 替換結束 ---
                
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedTab(LanguageProvider lang) {
    if (_pinnedRoutes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.push_pin_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(lang.noPinnedRoutes, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(lang.pinRoutesToSeeThemHere, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    final double bottomInset = 80 + MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset),
        itemCount: _pinnedRoutes.length,
        itemBuilder: (context, index) {
          final route = _pinnedRoutes[index];
          return _buildCompactRouteCard(
            route: route,
            lang: lang,
            isPinned: true,
            onUnpin: () async {
              await Kmb.unpinRoute(route['route'], route['direction'], route['serviceType']);
              _loadData();
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab(LanguageProvider lang) {
    final double bottomInset = 80 + MediaQuery.of(context).padding.bottom;
    if (_historyRoutes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(lang.noHistory, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(lang.viewedRoutesWillAppearHere, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_historyRoutes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(lang.clearHistory),
                  style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                  onPressed: () async {
                    final confirm = await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(lang.clearAllHistory),
                        content: Text(lang.thisActionCannotBeUndone),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(lang.cancel)),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: Text(lang.clear),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await Kmb.clearRouteHistory();
                      _loadData();
                    }
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(12, 4, 12, bottomInset),
              itemCount: _historyRoutes.length,
              itemBuilder: (context, index) {
                final route = _historyRoutes[index];
                return _buildCompactRouteCard(route: route, lang: lang, isPinned: false, showTimestamp: true);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactRouteCard({
    required Map<String, dynamic> route,
    required LanguageProvider lang,
    required bool isPinned,
    VoidCallback? onUnpin,
    bool showTimestamp = false,
  }) {
    final routeNum = route['route'] ?? '';
    final label = route['label'] ?? routeNum;
    final direction = route['direction'] ?? '';
    final serviceType = route['serviceType'] ?? '1';
    final destEn = route['destEn'];
    final destTc = route['destTc'];
    final origEn = route['origEn'];
    final origTc = route['origTc'];

    String destinationText = '';
    if (lang.isEnglish) {
      final orig = origEn ?? origTc ?? '';
      final dest = destEn ?? destTc ?? '';
      destinationText = (orig.isNotEmpty && dest.isNotEmpty) ? 'From $orig to $dest' : label.replaceFirst('$routeNum: ', '');
    } else {
      final orig = origTc ?? origEn ?? '';
      final dest = destTc ?? destEn ?? '';
      destinationText = (orig.isNotEmpty && dest.isNotEmpty) ? '由 $orig 往 $dest' : label.replaceFirst('$routeNum: ', '');
    }

    String? timeText;
    if (showTimestamp && route['accessedAt'] != null) {
      try {
        final dt = DateTime.parse(route['accessedAt']);
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (diff.inMinutes < 1) {
          timeText = lang.justNow;
        } else if (diff.inHours < 1) {
          timeText = lang.isEnglish ? '${diff.inMinutes}m ago' : '${diff.inMinutes}分鐘前';
        } else if (diff.inDays < 1) {
          timeText = lang.isEnglish ? '${diff.inHours}h ago' : '${diff.inHours}小時前';
        } else if (diff.inDays < 7) {
          timeText = lang.isEnglish ? '${diff.inDays}d ago' : '${diff.inDays}天前';
        } else {
          timeText = '${dt.month}/${dt.day}';
        }
      } catch (_) {}
    }

    final cs = Theme.of(context).colorScheme;
    Color dirColor = cs.secondary;
    IconData dirIcon = Icons.arrow_forward;
    if (direction.toUpperCase().startsWith('O')) {
      dirIcon = Icons.arrow_circle_right;
      dirColor = cs.primary;
    } else if (direction.toUpperCase().startsWith('I')) {
      dirIcon = Icons.arrow_circle_left;
      dirColor = cs.tertiary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.15), width: 1.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => KmbRouteStatusPage(route: routeNum, bound: direction, serviceType: serviceType)),
              ).then((_) => _loadData());
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: dirColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: Icon(dirIcon, color: dirColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: AutoSizeText(
                                '${lang.route} $routeNum',
                                maxLines: 1,
                                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer, fontSize: 14),
                              ),
                            ),
                            if (serviceType != '1') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: AutoSizeText('${lang.type}($serviceType)', style: TextStyle(fontSize: 10, color: Colors.blue[800], fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        AutoSizeText(
                          destinationText.toTitleCase(),
                          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        if (timeText != null) ...[
                          const SizedBox(height: 2),
                          Text(timeText, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6))),
                        ],
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: isPinned
                        ? IconButton(
                            key: const ValueKey('pinned'),
                            onPressed: onUnpin,
                            icon: const Icon(Icons.push_pin, size: 20),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                              foregroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              //padding: const EdgeInsets.all(6),
                              minimumSize: const Size(40, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                        : Icon(
                            key: const ValueKey('unpinned'),
                            Icons.chevron_right,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                            size: 20,
                          ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedStopsTab(LanguageProvider lang) {
    if (_pinnedStops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(lang.isEnglish ? 'No Pinned Stops' : '沒有釘選站點', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(lang.isEnglish ? 'Pin stops to see them here' : '釘選站點以在此處查看', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    final double bottomInset = 80 + MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset),
        itemCount: _pinnedStops.length,
        itemBuilder: (context, index) {
          final stop = _pinnedStops[index];
          return PinnedStopCard(
            stop: stop,
            lang: lang,
            onUnpin: () async {
              await Kmb.unpinStop(stop['route'], stop['stopId'], stop['seq']);
              _loadData();
            },
            compact: _pinnedStops.length > 8,
          );
        },
      ),
    );
  }
}

class PinnedStopCard extends StatefulWidget {
  final Map<String, dynamic> stop;
  final LanguageProvider lang;
  final VoidCallback onUnpin;
  final bool compact;

  const PinnedStopCard({super.key, required this.stop, required this.lang, required this.onUnpin, this.compact = false});

  @override
  State<PinnedStopCard> createState() => _PinnedStopCardState();
}

class _PinnedStopCardState extends State<PinnedStopCard> {
  Timer? _etaRefreshTimer;
  List<Map<String, dynamic>> _etas = [];
  bool _loading = true;
  bool _hasLoadedOnce = false;
  Duration _refreshInterval = const Duration(seconds: 15);
  int _consecutiveErrors = 0;

  @override
  void initState() {
    super.initState();
    _fetchEtas();
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(PinnedStopCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lang.isEnglish != widget.lang.isEnglish) {
      _fetchEtas(silent: true);
    }
  }

  @override
  void dispose() {
    _etaRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _etaRefreshTimer?.cancel();
    _etaRefreshTimer = Timer.periodic(_refreshInterval, (timer) {
      if (mounted) _fetchEtas(silent: true);
    });
  }

  Future<void> _fetchEtas({bool silent = false}) async {
    if (!silent && !_hasLoadedOnce) {
      setState(() => _loading = true);
    }

    try {
      final route = widget.stop['route']?.toString().trim().toUpperCase() ?? '';
      final serviceType = widget.stop['serviceType']?.toString() ?? '1';
      final seq = widget.stop['seq']?.toString() ?? '';
      final direction = widget.stop['direction']?.toString().trim().toUpperCase() ?? '';

      if (route.isEmpty) {
        setState(() {
          _etas = [];
          _loading = false;
        });
        return;
      }

      final entries = await Kmb.fetchRouteEta(route, serviceType);
      final directionChar = direction.isNotEmpty ? direction[0] : '';
      final freshEtas = entries.where((e) {
        if (e['seq']?.toString() != seq) return false;
        if (directionChar.isNotEmpty) {
          final etaDir = e['dir']?.toString().trim().toUpperCase() ?? '';
          if (etaDir.isEmpty || etaDir[0] != directionChar) return false;
        }
        return true;
      }).toList();

      freshEtas.sort((a, b) {
        final ai = int.tryParse(a['eta_seq']?.toString() ?? '') ?? 0;
        final bi = int.tryParse(b['eta_seq']?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });

      if (mounted) {
        setState(() {
          _etas = freshEtas;
          _loading = false;
          _hasLoadedOnce = true;
          _consecutiveErrors = 0;
          _refreshInterval = const Duration(seconds: 15);
        });
        _startAutoRefresh();
      }
    } catch (e) {
      _consecutiveErrors++;
      _refreshInterval = Duration(seconds: math.min(60, 15 * math.pow(2, _consecutiveErrors).toInt()));
      _startAutoRefresh();
      if (mounted && !silent) {
        setState(() {
          _etas = [];
          _loading = false;
        });
      }
    }
  }

  Color _getEtaColor(dynamic raw) {
    if (raw == null) return Colors.grey;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final diff = dt.difference(DateTime.now());
      if (diff.isNegative) return Colors.grey;
      if (diff.inMinutes <= 2) return Colors.red;
      if (diff.inMinutes <= 5) return Colors.orange;
      if (diff.inMinutes <= 10) return Colors.green;
      return Colors.blue;
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.stop['route'] ?? '';
    final nameEn = widget.stop['stopNameEn'] ?? widget.stop['stopName'] ?? '';
    final nameTc = widget.stop['stopNameTc'] ?? widget.stop['stopName'] ?? '';
    final stopName = widget.lang.isEnglish ? (nameEn.isNotEmpty ? nameEn.toString().toTitleCase()  : nameTc) : (nameTc.isNotEmpty ? nameTc : nameEn.toString().toTitleCase());
    final latitude = widget.stop['latitude'];
    final longitude = widget.stop['longitude'];
    final destEn = widget.stop['destEn'];
    final destTc = widget.stop['destTc'];
    final dest = widget.lang.isEnglish ? (destEn.toString().toTitleCase() ?? destTc ?? '') : (destTc ?? destEn.toString().toTitleCase() ?? '');
    final direction = widget.stop['direction']?.toString() ?? 'O';

    final cs = Theme.of(context).colorScheme;
    Color directionColor = cs.secondary;
    IconData directionIcon = Icons.arrow_forward;
    if (direction.toUpperCase().startsWith('O')) {
      directionColor = cs.primary;
      directionIcon = Icons.arrow_circle_right;
    } else if (direction.toUpperCase().startsWith('I')) {
      directionColor = cs.tertiary;
      directionIcon = Icons.arrow_circle_left;
    }

    if (widget.compact) {
      String? firstEtaText;
      if (!_loading && _etas.isNotEmpty) {
        final e = _etas.first;
        final etaRaw = e['eta'] ?? e['eta_time'];
        if (etaRaw != null) {
          try {
            final dt = DateTime.parse(etaRaw.toString()).toLocal();
            final diff = dt.difference(DateTime.now());
            if (diff.inMinutes <= 0 && diff.inSeconds > -60) {
              firstEtaText = widget.lang.isEnglish ? 'Arr' : '到達';
            } else if (diff.isNegative) {
              firstEtaText = '-';
            } else {
              final mins = diff.inMinutes;
              firstEtaText = widget.lang.isEnglish ? '${mins}m' : '$mins分';
            }
          } catch (_) {}
        }
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.15), width: 1.0),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => KmbRouteStatusPage(
                    route: route, 
                    bound: widget.stop['direction'], 
                    serviceType: widget.stop['serviceType'],
                    autoExpandSeq: widget.stop['seq']?.toString(),
                    autoExpandStopId: widget.stop['stopId']?.toString(),
                  )),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: directionColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: Text(route, style: TextStyle(fontWeight: FontWeight.bold, color: directionColor, fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText(stopName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (dest.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(dest, style: TextStyle(fontSize: 11, color: directionColor.withOpacity(0.9)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_loading)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (firstEtaText != null)
                      Text(firstEtaText, style: TextStyle(fontWeight: FontWeight.bold, color: _getEtaColor(_etas.first['eta'] ?? _etas.first['eta_time'])))
                    else
                      const SizedBox.shrink(),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('pinned'),
                      onPressed: widget.onUnpin,
                      icon: const Icon(Icons.push_pin, size: 29),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                        //padding: const EdgeInsets.all(6),
                        minimumSize: const Size(20, 20),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.15), width: 1.0),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => KmbRouteStatusPage(
                      route: route, 
                      bound: widget.stop['direction'], 
                      serviceType: widget.stop['serviceType'],
                      autoExpandSeq: widget.stop['seq']?.toString(),
                      autoExpandStopId: widget.stop['stopId']?.toString(),
                    )),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: directionColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: directionColor.withOpacity(0.3), width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(route, style: TextStyle(fontWeight: FontWeight.bold, color: directionColor, fontSize: 14)),
                            const SizedBox(height: 2),
                            Icon(directionIcon, color: directionColor, size: 16),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AutoSizeText(stopName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (dest.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(directionIcon, size: 11, color: directionColor.withOpacity(0.8)),
                                  const SizedBox(width: 4),
                                  Expanded(child: AutoSizeText(dest, style: TextStyle(fontSize: 11, color: directionColor.withOpacity(0.9), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            if (_loading)
                              const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            else if (_etas.isEmpty)
                              Text(widget.lang.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士', style: TextStyle(color: Colors.grey[600], fontSize: 11))
                            else
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: _etas.take(3).map((e) {
                                  final etaRaw = e['eta'] ?? e['eta_time'];
                                  final rmk = widget.lang.isEnglish ? (e['rmk_en'] ?? '') : (e['rmk_tc'] ?? '');
                                  String etaText = widget.lang.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士';
                                  bool isDeparted = false;
                                  bool isNearlyArrived = false;
                                  if (etaRaw != null) {
                                    try {
                                      final dt = DateTime.parse(etaRaw.toString()).toLocal();
                                      final diff = dt.difference(DateTime.now());
                                      final mins = diff.inMinutes;
                                      if (mins <= 0 && diff.inSeconds > -60) {
                                        etaText = widget.lang.isEnglish ? 'Arriving' : '到達中';
                                        isNearlyArrived = true;
                                      } else if (diff.isNegative) {
                                        etaText = widget.lang.isEnglish ? '- min' : '- 分鐘';
                                        isDeparted = true;
                                      } else {
                                        if (mins < 1) {
                                          etaText = widget.lang.isEnglish ? 'Due' : '即將抵達';
                                          isNearlyArrived = true;
                                        } else {
                                          etaText = widget.lang.isEnglish ? '$mins min' : '$mins分鐘';
                                        }
                                      }
                                    } catch (_) {}
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(etaText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDeparted ? Colors.grey[400] : (isNearlyArrived ? Colors.green : _getEtaColor(etaRaw)))),
                                      if (rmk.isNotEmpty) Text(rmk, style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7))),
                                    ],
                                  );
                                }).toList(),
                              ),
                            if (latitude != null && longitude != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 11, color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
                                  const SizedBox(width: 4),
                                  Text('$latitude, $longitude', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onUnpin,
                        icon: const Icon(Icons.push_pin, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
