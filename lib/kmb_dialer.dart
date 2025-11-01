import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:provider/provider.dart';
import 'kmb.dart';
import 'kmb_route_status_page.dart';
import 'main.dart' show LanguageProvider;

class KmbDialer extends StatefulWidget {
  final void Function(String route)? onRouteSelected;
  // When true the dialer is positioned to favor right-hand one-handed use.
  final bool rightHanded;
  const KmbDialer({Key? key, this.onRouteSelected, this.rightHanded = true}) : super(key: key);

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

    String? _normChar(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim().toUpperCase();
      if (s.isEmpty) return null;
      final c = s[0];
      if (c == 'I' || c == 'O') return c;
      return null;
    }

    final Set<String> dirs = {};
    for (final e in entries) {
      final b = _normChar(e['bound']);
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
  final baseFromInput = RegExp(r'^(\d+)').firstMatch(input)?.group(1);
    // We'll use a Stack so the dialer can float in a one-handed position
    return Stack(
      children: [
        // Main column holds header and (conditionally visible) routes list
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(lang.isEnglish ? 'Enter Route:' : '輸入路線:', style: TextStyle(fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(input, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            ),
            SizedBox(height: 8),

            // status indicators
            if (loading) Center(child: CircularProgressIndicator()),
            if (error != null) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Text('${lang.isEnglish ? "Error" : "錯誤"}: $error', style: TextStyle(color: Colors.red)),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _fetchRoutes,
                    child: Text(lang.isEnglish ? 'Retry' : '重試'),
                  ),
                ],
              ),
            ),

            // AnimatedSwitcher for the routes list: hidden when input is empty
            AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: (!loading && error == null && input.isNotEmpty)
                  ? LayoutBuilder(
                      key: ValueKey('routes_list'),
                      builder: (context, constraints) {
                        // Cap the list height to avoid overflow on tall/narrow screens (like 18:9)
                        final maxHeight = MediaQuery.of(context).size.height * 0.38;
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: Builder(builder: (_) {
                            // Group display routes by their numeric base (e.g., '11', '11A' -> base '11')
                            final Map<String, List<Map<String, dynamic>>> groups = {};
                            final baseRe = RegExp(r'^(\d+)');
                            for (final routeData in displayRoutes) {
                              final route = routeData['route'] as String;
                              final m = baseRe.firstMatch(route);
                              final base = m != null ? m.group(1)! : route;
                              groups.putIfAbsent(base, () => []).add(routeData);
                            }

                            // Sort group keys numerically where possible
                            final sortedBases = groups.keys.toList()
                              ..sort((a, b) {
                                final ai = int.tryParse(a);
                                final bi = int.tryParse(b);
                                if (ai != null && bi != null) return ai.compareTo(bi);
                                return a.compareTo(b);
                              });

                            final isEnglish = lang.isEnglish;
                            final List<Widget> tiles = [];
                            for (final base in sortedBases) {
                              final variants = groups[base]!..sort((x, y) {
                                // prefer the plain numeric base (e.g. '11') before letter variants (e.g. '11A')
                                final routeX = x['route'] as String;
                                final routeY = y['route'] as String;
                                if (routeX == base && routeY != base) return -1;
                                if (routeY == base && routeX != base) return 1;
                                // otherwise fallback to lexical order
                                return routeX.compareTo(routeY);
                              });

                              if (variants.length == 1) {
                                final routeData = variants.first;
                                final route = routeData['route'] as String;

                                // Check if we have multiple direction/service variants for this route in search results
                                final routeVariants = displayRoutes.where((r) => r['route'] == route).toList();
                                
                                // Group variants by unique origin-destination pairs to detect circular routes and service types
                                final Map<String, List<Map<String, dynamic>>> routesByDestination = {};
                                for (final variant in routeVariants) {
                                  final orig = isEnglish ? (variant['orig_en'] ?? '') : (variant['orig_tc'] ?? '');
                                  final dest = isEnglish ? (variant['dest_en'] ?? '') : (variant['dest_tc'] ?? '');
                                  final key = '$orig→$dest';
                                  routesByDestination.putIfAbsent(key, () => []).add(variant);
                                }
                                
                                if (routesByDestination.length > 1 || (routesByDestination.length == 1 && routesByDestination.values.first.length > 1)) {
                                  // Multiple destination pairs or multiple service types - show each variant
                                  final List<Widget> variantTiles = [];
                                  
                                  for (final destEntry in routesByDestination.entries) {
                                    final destVariants = destEntry.value;
                                    
                                    for (final variant in destVariants) {
                                      final bound = variant['bound'] as String?;
                                      final direction = variant['direction'] as String?;
                                      final serviceType = variant['service_type'] as String?;
                                      
                                      // Get origin and destination with language preference
                                      final orig = isEnglish 
                                        ? (variant['orig_en']?.toString().trim() ?? variant['orig_tc']?.toString().trim() ?? '')
                                        : (variant['orig_tc']?.toString().trim() ?? variant['orig_en']?.toString().trim() ?? '');
                                      final dest = isEnglish
                                        ? (variant['dest_en']?.toString().trim() ?? variant['dest_tc']?.toString().trim() ?? '')
                                        : (variant['dest_tc']?.toString().trim() ?? variant['dest_en']?.toString().trim() ?? '');
                                      
                                      String? subtitleText;
                                      
                                      // Check if we have origin and destination data
                                      if (orig.isNotEmpty && dest.isNotEmpty) {
                                        // Check if it's a circular route
                                        final isCircular = (variant['orig_en'] == variant['dest_en'] && variant['orig_en'] != null) ||
                                                          (variant['orig_tc'] == variant['dest_tc'] && variant['orig_tc'] != null);
                                        
                                        if (isCircular) {
                                          // Circular route - show direction instead of origin→dest
                                          final dirLabel = bound == 'O' 
                                            ? (isEnglish ? 'Outbound (Circular)' : '往程（循環線）')
                                            : (isEnglish ? 'Inbound (Circular)' : '返程（循環線）');
                                          subtitleText = serviceType != null && serviceType != '1' 
                                            ? '$dirLabel - Type $serviceType' 
                                            : dirLabel;
                                        } else {
                                          // Normal route - show origin → destination
                                          subtitleText = serviceType != null && serviceType != '1'
                                            ? '$orig → $dest (Type $serviceType)'
                                            : '$orig → $dest';
                                        }
                                      } else {
                                        // Fallback: show direction label if no origin/destination data
                                        final dirLabel = bound == 'O' 
                                          ? (isEnglish ? 'Outbound' : '往程')
                                          : bound == 'I'
                                            ? (isEnglish ? 'Inbound' : '返程')
                                            : (direction == 'outbound' 
                                                ? (isEnglish ? 'Outbound' : '往程')
                                                : (isEnglish ? 'Inbound' : '返程'));
                                        
                                        subtitleText = serviceType != null && serviceType != '1'
                                          ? '$dirLabel (Type $serviceType)'
                                          : dirLabel;
                                      }
                                      
                                      variantTiles.add(ListTile(
                                        title: _buildHighlightedText(route, input),
                                        subtitle: Text(subtitleText, style: TextStyle(fontSize: 13)),
                                        onTap: () {
                                          final r = route.toUpperCase();
                                          Navigator.of(context).push(MaterialPageRoute(
                                            builder: (_) => KmbRouteStatusPage(route: r, bound: bound, serviceType: serviceType)));
                                          widget.onRouteSelected?.call(r);
                                        },
                                      ));
                                    }
                                  }
                                  
                                  tiles.add(
                                    Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      color: theme.colorScheme.surfaceVariant,
                                      child: Column(children: variantTiles),
                                    ),
                                  );
                                  continue;
                                }

                                // Single variant - show as before
                                String? subtitleText;
                                if (routeData.containsKey('orig_en') && routeData.containsKey('dest_en')) {
                                  final orig = isEnglish ? (routeData['orig_en'] ?? '') : (routeData['orig_tc'] ?? '');
                                  final dest = isEnglish ? (routeData['dest_en'] ?? '') : (routeData['dest_tc'] ?? '');
                                  if (orig.isNotEmpty && dest.isNotEmpty) {
                                    subtitleText = '$orig → $dest';
                                  }
                                }

                                if (subtitleText == null) {
                                  final dirLabel = _directionLabelForRoute(route);
                                  final dest = _destinationForRoute(route, isEnglish);
                                  subtitleText = dest ?? dirLabel;
                                }

                                final subtitleWidget = subtitleText != null ? Text(subtitleText) : null;

                                // Detect if this single variant route actually has multiple bounds (I/O).
                                final bounds = <String>{};
                                if (_routeMap != null) {
                                  final rKey = route.toUpperCase();
                                  final baseKey = RegExp(r'^(\d+)').firstMatch(rKey)?.group(1) ?? rKey;
                                  final entries = _routeMap![rKey] ?? _routeMap![baseKey] ?? [];
                                  for (final e in entries) {
                                    final b = (e['bound'] == null) ? null : e['bound'].toString().toUpperCase();
                                    if (b != null && b.isNotEmpty) bounds.add(b[0]);
                                  }
                                }

                                if (bounds.length <= 1) {
                                  tiles.add(
                                    Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      color: theme.colorScheme.surfaceVariant,
                                        child: ListTile(
                                          title: _buildHighlightedText(route, input),
                                          subtitle: subtitleWidget,
                                          onTap: () {
                                            final r = route.toUpperCase();
                                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r)));
                                            widget.onRouteSelected?.call(r);
                                          },
                                        ),
                                    ),
                                  );
                                } else {
                                  // Multiple bounds: show a card containing per-bound choices
                                  final List<Widget> boundTiles = [];
                                  final ordered = bounds.toList()..sort();
                                  for (final b in ordered) {
                                    final destForBound = _destinationForRouteBound(route, b, isEnglish);
                  final label = (b == 'I')
                    ? (isEnglish ? 'Inbound' : '返程')
                    : (b == 'O')
                      ? (isEnglish ? 'Outbound' : '往程')
                      : b;
                                    boundTiles.add(ListTile(
                                      title: _buildHighlightedText(route, input),
                                      subtitle: destForBound != null ? Text(destForBound) : Text(label),
                                      onTap: () {
                                        final r = route.toUpperCase();
                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r, bound: b)));
                                        widget.onRouteSelected?.call(r);
                                      },
                                    ));
                                  }
                                  tiles.add(
                                    Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      color: theme.colorScheme.surfaceVariant,
                                      child: Column(children: boundTiles),
                                    ),
                                  );
                                }
                              } else {
                                tiles.add(
                                  Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    color: theme.colorScheme.surfaceVariant,
                                    child: ExpansionTile(
                                      title: Text('$base (${variants.length})', style: theme.textTheme.titleMedium),
                                      // auto-expand the group that matches the numeric base typed, or expand if it's the only group
                                      initiallyExpanded: baseFromInput == base || sortedBases.length == 1,
                                      children: variants.map((routeData) {
                                        final route = routeData['route'] as String;
                                        final bound = routeData['bound'] as String?;
                                        final direction = routeData['direction'] as String?;
                                        final serviceType = routeData['service_type'] as String?;

                                        // Use destination from search results if available
                                        String? subtitleText;
                                        if (routeData.containsKey('orig_en') && routeData.containsKey('dest_en')) {
                                          final orig = isEnglish ? (routeData['orig_en'] ?? '') : (routeData['orig_tc'] ?? '');
                                          final dest = isEnglish ? (routeData['dest_en'] ?? '') : (routeData['dest_tc'] ?? '');
                                          
                                          // Check if circular route
                                          final isCircular = orig == dest && orig.isNotEmpty;
                                          
                                          if (orig.isNotEmpty && dest.isNotEmpty) {
                                            if (isCircular) {
                                              // Circular route - show direction
                                              final dirLabel = bound == 'O' 
                                                ? (isEnglish ? 'Outbound (Circular)' : '往程（循環線）')
                                                : bound == 'I'
                                                  ? (isEnglish ? 'Inbound (Circular)' : '返程（循環線）')
                                                  : (isEnglish ? 'Circular' : '循環線');
                                              subtitleText = serviceType != null && serviceType != '1' 
                                                ? '$dirLabel - Type $serviceType' 
                                                : dirLabel;
                                            } else {
                                              subtitleText = serviceType != null && serviceType != '1'
                                                ? '$orig → $dest (Type $serviceType)'
                                                : '$orig → $dest';
                                            }
                                          }
                                        }

                                        // Fallback to direction label
                                        if (subtitleText == null && direction != null) {
                                          subtitleText = direction == 'outbound' 
                                            ? (isEnglish ? 'Outbound' : '往程')
                                            : (isEnglish ? 'Inbound' : '返程');
                                          if (serviceType != null && serviceType != '1') {
                                            subtitleText = '$subtitleText (Type $serviceType)';
                                          }
                                        }

                                        // Final fallback to route-stop map
                                        if (subtitleText == null) {
                                          final dirLabel = _directionLabelForRoute(route);
                                          final dest = _destinationForRoute(route, isEnglish);
                                          subtitleText = dest ?? dirLabel;
                                        }

                                        final subtitleWidget = subtitleText != null ? Text(subtitleText, style: TextStyle(fontSize: 13)) : null;

                                        // Check if this specific variant has a known bound
                                        if (bound != null && bound.isNotEmpty) {
                                          // We have bound information from the route list API
                                          return ListTile(
                                            title: _buildHighlightedText(route, input),
                                            subtitle: subtitleWidget,
                                            onTap: () {
                                              Navigator.of(context).push(MaterialPageRoute(
                                                builder: (_) => KmbRouteStatusPage(route: route, bound: bound, serviceType: serviceType)));
                                              widget.onRouteSelected?.call(route);
                                            },
                                          );
                                        }

                                        // Otherwise check route-stop map for bounds
                                        final bounds = <String>{};
                                        if (_routeMap != null) {
                                          final rKey = route.toUpperCase();
                                          final baseKey = RegExp(r'^(\d+)').firstMatch(rKey)?.group(1) ?? rKey;
                                          final entries = _routeMap![rKey] ?? _routeMap![baseKey] ?? [];
                                          for (final e in entries) {
                                            final b = (e['bound'] == null) ? null : e['bound'].toString().toUpperCase();
                                            if (b != null && b.isNotEmpty) bounds.add(b[0]);
                                          }
                                        }

                                        if (bounds.length <= 1) {
                                          return ListTile(
                                            title: _buildHighlightedText(route, input),
                                            subtitle: subtitleWidget,
                                            onTap: () {
                                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: route)));
                                              widget.onRouteSelected?.call(route);
                                            },
                                          );
                                        }

                                        // Multiple bounds -> render multiple ListTiles, one per bound
                                        final List<Widget> boundTiles = [];
                                        final ordered = bounds.toList()..sort();
                                        for (final b in ordered) {
                                          final destForBound = _destinationForRouteBound(route, b, isEnglish);
                                          final label = (b == 'I')
                                            ? (isEnglish ? 'Inbound' : '返程')
                                            : (b == 'O')
                                              ? (isEnglish ? 'Outbound' : '往程')
                                              : b;
                                                    boundTiles.add(ListTile(
                                                      title: _buildHighlightedText(route, input),
                                                      subtitle: destForBound != null ? Text(destForBound) : Text(label),
                                                      onTap: () {
                                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: route, bound: b)));
                                                        widget.onRouteSelected?.call(route);
                                                      },
                                                    ));
                                                  }
                                                  return Column(children: boundTiles);
                                      }).toList(),
                                    ),
                                  ),
                                );
                              }
                            }

                            if (tiles.isEmpty) {
                              return Center(child: Text('No routes found'));
                            }

                            return ListView(children: tiles);
                          }),
                        );
                      },
                    )
                  : SizedBox.shrink(),
            ),

            SizedBox(height: 24), // smaller spacer to reduce overall vertical footprint
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

    // When input is empty, show digits that appear as first char in routes (0-9)
    List<String> keys;
    if (input.isEmpty) {
      keys = nextKeys.where((k) => RegExp(r"^\d$").hasMatch(k)).toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    } else {
      // If input currently contains only digits and length < 4, allow next digit or letter
      // but cap route length to typical max (digits up to 3 plus optional letter)
      keys = nextKeys.toList()..sort();
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
                    padding: EdgeInsets.all(gap / 2),
                    child: SizedBox(
                      width: btnSize,
                      height: btnSize,
                      child: isEmpty
                          ? SizedBox.shrink()
                          : ElevatedButton(
                              onPressed: () {
                                if (key == backKey) _onBackspace();
                                else if (key == okKey) {
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
                                minimumSize: Size(btnSize, btnSize),
                              ),
                              child: Text(key, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),

          SizedBox(width: 8),

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
                        padding: EdgeInsets.all(gap / 2),
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
                                  minimumSize: Size(btnSize, btnSize),
                                  elevation: 0,
                                ),
                                child: Text(letter, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              );
                            }

                            // If no letter for this cell, try to place back/OK here if needed
                            if (!digitGrid.any((row) => row.contains(backKey))) {
                              return ElevatedButton(
                                onPressed: _onBackspace,
                                child: Icon(Icons.backspace_outlined, color: theme.colorScheme.onPrimaryContainer),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
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
                                child: Text('OK', style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                              );
                            }

                            return SizedBox.shrink();
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
  Widget _buildHighlightedText(String text, String query) {
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
  const _OneHandDialerContainer({Key? key, required this.child}) : super(key: key);

  @override
  State<_OneHandDialerContainer> createState() => _OneHandDialerContainerState();
}

class _OneHandDialerContainerState extends State<_OneHandDialerContainer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 300));

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
    return ScaleTransition(
      scale: CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6)),
              ],
              border: Border.all(color: Colors.white10),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
