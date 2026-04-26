import 'dart:async';
import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:lrt_next_train/optionalMarquee.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kmb_route_status_page.dart';
import '../ctb_route_status_page.dart';
import '../route_status_page.dart';
import '../main.dart' show LanguageProvider, EnhancedPageRoute, DeveloperSettingsProvider;
import '../services/unified_pinned_storage.dart';
import '../toTitleCase.dart';
import 'api/citybus.dart';
import 'api/gmb.dart';
import 'api/kmb.dart';
import 'api/nlb.dart';
import 'company_name.dart';



class KmbPinnedPage extends StatefulWidget {
  const KmbPinnedPage({super.key});

  @override
  State<KmbPinnedPage> createState() => _KmbPinnedPageState();
}

class _KmbPinnedPageState extends State<KmbPinnedPage> with SingleTickerProviderStateMixin {
  static const String _pinnedTabKey = 'kmb_pinned_tab_index';

  TabController? _tabController;
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
      final controller = TabController(length: 3, vsync: this, initialIndex: savedIndex);
      controller.addListener(_saveTabIndex);
      setState(() {
        _tabController = controller;
        _isInitializing = false;
      });
      _loadData();
    }
    
  }



  // _saveTabIndex uses _tabController! without null check
  Future<void> _saveTabIndex() async {
    if (!_tabController!.indexIsChanging) { // add !
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pinnedTabKey, _tabController!.index); // add !
    }
  }

  // dispose is fine but simplify:
  @override
  void dispose() {
    _tabController?.removeListener(_saveTabIndex);
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final kmbPinned = await Kmb.getPinnedRoutes();
      final kmbPinnedStops = await Kmb.getPinnedStops();
      final kmbHistory = await Kmb.getRouteHistory();

      // Load CTB data
      final ctbPinned = await Citybus.getPinnedRoutes();
      final ctbPinnedStops = await Citybus.getPinnedStops();
      final ctbHistory = await Citybus.getRouteHistory();

      // Load GMB/NLB + unified storage
      final gmbPinned = await GMB.getPinnedRoutes();
      final gmbPinnedStops = await GMB.getPinnedStops();
      final nlbPinned = await Nlb.getPinnedRoutes();
      final unifiedPinnedRoutes = await UnifiedPinnedStorage.getPinnedRoutes();
      final unifiedPinnedStops = await UnifiedPinnedStorage.getPinnedStops();

      // Merge and enrich
      final allPinned = [
        ...kmbPinned.map((e) => Map<String, dynamic>.from(e)),
        ...ctbPinned.map((e) => Map<String, dynamic>.from(e)),
        ...gmbPinned.map(_normalizeGmbPinnedRoute),
        ...nlbPinned.map(_normalizeNlbPinnedRoute),
        ...unifiedPinnedRoutes.map((e) => Map<String, dynamic>.from(e)),
      ];
      final allPinnedStops = [
        ...kmbPinnedStops.map((e) => Map<String, dynamic>.from(e)),
        ...ctbPinnedStops.map((e) => Map<String, dynamic>.from(e)),
        ...gmbPinnedStops.map(_normalizeGmbPinnedStop),
        ...unifiedPinnedStops.map((e) => Map<String, dynamic>.from(e)),
      ];
    
      final allHistory = [
        ...kmbHistory.map((e) => Map<String, dynamic>.from(e)),
        ...ctbHistory.map((e) => Map<String, dynamic>.from(e)),
      ];

      // Sort by timestamp (newest first)
      allPinned.sort((a, b) {
        final aTime = a['pinnedAt'] ?? '';
        final bTime = b['pinnedAt'] ?? '';
        return bTime.compareTo(aTime);
      });
      
      allHistory.sort((a, b) {
        final aTime = a['accessedAt'] ?? '';
        final bTime = b['accessedAt'] ?? '';
        return bTime.compareTo(aTime);
      });
    
      final enrichedRoutes = await _enrichWithDestination(allPinned);
      final enrichedStops = await _enrichStopsWithDestination(allPinnedStops);

      setState(() {
        _pinnedRoutes = enrichedRoutes;
        _pinnedStops = enrichedStops;
        _historyRoutes = allHistory;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _normalizeNlbPinnedRoute(Map<String, dynamic> item) {
    return {
      'source': 'nlb',
      'co': 'nlb',
      'route': item['routeNo']?.toString() ?? '',
      'direction': item['direction']?.toString() ?? '',
      'serviceType': item['serviceType']?.toString() ?? '1',
      'label': item['label']?.toString() ?? (item['routeNo']?.toString() ?? ''),
      'initialRouteId': item['routeId']?.toString(),
      'routeId': item['routeId']?.toString(),
      'pinnedAt': item['pinnedAt'],
    };
  }

  Map<String, dynamic> _normalizeGmbPinnedRoute(Map<String, dynamic> item) {
    final routeSeq = item['routeSeq']?.toString() ?? '1';
    return {
      'source': 'gmb',
      'co': 'gmb',
      'route': item['routeCode']?.toString() ?? '',
      'direction': routeSeq == '2' ? 'I' : 'O',
      'serviceType': item['serviceType']?.toString() ?? '1',
      'label': item['label']?.toString() ?? (item['routeCode']?.toString() ?? ''),
      'gmbRouteId': item['routeId'],
      'gmbRouteSeq': item['routeSeq'],
      'gmbRegion': item['region']?.toString(),
      'pinnedAt': item['pinnedAt'],
    };
  }

  Map<String, dynamic> _normalizeGmbPinnedStop(Map<String, dynamic> item) {
    return {
      'source': 'gmb',
      'co': 'gmb',
      'route': item['routeCode']?.toString() ?? '',
      'stopId': item['stopId']?.toString() ?? '',
      'seq': item['routeSeq']?.toString() ?? '1',
      'stopName': item['stopName']?.toString() ?? '',
      'stopNameEn': item['stopName']?.toString() ?? '',
      'stopNameTc': item['stopName']?.toString() ?? '',
      'direction': (item['routeSeq']?.toString() == '2') ? 'I' : 'O',
      'serviceType': '1',
      'gmbRouteId': item['routeId'],
      'gmbRouteSeq': item['routeSeq'],
      'pinnedAt': item['pinnedAt'],
    };
  }

  Future<List<Map<String, dynamic>>> _enrichWithDestination(List<Map<String, dynamic>> items) async {
    try {
      final kmbIndex = await Kmb.buildRouteIndex();
      final ctbIndex = await Citybus.buildRouteIndex();

      final enriched = <Map<String, dynamic>>[];
      for (final item in items) {
          final route = item['route']?.toString().trim().toUpperCase();
          final direction = item['direction']?.toString() ?? 'O';
          final serviceType = item['serviceType']?.toString() ?? '1';
          final companyId = item['co']?.toString().toLowerCase() ?? 'kmb';
          if (route != null && route.isNotEmpty) {
            // Choose correct index based on company
          final routeIndex = (companyId == 'ctb' || companyId == 'nwfb') 
              ? ctbIndex 
              : kmbIndex;
          
          // CTB doesn't use service type in key
          final indexKey = (companyId == 'ctb' || companyId == 'nwfb')
              ? '${route}_${direction}_$serviceType'
              : '${route}_${direction}_$serviceType';
          
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

  Future<List<Map<String, dynamic>>> _enrichStopsWithDestination(
    List<Map<String, dynamic>> stops,
  ) async {
    try {
      debugPrint('🔍 === Starting _enrichStopsWithDestination ===');
      debugPrint('📦 Total stops to enrich: ${stops.length}');
      
      // ✅ Load BOTH route indices
      final kmbIndex = await Kmb.buildRouteIndex();
      final ctbIndex = await Citybus.buildRouteIndex();
      
      debugPrint('📚 KMB index has ${kmbIndex.length} entries');
      debugPrint('📚 CTB index has ${ctbIndex.length} entries');
      debugPrint('📚 Sample CTB keys: ${ctbIndex.keys.take(5).toList()}');
      
      final enriched = <Map<String, dynamic>>[];
      
      for (int i = 0; i < stops.length; i++) {
        final stop = stops[i];
        final route = stop['route']?.toString().trim().toUpperCase();
        final direction = stop['direction']?.toString() ?? 'O';
        final serviceType = stop['serviceType']?.toString() ?? '1';
        final companyId = stop['co']?.toString().toLowerCase() ?? 'kmb';

        debugPrint('\n🛑 Stop ${i + 1}/${stops.length}:');
        debugPrint('   Route: $route, Direction: $direction, ServiceType: $serviceType, Company: $companyId');
        debugPrint('   Existing destEn: ${stop['destEn']}, destTc: ${stop['destTc']}');

        // ✅ Skip if already enriched
        if (stop['destEn'] != null && stop['destTc'] != null) {
          debugPrint('   ✅ Already enriched - skipping');
          enriched.add(stop);
          continue;
        }

        if (route != null && route.isNotEmpty) {
          // ✅ Choose correct index and key format based on company
          final Map<String, dynamic> routeIndex;
          final String indexKey;
          
          if (companyId == 'ctb' || companyId == 'nwfb') {
            // CTB: Use CTB index with route_direction format (no service type)
            routeIndex = ctbIndex;
            indexKey = '${route}_${direction}_$serviceType';
            debugPrint('   🚌 CTB/NWFB stop - using key: $indexKey');
          } else {
            // KMB: Use KMB index with route_direction_serviceType format
            routeIndex = kmbIndex;
            indexKey = '${route}_${direction}_$serviceType';
            debugPrint('   🚌 KMB stop - using key: $indexKey');
          }
          
          final routeData = routeIndex[indexKey];
          
          if (routeData != null) {
            debugPrint('   ✅ FOUND in index!');
            debugPrint('   📍 dest_en: ${routeData['dest_en']}');
            debugPrint('   📍 desten: ${routeData['desten']}');
            debugPrint('   📍 dest_tc: ${routeData['dest_tc']}');
            debugPrint('   📍 desttc: ${routeData['desttc']}');
            
            final enrichedStop = Map<String, dynamic>.from(stop);
            
            // ✅ Handle both field name formats
            enrichedStop['destEn'] = routeData['dest_en'] ?? routeData['desten'];
            enrichedStop['destTc'] = routeData['dest_tc'] ?? routeData['desttc'];
            enrichedStop['origEn'] = routeData['orig_en'] ?? routeData['origen'];
            enrichedStop['origTc'] = routeData['orig_tc'] ?? routeData['origtc'];
            
            debugPrint('   ✅ Enriched with destEn: ${enrichedStop['destEn']}, destTc: ${enrichedStop['destTc']}');
            
            enriched.add(enrichedStop);
            continue;
          } else {
            debugPrint('   ❌ NOT FOUND in index for key: $indexKey');
            debugPrint('   💡 Available keys with same route:');
            final sameRouteKeys = routeIndex.keys.where((k) => k.startsWith(route)).take(3).toList();
            debugPrint('      $sameRouteKeys');
          }
        }
        
        debugPrint('   ⚠️ Adding without enrichment');
        enriched.add(stop);
      }
      
      debugPrint('\n✅ === Enrichment Complete ===');
      debugPrint('📊 Total enriched: ${enriched.length}');
      debugPrint('📊 With destEn: ${enriched.where((s) => s['destEn'] != null).length}');
      debugPrint('📊 With destTc: ${enriched.where((s) => s['destTc'] != null).length}');
      
      return enriched;
    } catch (e, stackTrace) {
      debugPrint('❌ Error enriching stops: $e');
      debugPrint('Stack trace: $stackTrace');
      return stops;
    }
  }

  // Add to class fields
  static const tabIcons = [Icons.push_pin, Icons.location_on, Icons.history];

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    // 1. Add this check! 
    // If we are still initializing the controller, show a loading spinner.
    // This prevents the app from trying to use _tabController before it exists.
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    final tabLabels = [lang.pinnedRoutes, lang.isEnglish ? 'Stops' : '站點', lang.history];

    
    return Scaffold(
      body: Stack(
        children: [
          // In KmbPinnedPage build(), replace:
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _loading
                  ? const Center(
                      key: ValueKey('loading'),
                      child: CircularProgressIndicator.adaptive(),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) => n.metrics.axis == Axis.horizontal,
                      child: TabBarView(
                        key: const ValueKey('content'),
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(), // tap-only inner tabs
                        children: [
                          _buildPinnedTab(lang),
                          _buildPinnedStopsTab(lang),
                          _buildHistoryTab(lang),
                        ],
                      ),
                    ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12, 8, 12,
                  MediaQuery.of(context).padding.bottom + 12,
                ),
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings(
                    thickness: 50,
                    blur: 10,
                    glassColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    lightIntensity: 0.1,
                    lightAngle: 45,
                  ),
                  child: LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 50),
                    child: Material(
                      color: Colors.transparent,
                      shape: LiquidRoundedSuperellipse(borderRadius: 50),
                      clipBehavior: Clip.antiAlias,
                        child: _tabController == null
                        ? const SizedBox.shrink()
                        : AnimatedBuilder(
                            animation: _tabController!.animation!,
                            builder: (context, _) {
                              final animValue = _tabController!.animation!.value;
                              return Row(
                                children: List.generate(tabIcons.length, (i) {
                                  final selectedAmount = (1.0 - (animValue - i).abs()).clamp(0.0, 1.0);
                                  return Expanded(
                                    child: InkWell(
                                      customBorder: LiquidRoundedSuperellipse(borderRadius: 50),
                                      onTap: () => _tabController!.animateTo(i),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.all(4),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: ShapeDecoration(
                                        shape: LiquidRoundedSuperellipse(borderRadius: 50),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.6 * selectedAmount),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            tabIcons[i],
                                            size: 20,
                                            color: Color.lerp(
                                              Theme.of(context).colorScheme.onSurfaceVariant,
                                              Theme.of(context).colorScheme.onPrimaryContainer,
                                              selectedAmount,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            tabLabels[i],
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Color.lerp(
                                                Theme.of(context).colorScheme.onSurfaceVariant,
                                                Theme.of(context).colorScheme.onPrimaryContainer,
                                                selectedAmount,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),

                    
                  ),
                ),
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
              final companyId = route['co']?.toString().toLowerCase() ?? 'kmb';
              final source = route['source']?.toString();
              // ✅ Check storage SOURCE first — before company-specific checks
              if (source == 'unified' || companyId == 'mtr' || companyId == 'lrt') {
                await UnifiedPinnedStorage.unpinRoute(
                  company: companyId,
                  route: route['route']?.toString() ?? '',
                  bound: route['direction']?.toString(),
                  serviceType: route['serviceType']?.toString(),
                  initialRouteId: route['initialRouteId']?.toString(),
                );
              } else if (companyId == 'ctb') {
                await Citybus.unpinRoute(route['route'], companyId: companyId.toLowerCase());
              } else if (companyId == 'nlb') {
                final routeId = route['routeId']?.toString() ?? route['initialRouteId']?.toString() ?? '';
                if (routeId.isNotEmpty)
                  await Nlb.unpinRoute(routeId);
                else
                  await UnifiedPinnedStorage.unpinRoute(
                    company: companyId,
                    route: route['route']?.toString() ?? '',
                    bound: route['direction']?.toString(),
                    serviceType: route['serviceType']?.toString(),
                    initialRouteId: route['initialRouteId']?.toString(),
                  );
                
              } else if (route['source'] == 'unified' || companyId == 'mtr' || companyId == 'lrt') {
                await UnifiedPinnedStorage.unpinRoute(
                  company: companyId,
                  route: route['route']?.toString() ?? '',
                  bound: route['direction']?.toString(),
                  serviceType: route['serviceType']?.toString(),
                  initialRouteId: route['initialRouteId']?.toString(),
                );
              } else {
                await Kmb.unpinRoute(
                  route['route'],
                  route['direction'],
                  route['serviceType'],
                );
              }
              await _loadData();
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
    final useUnifiedNav = context.watch<DeveloperSettingsProvider>().useUnifiedRouteStatusNavigation;
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15), width: 1.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final companyId = route['co']?.toString().toLowerCase() ?? 'kmb';
              if (useUnifiedNav) {
                final unifiedCompany = companyId == 'lrt' ? 'lightrail' : companyId;
                Navigator.push(
                  context,
                  EnhancedPageRoute(
                    builder: (context) => UnifiedRouteStatusPage(
                      route: routeNum,
                      companies: [unifiedCompany],
                      initialCompany: unifiedCompany,
                      bound: direction.isEmpty ? null : direction,
                      serviceType: serviceType,
                      initialRouteId: route['initialRouteId']?.toString() ?? route['routeId']?.toString(),
                    ),
                  ),
                ).then((_) => _loadData());
              } else {
                if (companyId == 'ctb' || companyId == 'nwfb') {
                  Navigator.push(
                    context,
                    EnhancedPageRoute(
                      builder: (context) => CtbRouteStatusPage(
                        route: routeNum,
                        bound: direction,
                        serviceType: null,  // CTB doesn't use service type
                        companyId: companyId,
                      ),
                    ),
                  ).then((_) => _loadData());
                } else if (companyId == 'kmb') {
                  Navigator.push(
                    context,
                    EnhancedPageRoute(
                      builder: (context) => KmbRouteStatusPage(
                        route: routeNum,
                        bound: direction,
                        serviceType: serviceType,
                        companyId: null,
                      ),
                    ),
                  ).then((_) => _loadData());
                } else {
                  final unifiedCompany = companyId == 'lrt' ? 'lightrail' : companyId;
                  Navigator.push(
                    context,
                    EnhancedPageRoute(
                      builder: (context) => UnifiedRouteStatusPage(
                        route: routeNum,
                        companies: [unifiedCompany],
                        initialCompany: unifiedCompany,
                        bound: direction.isEmpty ? null : direction,
                        serviceType: serviceType,
                        initialRouteId: route['initialRouteId']?.toString() ?? route['routeId']?.toString(),
                      ),
                    ),
                  ).then((_) => _loadData());
                }
              }
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: dirColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
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
                                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.8),
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
                                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
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
                          Text(timeText, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                        ],
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    switchInCurve: Curves.bounceIn,
                    switchOutCurve: Curves.bounceOut,
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
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
              final route = stop['route']?.toString() ?? '';
              final stopId = stop['stopId']?.toString() ?? '';
              final seq = stop['seq']?.toString() ?? '';
              // Optimistic UI update to avoid stale card lingering
              if (mounted) {
                setState(() {
                  _pinnedStops.removeWhere((s) =>
                      (s['route']?.toString() ?? '') == route &&
                      (s['stopId']?.toString() ?? '') == stopId &&
                      (s['seq']?.toString() ?? '') == seq);
                });
              }

              // ✅ Check company ID and call correct API
              final companyId = stop['co']?.toString().toLowerCase() ?? 'kmb';
              
              if (companyId == 'ctb' || companyId == 'nwfb') {
                await Citybus.unpinStop(
                  stop['route'],
                  stop['stopId'],
                  stop['seq'],
                  companyId: companyId,
                );
              } else if (companyId == 'kmb') {
                await Kmb.unpinStop(
                  stop['route'],
                  stop['stopId'],
                  stop['seq'],
                );
              } else if (companyId == 'gmb' && stop['source'] == 'gmb') {
                final gmbStopId = int.tryParse(stop['stopId']?.toString() ?? '');
                final routeCode = stop['route']?.toString() ?? '';
                if (gmbStopId != null && routeCode.isNotEmpty) {
                  await GMB.unpinStop(gmbStopId, routeCode);
                }
              } else {
                await UnifiedPinnedStorage.unpinStop(
                  company: companyId,
                  route: stop['route']?.toString() ?? '',
                  stopId: stop['stopId']?.toString() ?? '',
                  seq: stop['seq']?.toString() ?? '',
                );
              }
              
              await _loadData();
            },

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

  const PinnedStopCard({super.key, required this.stop, required this.lang, required this.onUnpin,});

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
  bool _hasNoScheduledBuses = false;  // ✅ ADD THIS

  // ✅ Add helper method to _PinnedStopCardState class
  String _formatEtaTime(DateTime dt) {
    // Respect device/user 24-hour preference when available
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    if (use24) {
      return DateFormat.Hm().format(dt); // 24-hour HH:mm (e.g., 17:30)
    } else {
      // jm() will format as e.g. 5:08 PM for en_US, or follow locale conventions
      final locale = Localizations.localeOf(context).toString();
      return DateFormat.jm(locale).format(dt);
    }
  }

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
      final stopId = widget.stop['stopId']?.toString() ?? '';
      final direction = widget.stop['direction']?.toString().trim().toUpperCase() ?? '';
      final companyId = widget.stop['co']?.toString().toLowerCase() ?? 'kmb';

      if (route.isEmpty || stopId.isEmpty) {
        setState(() {
          _etas = [];
          _loading = false;
        });
        return;
      }

      // ✅ Use route-stop ETA API (faster and more efficient)
      final List<Map<String, dynamic>> entries;

      if (companyId == 'ctb' || companyId == 'nwfb') {
        // CTB: Use fetchEta(stopId, route, companyId)
        final rawEntries = await Citybus.fetchEta(
          stopId,
          route,
          companyId: companyId,
        );
        entries = rawEntries.map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (companyId == 'kmb') {
        // KMB: Use fetchStopRouteEta(stopId, route, serviceType)
        final rawEntries = await Kmb.fetchStopRouteEta(stopId, route, serviceType);
        entries = rawEntries.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        entries = <Map<String, dynamic>>[];
      }
      
      if (!mounted) return;
    
      // ✅ Since we're using stop-specific API, we still need to filter by direction
      final directionChar = direction.isNotEmpty ? direction[0] : '';

      final freshEtas = entries.where((e) {
        // Match direction if available (some stops serve multiple directions)
        if (directionChar.isNotEmpty) {
          final etaDir = e['dir']?.toString().trim().toUpperCase() ?? 
                        e['bound']?.toString().trim().toUpperCase() ?? '';
          if (etaDir.isNotEmpty && etaDir[0] != directionChar) return false;
        }
        
        return true;
      }).toList();

      // Sort by ETA sequence
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
          _consecutiveErrors = 0;  // ✅ Reset errors on successful fetch
          _refreshInterval = const Duration(seconds: 15);
          
          // ✅ Track if this is "no schedule" vs "error"
          // If we got data from API but no ETAs match, it's likely time-constrained
          _hasNoScheduledBuses = freshEtas.isEmpty && entries.isNotEmpty;
          //_lastUpdated = DateTime.now();  // ✅ Track update time
        });
        _startAutoRefresh();
      }
    } catch (e) {
      debugPrint('❌ Error fetching ETAs: $e');
      
      _consecutiveErrors++;
      _refreshInterval = Duration(
        seconds: math.min(60, 15 * math.pow(2, _consecutiveErrors).toInt()),
      );
      _startAutoRefresh();
      
      if (mounted && !silent) {
        setState(() {
          _etas = [];
          _loading = false;
          _hasNoScheduledBuses = false;  // ✅ This is an error, not "no schedule"
        });
      }
    }
  }

  Color _getEtaColor(dynamic raw, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (raw == null) return Colors.grey;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final diff = dt.difference(DateTime.now());

      if (diff.isNegative) return isDark ? Colors.grey[600]! : Colors.grey;

      if (diff.inMinutes <= 2) {
        // M3 Error Color 或是稍柔和的紅色
        return Theme.of(context).colorScheme.error; 
      }
      if (diff.inMinutes <= 5) {
        // 橙色在 M3 深色模式下需要亮一點，淺色模式下深一點
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);
      }
      if (diff.inMinutes <= 10) {
        // 綠色同理
        return isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      }
      
      // 正常藍色 -> Primary
      return Theme.of(context).colorScheme.primary;
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEn = widget.lang.isEnglish;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Stop metadata
    final route = widget.stop['route']?.toString() ?? '';
    final companyId = widget.stop['co']?.toString() ?? 'KMB';
    final nameEn = widget.stop['stopNameEn'] ?? widget.stop['stopName'] ?? '';
    final nameTc = widget.stop['stopNameTc'] ?? widget.stop['stopName'] ?? '';
    final stopName = isEn
        ? (nameEn.toString().isNotEmpty ? nameEn.toString().toTitleCase() : nameTc.toString())
        : (nameTc.toString().isNotEmpty ? nameTc.toString() : nameEn.toString().toTitleCase());

    final destEnStr = widget.stop['destEn']?.toString() ?? '';
    final destTcStr = widget.stop['destTc']?.toString() ?? '';
    final dest = isEn
        ? (destEnStr.isNotEmpty ? destEnStr : destTcStr).toTitleCase()
        : (destTcStr.isNotEmpty ? destTcStr : destEnStr).toTitleCase();

    final direction = widget.stop['direction']?.toString() ?? 'O';
    final directionUpper = direction.toUpperCase();
    final isInbound = directionUpper.startsWith('I');
    
    final directionColor = isInbound ? cs.tertiary : cs.primary;
    final directionIcon = isInbound ? Icons.arrow_circle_left : Icons.arrow_circle_right;

    // ✅ CompanyProvider
    final companyProv = context.watch<CompanyProvider>();
    final badgeBgColor = companyProv.getBadgeBgColor(companyId, context);
    final badgeBorderColor = companyProv.getBadgeBorderColor(companyId, context);
    final badgeTextColor = companyProv.getBadgeTextColor(companyId, context);
    final companyName = companyProv.getName(companyId, isEn);

    final radius = BorderRadius.circular(16);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          // [修改點 1] 改為直角 (90 degree angle)
          borderRadius: radius, 
          border: Border.all(
            color: badgeBorderColor.withValues(alpha: 0.3),
            width: 1.0,
          ),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.04),
                    blurRadius: 0,
                    spreadRadius: 0.5,
                  ),
                ]
              : [
                  BoxShadow(
                    color: badgeBorderColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 2,
                    spreadRadius: 0,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          // [修改點 2] Material 也要改成直角，甚至可以移除此行（預設即為 zero）
          borderRadius: radius,
          // [修改點 3] 直角不需要 antiAlias，移除以優化效能 (Performance Optimization)
          clipBehavior: Clip.none, 
          child: InkWell(
            onTap: _handleTap,
            // [修改點 4] 水波紋邊界改為直角，確保填滿角落
            borderRadius: radius, 
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                children: [
                  _buildRouteBadge(
                    badgeBgColor, badgeBorderColor, badgeTextColor,
                    directionIcon, route, companyName,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStopInfo(cs, stopName, dest, directionColor, directionIcon),
                  ),
                  const SizedBox(width: 8),
                  _buildUnpinButton(cs),
                ],
              ),
            ),
          ),
        ),
      ),
    );

  }

  void _handleTap() {
    final route = widget.stop['route']?.toString() ?? '';
    final companyId = widget.stop['co']?.toString().toLowerCase() ?? 'kmb';
    final direction = widget.stop['direction']?.toString() ?? 'O';
    final serviceType = widget.stop['serviceType']?.toString() ?? '1';
    final seq = widget.stop['seq']?.toString();
    final stopId = widget.stop['stopId']?.toString();
    final initialRouteId = widget.stop['initialRouteId']?.toString();

    final useUnifiedNav = context.read<DeveloperSettingsProvider>().useUnifiedRouteStatusNavigation;
    final page = useUnifiedNav
        ? UnifiedRouteStatusPage(
            route: route,
            companies: [companyId == 'lrt' ? 'lightrail' : companyId],
            initialCompany: companyId == 'lrt' ? 'lightrail' : companyId,
            bound: direction,
            serviceType: serviceType,
            initialRouteId: initialRouteId,
            autoExpandSeq: seq,
            autoExpandStopId: stopId,
          )
        : (companyId == 'ctb' || companyId == 'nwfb')
            ? CtbRouteStatusPage(
                route: route,
                bound: direction,
                serviceType: null,
                companyId: companyId,
                autoExpandSeq: seq,
                autoExpandStopId: stopId,
              )
            : (companyId == 'kmb')
                ? KmbRouteStatusPage(
                    route: route,
                    bound: direction,
                    serviceType: serviceType,
                    companyId: null,
                    autoExpandSeq: seq,
                    autoExpandStopId: stopId,
                  )
                : UnifiedRouteStatusPage(
                    route: route,
                    companies: [companyId == 'lrt' ? 'lightrail' : companyId],
                    initialCompany: companyId == 'lrt' ? 'lightrail' : companyId,
                    bound: direction,
                    serviceType: serviceType,
                    initialRouteId: initialRouteId,
                    autoExpandSeq: seq,
                    autoExpandStopId: stopId,
                  );

    Navigator.push(context, EnhancedPageRoute(builder: (_) => page));
  }

  Widget _buildRouteBadge(
    Color bgColor, Color borderColor, Color textColor,
    IconData icon, String route, String companyName,
  ) {
    return ConstrainedBox(
      // 固定寬度範圍，確保 Expanded 中間區不會左右漂移
      constraints: const BoxConstraints(minWidth: 56, maxWidth: 72),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              route,
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(fontSize: 14, height: 1.2, forceStrutHeight: true),
            ),
            const SizedBox(height: 2),
            Icon(icon, color: textColor, size: 16),
            const SizedBox(height: 2),
            Text(
              companyName,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.8)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(fontSize: 9, height: 1.2, forceStrutHeight: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopInfo(
    ColorScheme cs,
    String stopName,
    String dest,
    Color directionColor,
    IconData directionIcon,
  ) {
    final lang = context.read<LanguageProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OptionalMarquee(
          text: stopName,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface),
        ),
        if (dest.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(directionIcon, size: 11, color: directionColor.withValues(alpha: 0.8)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${lang.to}: $dest',
                  style: TextStyle(
                    fontSize: 12,
                    color: directionColor.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        _buildEtaSection(cs),
      ],
    );
  }

  Widget _buildEtaSection(ColorScheme cs) {
    final lang = context.watch<LanguageProvider>();
    final isEn = lang.isEnglish;
    final bool noSchedule = _hasNoScheduledBuses;

    Widget content;
    if (_loading) {
      content = const SizedBox(
        key: ValueKey('loading'),
        height: 20,
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            height: 2,
            width: 100,
            child: LinearProgressIndicator(stopIndicatorRadius: 20, trackGap: 60),
          ),
        ),
      );
    } else if (_etas.isEmpty) {
      content = Text(
        key: const ValueKey('empty'),
        noSchedule
            ? (lang.endEta)
            : (isEn ? 'Service not available' : '服務暫停'),
        style: TextStyle(
          color: noSchedule ? Colors.grey.shade600 : Colors.orange.shade700,
          fontSize: 14,
          fontStyle: FontStyle.italic,
          height: 1.2,
        ),
        textAlign: TextAlign.left,
      );
    } else {
      content = Wrap(
        key: const ValueKey('etas'),
        spacing: 20,
        runSpacing: 12,
        alignment: WrapAlignment.start, 
        children: _etas.take(3).map(_buildEtaItem).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // [關鍵] 取得父元件可用寬度，強制所有 content 狀態都是全寬
        // 這樣 AnimatedSize 的 width 永遠不變，只有 height 在做動畫
        final double? fixedWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : null;

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubicEmphasized,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: fixedWidth, // 鎖定全寬，null = 不限制 (fallback)
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeInOutCubicEmphasized,
                switchOutCurve: Curves.easeInOutQuad,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEtaItem(Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final isEn = widget.lang.isEnglish;
    final etaRaw = e['eta'] ?? e['eta_time'];
    final rmk = isEn
        ? (e['rmk_en'] ?? e['rmktc'] ?? '').toString()
        : (e['rmk_tc'] ?? e['rmktc'] ?? e['rmk_en'] ?? '').toString();

    String etaText = isEn ? 'No upcoming buses' : '沒有即將到站的巴士';
    String etaTime = '';
    bool isDeparted = false;
    bool noEtaRemark = true;
    bool isNearlyArrived = false;

    if (etaRaw != null) {
      try {
        final now = DateTime.now();
        final dt = DateTime.parse(etaRaw.toString()).toLocal();
        final diff = dt.difference(now);
        final seconds = diff.inSeconds; // 統一用秒數判斷
        etaTime = _formatEtaTime(dt);

        if (seconds <= -60) {
          // 1. 已經離開超過 1 分鐘 -> 顯示負數或離站
          etaText = isEn ? '- min' : '- 分鐘'; // 或考慮顯示 "Departed" / "已離站"
          isDeparted = true;
          noEtaRemark = false;
        } else if (seconds <= 0) {
          // 2. 過去 1 分鐘內 (0 ~ -59s) -> 視為到達中
          etaText = isEn ? 'Arriving' : '到達中';
          isNearlyArrived = true;
          noEtaRemark = false;
        } else if (seconds < 60) {
          // 3. 未來 1 分鐘內 (1s ~ 59s) -> 即將抵達 (NOW)
          etaText = isEn ? 'NOW' : '即將抵達';
          isNearlyArrived = true;
          noEtaRemark = false;
        } else {
          // 4. 超過 1 分鐘 -> 顯示分鐘數
          // (seconds / 60).ceil() 確保 61秒顯示 "2 min" 而不是 "1 min" (視需求而定，通常 ceil 比較準)
          // 但 KMB/CTB 通常用 floor (inMinutes 預設是 floor)，這裡保留你的 inMinutes 邏輯
          final mins = diff.inMinutes; 
          etaText = isEn ? '$mins min' : '$mins分鐘';
          noEtaRemark = false;
        }

      } catch (_) {}
    }

    final textColor = isDeparted
        ? Colors.grey[400]
        : (isNearlyArrived ? Colors.green : _getEtaColor(etaRaw, context));

    // 估算：時間文字 "12 分鐘" 大約 50-60px，給稍微寬一點的空間
    return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: noEtaRemark ? 150 : 72), // 稍微放寬一點點給 "25分鐘"
        child: Column(
          // [關鍵] 讓所有子元件 (Text) 在 Column 內水平居中
          crossAxisAlignment: CrossAxisAlignment.center, 
          mainAxisSize: MainAxisSize.min,
          children: [
            AutoSizeText(
              etaText,
              minFontSize: 9,
              maxFontSize: noEtaRemark ? 15 : 22,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
              strutStyle: const StrutStyle(
                  fontSize: 20, height: 1.2, forceStrutHeight: true),
              maxLines: 1,
              //overflow: TextOverflow.visible,
              textAlign: TextAlign.center, // [關鍵] 文字內容居中
            ),
            if (etaTime.isNotEmpty)
              Text(
                etaTime,
                style: TextStyle(
                    fontSize: 9, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                strutStyle: const StrutStyle(
                    fontSize: 9, height: 1.2, forceStrutHeight: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center, // [關鍵]
              ),
            if (rmk.isNotEmpty)
              Text(
                rmk,
                style: TextStyle(
                    fontSize: 9, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                strutStyle: const StrutStyle(
                    fontSize: 9, height: 1.2, forceStrutHeight: true),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center, // [關鍵]
              ),
          ],
        ),
      );

  }

  Widget _buildUnpinButton(ColorScheme cs) {
    return IconButton(
      onPressed: widget.onUnpin,
      icon: const Icon(Icons.push_pin, size: 16),
      style: IconButton.styleFrom(
        backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
        foregroundColor: cs.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(6),
        // ↓ 這兩行是關鍵：移除 Material 預設 48×48 最小觸控目標
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }


}
