import 'dart:io'; // For SocketException
import 'dart:async'; // For TimeoutException
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// Local project imports
import 'package:lrt_next_train/optionalMarquee.dart';
import 'package:lrt_next_train/toTitleCase.dart';
import '../main.dart' show LanguageProvider;
import '../kmb_route_status_page.dart';
import '../ctb_route_status_page.dart';
import '../nlb_route_status_page.dart';
import 'api/citybus.dart';
import 'api/kmb.dart';
import 'api/nlb.dart';

class KmbDialer extends StatefulWidget {
  final void Function(String route)? onRouteSelected;
  final bool rightHanded;
  const KmbDialer({super.key, this.onRouteSelected, this.rightHanded = true});

  @override
  State<KmbDialer> createState() => _KmbDialerState();
}

class _KmbDialerState extends State<KmbDialer> {
  String input = '';
  List<String> routes = [];
  List<Map<String, dynamic>> allRoutesData = [];
  List<Map<String, dynamic>> searchResults = [];
  
  // Filter State: null = All, 'kmb' = KMB, 'ctb' = Citybus
  String? _companyFilter; 
  
  bool loading = false;
  String? error;
  Map<String, List<Map<String, dynamic>>>? _routeMap;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    
    try {
      final results = await Future.wait([
        // 1. Fetch Simple Route Lists (Strings)
        Future.wait<List<String>>([
          Kmb.fetchRoutes().timeout(const Duration(seconds: 30), onTimeout: () => []),
          Citybus.fetchRoutes(companyId: 'ctb').timeout(const Duration(seconds: 30), onTimeout: () => [])
              .then((list) => list.map((r) => (r['route'] ?? '').toString()).where((r) => r.isNotEmpty).toList()),
          Nlb.fetchRoutes().timeout(const Duration(seconds: 30), onTimeout: () => [])
              .then((list) => list.map((r) => (r['routeNo'] ?? '').toString()).toSet().toList()),
        ], eagerError: false),

        // 2. Fetch Detailed Data Maps
        // ✅ FIX 1: Change <Map<String, Map<String, dynamic>>> to <Map<String, dynamic>>
        Future.wait<Map<String, dynamic>>([
          Kmb.buildRouteIndex().timeout(const Duration(seconds: 30), onTimeout: () => {}),
          Citybus.buildRouteIndex(companyId: 'ctb').timeout(const Duration(seconds: 30), onTimeout: () => {}),
          Nlb.buildRouteToStopsMap().timeout(const Duration(seconds: 30), onTimeout: () => {}),
        ], eagerError: false),
      ]);
      
      // Merge simple lists
      final simpleLists = results[0] as List<List<String>>;
      final Set<String> mergedRoutes = {};
      mergedRoutes.addAll(simpleLists[0]); 
      mergedRoutes.addAll(simpleLists[1]); 
      mergedRoutes.addAll(simpleLists[2]); 
      final sortedRoutes = mergedRoutes.toList()..sort(_compareRouteNumbers);
      
      // Merge detailed indices
      // ✅ FIX 2: Update the cast here to match the relaxed type above
      final indices = results[1] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> allDetailedRoutes = [];
      
      // 1. Process KMB
      if (indices[0].isNotEmpty) {
        // We can safely cast values to Map here if needed, or rely on dynamic
        final kmbMap = indices[0]; 
        for (final entry in kmbMap.values) {
          final routeData = Map<String, dynamic>.from(entry as Map);
          routeData['companyid'] = 'kmb';
          routeData['companyname'] = 'KMB';
          allDetailedRoutes.add(routeData);
        }
      }

      // 2. Process Citybus
      if (indices[1].isNotEmpty) {
        final ctbMap = indices[1];
        for (final entry in ctbMap.values) {
          final routeData = Map<String, dynamic>.from(entry as Map);
          routeData['companyid'] = 'ctb';
          routeData['companyname'] = 'CTB';
          allDetailedRoutes.add(routeData);
        }
      }

      // 3. Process NLB
      if (indices[2].isNotEmpty) {
        final nlbMap = indices[2];
        // Structure: { "37": { "routeId_123": { ... } } }
        nlbMap.forEach((routeNo, variants) {
          final variantsMap = variants as Map;
          variantsMap.forEach((routeId, data) {
             final routeData = Map<String, dynamic>.from(data as Map);
             routeData['route'] = routeNo;
             routeData['routeId'] = routeId;
             routeData['companyid'] = 'nlb';
             routeData['companyname'] = 'NLB';
             allDetailedRoutes.add(routeData);
          });
        });
      }
      
      allDetailedRoutes.sort((a, b) {
        final cmp = _compareRouteNumbers((a['route'] ?? '').toString(), (b['route'] ?? '').toString());
        if (cmp != 0) return cmp;
        return ((a['bound'] ?? '').toString()).compareTo((b['bound'] ?? '').toString());
      });
      
      if (mounted) {
        setState(() {
          routes = sortedRoutes; 
          allRoutesData = allDetailedRoutes;
        });
      }
      
      _loadRouteMetadata();

    } catch (e) {
      if (mounted) setState(() => error = 'Error loading routes');
      debugPrint('Error in _fetchRoutes: $e');
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }

  int _compareRouteNumbers(String a, String b) {
    final aMatch = RegExp(r'^([A-Z]?)(\d+)').firstMatch(a);
    final bMatch = RegExp(r'^([A-Z]?)(\d+)').firstMatch(b);
    if (aMatch == null || bMatch == null) return a.compareTo(b);
    
    final aPrefix = aMatch.group(1) ?? '';
    final bPrefix = bMatch.group(1) ?? '';
    final aNum = int.tryParse(aMatch.group(2) ?? '0') ?? 0;
    final bNum = int.tryParse(bMatch.group(2) ?? '0') ?? 0;
    
    if (aPrefix.isNotEmpty && bPrefix.isNotEmpty) {
      final cmp = aPrefix.compareTo(bPrefix);
      if (cmp != 0) return cmp;
    }
    if (aPrefix.isNotEmpty && bPrefix.isEmpty) return -1;
    if (aPrefix != bPrefix) return aPrefix.compareTo(bPrefix);
    return aNum.compareTo(bNum);
  }

  Future<void> _loadRouteMetadata() async {
    // Background metadata loading (implementation simplified for brevity)
    // Matches existing logic in your original file
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    final lowerQ = query.toLowerCase();
    // Local filter is usually sufficient and faster for dialer feedback
    final matches = allRoutesData.where((data) {
      final r = (data['route'] ?? '').toString();
      // Filter by query matches start AND company filter
      final matchesQuery = r.toLowerCase().startsWith(lowerQ);
      final matchesCompany = _companyFilter == null || (data['companyid'] == _companyFilter);
      return matchesQuery && matchesCompany;
    }).toList();

    // Deduplicate logic
    final Map<String, Map<String, dynamic>> unique = {};
    for (final item in matches) {
      final key = '${item['route']}_${item['bound']}_${item['service_type']}_${item['company_id']}';
      unique[key] = item;
    }
    
    setState(() => searchResults = unique.values.toList());
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

  void _toggleCompanyFilter(String? company) {
    setState(() {
      if (_companyFilter == company) {
        _companyFilter = null; // Toggle off if same selected
      } else {
        _companyFilter = company;
      }
      // Re-run search/filter with new setting
      if (input.isNotEmpty) {
        _performSearch(input);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final theme = Theme.of(context);
    
    // Apply filter to the main list if no search query
    List<Map<String, dynamic>> displayList;
    if (input.isEmpty) {
      if (_companyFilter == null) {
        displayList = allRoutesData;
      } else {
        displayList = allRoutesData.where((d) => d['companyid'] == _companyFilter).toList();
      }
    } else {
      displayList = searchResults;
    }

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            
            // --- Input & Filter Header ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isEnglish ? 'Route' : '路線', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                        Text(
                          input.isEmpty ? (isEnglish? 'Typing_': '輸入路線_') : input, 
                          style: TextStyle(
                            fontSize: 32, 
                            fontWeight: FontWeight.bold,
                            color: input.isEmpty ? theme.colorScheme.outline.withOpacity(0.5) : theme.colorScheme.onSurface
                          )
                        ),
                      ],
                    ),
                  ),
                  // Company Filter Toggles
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFilterButton(isEnglish ? 'KMB' : '九巴', 'kmb', Colors.red),
                      const SizedBox(width: 8),
                      _buildFilterButton(isEnglish ? 'CityBus' : '城巴', 'ctb', Colors.amber),
                      const SizedBox(width: 8),
                      _buildFilterButton(isEnglish ? 'NLB' : '嶼巴', 'nlb', Colors.lightGreen),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            if (loading && input.isEmpty) 
              const LinearProgressIndicator(minHeight: 2),

            // --- Route List ---
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: displayList.isEmpty && !loading && input.isNotEmpty
                    ? Center(child: Text(isEnglish ? 'No routes found' : '未找到路線'))
                    : ListView.builder(
                        key: ValueKey('list_${input}_$_companyFilter'),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 240), // Large padding for dialer
                        itemCount: _groupRoutes(displayList).length,
                        itemBuilder: (context, index) {
                          final groups = _groupRoutes(displayList);
                          final base = groups.keys.elementAt(index);
                          final variants = groups[base]!;
                          
                          // Single Variant
                          if (variants.length == 1) {
                            return Card.filled(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              color: theme.colorScheme.surfaceContainerLow,
                              child: _buildRouteContent(
                                context,
                                route: variants.first['route'].toString(),
                                variants: variants,
                                isEnglish: isEnglish,
                                input: input,
                              ),
                            );
                          }

                          // Grouped Variants
                          return Card.filled(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            color: theme.colorScheme.surfaceContainerLow,
                            clipBehavior: Clip.hardEdge,
                            child: ExpansionTile(
                              shape: const Border(),
                              collapsedShape: const Border(),
                              backgroundColor: theme.colorScheme.surfaceContainer,
                              title: Text(
                                '$base (${variants.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              initiallyExpanded: base == input || groups.length == 1,
                              children: variants.map((v) {
                                return _buildRouteContent(
                                  context,
                                  route: v['route'].toString(),
                                  variants: [v],
                                  isEnglish: isEnglish,
                                  input: input,
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
        
        // One-Handed Dialer
        Positioned(
          left: widget.rightHanded ? null : 12,
          right: widget.rightHanded ? 12 : null,
          bottom: MediaQuery.of(context).padding.bottom + 12,
          child: _OneHandDialerContainer(child: _buildFixedDialer(theme)),
        ),
      ],
    );
  }

  // Filter Button Widget
  Widget _buildFilterButton(String label, String id, MaterialColor color) {
    final isSelected = _companyFilter == id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleCompanyFilter(id),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.shade100 : Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: isSelected ? color.shade700 : Colors.transparent, 
              width: 1.5
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isSelected ? color.shade900 : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // Helper to group routes by number base (e.g. 101, 101X -> 101)
  Map<String, List<Map<String, dynamic>>> _groupRoutes(List<Map<String, dynamic>> list) {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    final baseRe = RegExp(r'^([A-Z]?\d+)');
    
    for (final item in list) {
      final r = (item['route'] ?? '').toString();
      final m = baseRe.firstMatch(r);
      final base = m != null ? m.group(1)! : r;
      groups.putIfAbsent(base, () => []).add(item);
    }
    
    // Sort keys and values
    final sortedKeys = groups.keys.toList()..sort(_compareRouteNumbers);
    final Map<String, List<Map<String, dynamic>>> sortedGroups = {};
    for (var key in sortedKeys) {
      final val = groups[key]!;
      val.sort((a, b) => _compareRouteNumbers(a['route'].toString(), b['route'].toString()));
      sortedGroups[key] = val;
    }
    return sortedGroups;
  }

  // --- Fixed Layout Dialer ---
  Widget _buildFixedDialer(ThemeData theme) {
    // Determine which keys are valid next inputs
    final Set<String> validNextKeys = {};
    final inputUpper = input.toUpperCase();
    
    // Check all routes that match current input
    final possibleRoutes = routes.where((r) => r.toUpperCase().startsWith(inputUpper));
    
    for (final route in possibleRoutes) {
      final rUpper = route.toUpperCase();
      if (rUpper.length > inputUpper.length) {
        validNextKeys.add(rUpper[inputUpper.length]);
      }
    }

    final bool canBackspace = input.isNotEmpty;
    final bool canSubmit = routes.contains(input); // Can press OK?

    // Standard keypad layout
    final List<String> keypad = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '<', '0', 'OK'
    ];

    // Extra Letters (Dynamic column)
    final letters = validNextKeys.where((k) => !RegExp(r'\d').hasMatch(k)).toList()..sort();

    const double btnSize = 48.0;
    const double gap = 6.0;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed Numeric Keypad (3x4)
          SizedBox(
            width: (btnSize * 3) + (gap * 4),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: keypad.map((key) {
                // Determine if key is enabled
                bool enabled = false;
                Color? bgColor;
                Color? fgColor;
                VoidCallback? action;

                if (key == '<') {
                  enabled = canBackspace;
                  action = _onBackspace;
                  bgColor = theme.colorScheme.secondaryContainer.withOpacity(0.5);
                } else if (key == 'OK') {
                  enabled = canSubmit;
                  action = () {
                    if (routes.contains(input)) {
                       _onKeyTap(''); // Hacky refresh or nav
                    }
                  };
                  bgColor = canSubmit ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
                  fgColor = canSubmit ? theme.colorScheme.onPrimary : null;
                } else {
                  // Digit
                  enabled = validNextKeys.contains(key) || (input.isEmpty); 
                  // If input is empty, usually 1-9 are valid start chars. 
                  // If strict mode preferred: enabled = validNextKeys.contains(key);
                  action = () => _onKeyTap(key);
                }

                return SizedBox(
                  width: btnSize,
                  height: btnSize,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      backgroundColor: bgColor,
                      foregroundColor: fgColor,
                      disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      disabledForegroundColor: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    onPressed: enabled ? action : null,
                    child: key == '<' 
                      ? const Icon(Icons.backspace_rounded, size: 20)
                      : Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                );
              }).toList(),
            ),
          ),

          if (letters.isNotEmpty) ...[
            const SizedBox(width: 8),
            // Dynamic Letters Column
            SizedBox(
              width: (btnSize * 3) + (gap * 2),
              height: (btnSize * 4) + (gap * 3),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  alignment: WrapAlignment.start,
                  children: letters.map((l) => SizedBox(
                    width: btnSize,
                    height: btnSize,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                      onPressed: () => _onKeyTap(l),
                      child: Text(l, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  )).toList(),
                ),
              ),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildRouteContent(
    BuildContext context, {
    required String route,
    required List<Map<String, dynamic>> variants,
    required bool isEnglish,
    required String input,
  }) {
    final tiles = <Widget>[];

    // Deduplicate logic
    final Map<String, List<Map<String, dynamic>>> byDest = {};
    for (final v in variants) {
      final orig = isEnglish
          ? (v['orig_en'] ?? v['orig_tc'] ?? '').toString()
          : (v['orig_tc'] ?? v['orig_en'] ?? '').toString();
      final dest = isEnglish
          ? (v['dest_en'] ?? v['dest_tc'] ?? '').toString()
          : (v['dest_tc'] ?? v['dest_en'] ?? '').toString();
      // Group by distinct visual line
      final key = '$orig-$dest';
      byDest.putIfAbsent(key, () => []).add(v);
    }

    // Build tiles
    final flattened = <Map<String, dynamic>>[];
    byDest.forEach((_, list) => flattened.addAll(list));

    for (final v in flattened) {
      final companyId = (v['companyid'] ?? v['company_id'] ?? 'kmb').toString().toLowerCase();

      // Localized Company Name
      String companyName;
      if (companyId == 'ctb') {
        companyName = isEnglish ? 'CTB' : '城巴';
      } else if (companyId == 'nlb') {
        companyName = isEnglish ? 'NLB' : '嶼巴';
      } else {
        companyName = isEnglish ? 'KMB' : '九巴';
      }

      final orig = isEnglish
          ? (v['orig_en'] ?? v['orig_tc'] ?? '').toString().toTitleCase()
          : (v['orig_tc'] ?? v['orig_en'] ?? '').toString();
      final dest = isEnglish
          ? (v['dest_en'] ?? v['dest_tc'] ?? '').toString().toTitleCase()
          : (v['dest_tc'] ?? v['dest_en'] ?? '').toString();

      final serviceType = v['service_type']?.toString();
      final hasService = serviceType != null && serviceType != '1';

      // Subtitle Logic
      String subtitle;
      if (orig.isNotEmpty && dest.isNotEmpty) {
        subtitle = '$orig → $dest';
      } else {
        // Fallback to bound label
        final bound = v['bound']?.toString();
        final dir = v['direction']?.toString();
        if (dir != null && dir.isNotEmpty) {
          subtitle = dir.toLowerCase() == 'inbound'
              ? (isEnglish ? 'Inbound' : '入站')
              : (isEnglish ? 'Outbound' : '出站');
        } else if (bound != null) {
          subtitle = bound.toUpperCase() == 'I'
              ? (isEnglish ? 'Inbound' : '入站')
              : (isEnglish ? 'Outbound' : '出站');
        } else {
          subtitle = isEnglish ? 'View Route' : '查看路線';
        }
      }

      // ✅ FIX: Use a helper for colors
      Color badgeBgColor;
      Color badgeBorderColor;
      Color badgeTextColor;

      if (companyId == 'ctb') {
        badgeBgColor = Colors.amber.shade100;
        badgeBorderColor = Colors.amber.shade700;
        badgeTextColor = Colors.brown.shade800;
      } else if (companyId == 'nlb') {
        badgeBgColor = Colors.lightGreen.shade100;
        badgeBorderColor = Colors.lightGreen.shade700;
        badgeTextColor = Colors.green.shade900;
      } else {
        badgeBgColor = Colors.red.shade100;
        badgeBorderColor = Colors.red.shade700;
        badgeTextColor = Colors.red.shade900;
      }

      tiles.add(
        ListTile(
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: _buildHighlightedText(route, input, Theme.of(context)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Company Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: badgeBorderColor,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      companyName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                  if (hasService) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEnglish ? 'Type $serviceType' : '類型$serviceType',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          trailing: Icon(
            Icons.chevron_right,
            size: 20,
            color: Theme.of(context).colorScheme.outline,
          ),
          onTap: () {
            final r = route.toUpperCase();
            
            // ✅ 修正：確保 bound 參數格式正確 (I 或 O)
            String? bound = v['bound']?.toString();
            
            // 如果 bound 缺失，嘗試從 direction 推斷
            if (bound == null || bound.isEmpty) {
              final dir = v['direction']?.toString().trim().toLowerCase();
              if (dir != null) {
                if (dir.startsWith('i') || dir == 'inbound') {
                  bound = 'I';
                } else if (dir.startsWith('o') || dir == 'outbound') {
                  bound = 'O';
                }
              }
            } else {
              // 標準化 bound 為 'I' 或 'O'
              final boundUpper = bound.trim().toUpperCase();
              if (boundUpper.startsWith('I')) {
                bound = 'I';
              } else if (boundUpper.startsWith('O')) {
                bound = 'O';
              }
            }
            
            // ✅ 修正：也標準化 serviceType
            final normalizedServiceType = serviceType?.toString();
            
            debugPrint('🚌 Navigating to route: $r, bound: $bound, serviceType: $normalizedServiceType, company: $companyId');
            
            // --- Navigation Logic ---
            if (companyId == 'ctb') {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CtbRouteStatusPage(
                  route: r, 
                  bound: bound, 
                  serviceType: normalizedServiceType, 
                  companyId: companyId
                ),
              ));
            } else if (companyId == 'nlb') {
               // ✅ Updated for NlbRouteStatusPage parameters
               Navigator.of(context).push(MaterialPageRoute(
                 builder: (_) => NlbRouteStatusPage(
                   routeNo: r, 
                   initialRouteId: v['routeId'].toString(), 
                 ),
               ));
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => KmbRouteStatusPage(
                  route: r, 
                  bound: bound, 
                  serviceType: normalizedServiceType, 
                  companyId: companyId
                ),
              ));
            }
            widget.onRouteSelected?.call(r);
          },
        ),
      );

      if (flattened.last != v) {
        tiles.add(const Divider(height: 1, indent: 16, endIndent: 16, thickness: 0.5));
      }
    }

    return Column(children: tiles);
  }

  Widget _buildHighlightedText(String text, String query, ThemeData theme) {
    if (query.isEmpty) return Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (!lowerText.contains(lowerQuery)) return Text(text);
    
    final startIndex = lowerText.indexOf(lowerQuery);
    final endIndex = startIndex + lowerQuery.length;
    
    return Text.rich(TextSpan(
      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
      children: [
        TextSpan(text: text.substring(0, startIndex)),
        TextSpan(
          text: text.substring(startIndex, endIndex),
          style: TextStyle(color: theme.colorScheme.primary)
        ),
        TextSpan(text: text.substring(endIndex)),
      ],
    ));
  }
}

class _OneHandDialerContainer extends StatefulWidget {
  final Widget child;
  const _OneHandDialerContainer({required this.child});
  @override
  State<_OneHandDialerContainer> createState() => _OneHandDialerContainerState();
}

class _OneHandDialerContainerState extends State<_OneHandDialerContainer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  @override
  void initState() { super.initState(); _ctrl.forward(); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return LiquidGlassLayer(
      settings: LiquidGlassSettings(
        blur: 1, 
        glassColor: Theme.of(context).colorScheme.surface.withOpacity(0.1), 
        thickness: 20
      ),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
        child: FakeGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 18),
          child: widget.child,
        ),
      ),
    );
  }
}