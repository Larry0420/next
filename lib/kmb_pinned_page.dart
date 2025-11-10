import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:async';
import 'kmb.dart';
import 'kmb_route_status_page.dart';
import 'main.dart' show LanguageProvider;

class KmbPinnedPage extends StatefulWidget {
  const KmbPinnedPage({Key? key}) : super(key: key);

  @override
  State<KmbPinnedPage> createState() => _KmbPinnedPageState();
}

class _KmbPinnedPageState extends State<KmbPinnedPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pinnedRoutes = [];
  List<Map<String, dynamic>> _pinnedStops = [];
  List<Map<String, dynamic>> _historyRoutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final pinned = await Kmb.getPinnedRoutes();
      final pinnedStops = await Kmb.getPinnedStops();
      final history = await Kmb.getRouteHistory();
      
      // Enrich pinned routes with destination info
      final enrichedRoutes = await _enrichWithDestination(pinned);
      
      // Enrich pinned stops with destination info
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
      // Build route index from cached API data
      final routeIndex = await Kmb.buildRouteIndex();
      
      final enriched = <Map<String, dynamic>>[];
      
      for (final item in items) {
        final route = item['route']?.toString().trim().toUpperCase();
        final direction = item['direction']?.toString() ?? 'O';
        final serviceType = item['serviceType']?.toString() ?? '1';
        
        if (route != null && route.isNotEmpty) {
          // Look up in route index
          final indexKey = '${route}_${direction}_$serviceType';
          final routeData = routeIndex[indexKey];
          
          if (routeData != null) {
            // Add destination info to the item
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
      // Return items as-is if enrichment fails
      return items;
    }
  }

  Future<List<Map<String, dynamic>>> _enrichStopsWithDestination(List<Map<String, dynamic>> stops) async {
    try {
      // Build route index from cached API data
      final routeIndex = await Kmb.buildRouteIndex();
      
      final enriched = <Map<String, dynamic>>[];
      
      for (final stop in stops) {
        final route = stop['route']?.toString().trim().toUpperCase();
        final direction = stop['direction']?.toString() ?? 'O';
        final serviceType = stop['serviceType']?.toString() ?? '1';
        
        // If destination is already cached, skip lookup
        if (stop['destEn'] != null || stop['destTc'] != null) {
          enriched.add(stop);
          continue;
        }
        
        if (route != null && route.isNotEmpty) {
          // Look up in route index
          final indexKey = '${route}_${direction}_$serviceType';
          final routeData = routeIndex[indexKey];
          
          if (routeData != null) {
            // Add destination info to the stop
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
      // Return stops as-is if enrichment fails
      return stops;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
  // (bottomInset is computed per-tab where needed)
    return Scaffold(
      // Use a Stack so we can place the TabBar visually above the app's bottom nav
      body: Stack(
        children: [
          // Main content (TabBarView)
          Positioned.fill(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPinnedTab(lang),
                      _buildPinnedStopsTab(lang),
                      _buildHistoryTab(lang),
                    ],
                  ),
          ),

          // Floating bottom TabBar placed above the global bottom navigation
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: true,
              bottom: false,
              child: Padding(
                // compute bottom offset so the bar sits above the app's bottom nav (~60) + small gap
                padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 12 + 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        /*gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.7),
                            Theme.of(context).colorScheme.surface.withOpacity(0.5),
                          ],
                        ),*/
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                          width: 1.0,
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,  
                        splashBorderRadius: BorderRadius.circular(12),
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: EdgeInsets.all(4),
                        labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
                        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(icon: Icon(Icons.push_pin, size: 20), text: lang.pinnedRoutes, height: 52),
                          Tab(icon: Icon(Icons.location_on, size: 20), text: lang.isEnglish ? 'Stops' : '站點', height: 52),
                          Tab(icon: Icon(Icons.history, size: 20), text: lang.history, height: 52),
                        ],
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
            SizedBox(height: 16),
            Text(
              lang.noPinnedRoutes,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              lang.pinRoutesToSeeThemHere,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
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
              await Kmb.unpinRoute(
                route['route'],
                route['direction'],
                route['serviceType'],
              );
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
            SizedBox(height: 16),
            Text(
              lang.noHistory,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              lang.viewedRoutesWillAppearHere,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
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
                  icon: Icon(Icons.delete_outline, size: 18),
                  label: Text(lang.clearHistory),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[700],
                  ),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(lang.clearAllHistory),
                        content: Text(lang.thisActionCannotBeUndone),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(lang.cancel),
                          ),
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
                return _buildCompactRouteCard(
                  route: route,
                  lang: lang,
                  isPinned: false,
                  showTimestamp: true,
                );
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
    
    // Get destination from enriched data
    final destEn = route['destEn'];
    final destTc = route['destTc'];
    final origEn = route['origEn'];
    final origTc = route['origTc'];
    
    // Format destination text
    String destinationText = '';
    if (lang.isEnglish) {
      final orig = origEn ?? origTc ?? '';
      final dest = destEn ?? destTc ?? '';
      if (orig.isNotEmpty && dest.isNotEmpty) {
        destinationText = lang.isEnglish ? 'From $orig to $dest' : '由 $orig 往 $dest';
      } else {
        destinationText = label.replaceFirst('$routeNum: ', '');
      }
    } else {
      final orig = origTc ?? origEn ?? '';
      final dest = destTc ?? destEn ?? '';
      if (orig.isNotEmpty && dest.isNotEmpty) {
        destinationText = lang.isEnglish ? 'From $orig to $dest' : '由 $orig 往 $dest';
      } else {
        destinationText = label.replaceFirst('$routeNum: ', '');
      }
    }
    
    // Parse timestamp
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

    // Direction icon
    IconData dirIcon = Icons.arrow_forward;
    Color dirColor = Colors.blue;
    if (direction.toUpperCase().startsWith('O')) {
      dirIcon = Icons.arrow_circle_right;
      dirColor = Colors.green;
    } else if (direction.toUpperCase().startsWith('I')) {
      dirIcon = Icons.arrow_circle_left;
      dirColor = Colors.orange;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                width: 1.0,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => KmbRouteStatusPage(
                        route: routeNum,
                        bound: direction,
                        serviceType: serviceType,
                      ),
                    ),
                  ).then((_) => _loadData());
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Compact direction icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: dirColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(dirIcon, color: dirColor, size: 20),
                      ),
                      SizedBox(width: 12),
                      
                      // Route info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Route number and service type badges
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: AutoSizeText(
                                    '${lang.route} $routeNum',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (serviceType != '1') ...[
                                  SizedBox(width: 6),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: AutoSizeText(
                                      '${lang.type}($serviceType)',
                                      style: TextStyle(fontSize: 10, color: Colors.blue[800], fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: 4),
                            // Route destination
                            AutoSizeText(
                              destinationText,
                              style: TextStyle(
                                fontSize: 14, 
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Timestamp
                            if (timeText != null) ...[
                              SizedBox(height: 2),
                              Text(
                                timeText,
                                style: TextStyle(
                                  fontSize: 10, 
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      // Action button
                      if (isPinned)
                        Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: InkWell(
                            onTap: onUnpin,
                            child: Icon(
                              Icons.push_pin,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.chevron_right, 
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                          size: 20,
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

  Widget _buildPinnedStopsTab(LanguageProvider lang) {
    if (_pinnedStops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on_outlined, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              lang.isEnglish ? 'No Pinned Stops' : '沒有釘選站點',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              lang.isEnglish ? 'Pin stops to see them here' : '釘選站點以在此處查看',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
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
          return _buildStopCard(
            stop: stop,
            lang: lang,
            onUnpin: () async {
              await Kmb.unpinStop(
                stop['route'],
                stop['stopId'],
                stop['seq'],
              );
              _loadData();
            },
            compact: _pinnedStops.length > 8,
          );
        },
      ),
    );
  }

  Widget _buildStopCard({
    required Map<String, dynamic> stop,
    required LanguageProvider lang,
    required VoidCallback onUnpin,
    bool compact = false,
  }) {
    return PinnedStopCard(
      stop: stop,
      lang: lang,
      onUnpin: onUnpin,
      compact: compact,
    );
  }
}

// Stateful widget for each pinned stop with ETA fetching
class PinnedStopCard extends StatefulWidget {
  final Map<String, dynamic> stop;
  final LanguageProvider lang;
  final VoidCallback onUnpin;
  final bool compact;

  const PinnedStopCard({
    Key? key,
    required this.stop,
    required this.lang,
    required this.onUnpin,
    this.compact = false,
  }) : super(key: key);

  @override
  State<PinnedStopCard> createState() => _PinnedStopCardState();
}

class _PinnedStopCardState extends State<PinnedStopCard> {
  Timer? _etaRefreshTimer;
  List<Map<String, dynamic>> _etas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchEtas();
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(PinnedStopCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh ETAs when language changes
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
    _etaRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) {
        _fetchEtas(silent: true);
      }
    });
  }

  Future<void> _fetchEtas({bool silent = false}) async {
    if (!silent) {
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
      
      // Get the first character of direction for matching (I or O)
      final directionChar = direction.isNotEmpty ? direction[0] : '';
      
      // Filter for this specific stop sequence AND direction
      final freshEtas = entries.where((e) {
        // Match sequence number
        if (e['seq']?.toString() != seq) return false;
        
        // Match direction if available
        if (directionChar.isNotEmpty) {
          final etaDir = e['dir']?.toString().trim().toUpperCase() ?? '';
          if (etaDir.isEmpty || etaDir[0] != directionChar) return false;
        }
        
        return true;
      }).toList();
      
      // Sort by eta_seq
      freshEtas.sort((a, b) {
        final ai = int.tryParse(a['eta_seq']?.toString() ?? '') ?? 0;
        final bi = int.tryParse(b['eta_seq']?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });
      
      if (mounted) {
        setState(() {
          _etas = freshEtas;
          _loading = false;
        });
      }
    } catch (e) {
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
      final now = DateTime.now();
      final diff = dt.difference(now);
      
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
    final stopName = widget.lang.isEnglish 
      ? (nameEn.isNotEmpty ? nameEn : nameTc)
      : (nameTc.isNotEmpty ? nameTc : nameEn);
    final latitude = widget.stop['latitude'];
    final longitude = widget.stop['longitude'];
    final destEn = widget.stop['destEn'];
    final destTc = widget.stop['destTc'];
    final dest = widget.lang.isEnglish 
      ? (destEn ?? destTc ?? '')
      : (destTc ?? destEn ?? '');
    final direction = widget.stop['direction']?.toString() ?? 'O';
    
    // Direction display
    Color directionColor = Colors.blue;
    IconData directionIcon = Icons.arrow_forward;
    
    if (direction.toUpperCase().startsWith('O')) {
      directionColor = Colors.green;
      directionIcon = Icons.arrow_circle_right;
    } else if (direction.toUpperCase().startsWith('I')) {
      directionColor = Colors.orange;
      directionIcon = Icons.arrow_circle_left;
    }
    // Lightweight compact rendering for long lists (faster, avoids BackdropFilter)
    if (widget.compact) {
      String? firstEtaText;
      if (_loading) {
        firstEtaText = null;
      } else if (_etas.isEmpty) {
        firstEtaText = null;
      } else {
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
              firstEtaText = widget.lang.isEnglish ? '${mins}m' : '${mins}分';
            }
          } catch (_) {
            firstEtaText = null;
          }
        }
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.06),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => KmbRouteStatusPage(
                      route: route,
                      bound: widget.stop['direction'],
                      serviceType: widget.stop['serviceType'],
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    // small route badge
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: directionColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(route, style: TextStyle(fontWeight: FontWeight.bold, color: directionColor, fontSize: 13)),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    // stop name + dest
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText(stopName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (dest.isNotEmpty) SizedBox(height: 2),
                          if (dest.isNotEmpty) Text(dest, style: TextStyle(fontSize: 11, color: directionColor.withOpacity(0.9)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    // ETA / loading indicator
                    if (_loading)
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (firstEtaText != null)
                      Text(firstEtaText, style: TextStyle(fontWeight: FontWeight.bold, color: _getEtaColor(_etas.isNotEmpty ? (_etas.first['eta'] ?? _etas.first['eta_time']) : null)))
                    else
                      SizedBox.shrink(),
                    SizedBox(width: 8),
                    // unpin
                    InkWell(
                      onTap: widget.onUnpin,
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Icon(Icons.push_pin, size: 18, color: Theme.of(context).colorScheme.primary),
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

    // Full (original) rich card
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              /*gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
                  Theme.of(context).colorScheme.surface.withOpacity(0.4),
                ],
              ),*/
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                width: 1.0,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // Navigate to route status page with this stop highlighted
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => KmbRouteStatusPage(
                        route: route,
                        bound: widget.stop['direction'],
                        serviceType: widget.stop['serviceType'],
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Route badge with direction
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: directionColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: directionColor.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Route number
                                Text(
                                  route,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: directionColor,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 2),
                                // Direction icon
                                Icon(
                                  directionIcon,
                                  color: directionColor,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 12),
                          
                          // Stop info and ETAs
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Stop name
                                Text(
                                  stopName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                
                                // Destination
                                if (dest.isNotEmpty) ...[
                                  SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        directionIcon,
                                        size: 11,
                                        color: directionColor.withOpacity(0.8),
                                      ),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          dest,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: directionColor.withOpacity(0.9),
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                
                                SizedBox(height: 6),
                                
                                // ETA times display
                                if (_loading)
                                  SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else if (_etas.isEmpty)
                                  Text(
                                    widget.lang.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: _etas.take(3).map((e) {
                                      final etaRaw = e['eta'] ?? e['eta_time'];
                                      final rmk = widget.lang.isEnglish 
                                        ? (e['rmk_en'] ?? '') 
                                        : (e['rmk_tc'] ?? '');
                                      String etaText = '—';
                                      bool isDeparted = false;
                                      bool isNearlyArrived = false;
                                      
                                      if (etaRaw != null) {
                                        try {
                                          final dt = DateTime.parse(etaRaw.toString()).toLocal();
                                          final now = DateTime.now();
                                          final diff = dt.difference(now);
                                          
                                          if (diff.inMinutes <= 0 && diff.inSeconds > -60) {
                                            etaText = widget.lang.isEnglish ? 'Arriving' : '到達中';
                                            isNearlyArrived = true;
                                          } else if (diff.isNegative) {
                                            etaText = '-';
                                            isDeparted = true;
                                          } else {
                                            final mins = diff.inMinutes;
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
                                          Text(
                                            etaText,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isDeparted 
                                                ? Colors.grey[400] 
                                                : (isNearlyArrived ? Colors.green : _getEtaColor(etaRaw)),
                                            ),
                                          ),
                                          if (rmk.isNotEmpty)
                                            Text(
                                              rmk,
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                              ),
                                            ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                
                                // Coordinates
                                if (latitude != null && longitude != null) ...[
                                  SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 11,
                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        '$latitude, $longitude',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          
                          // Unpin button
                          Ink(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: InkWell(
                              onTap: widget.onUnpin,
                              borderRadius: BorderRadius.circular(100),
                              child: Icon(
                                Icons.push_pin,
                                color: Theme.of(context).colorScheme.primary,
                                size: 25,
                              ),
                            ),
                          )

                        ],
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
