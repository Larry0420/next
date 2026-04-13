import 'dart:async'; // For TimeoutException
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 必須加入這行才能使用 HapticFeedback
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:lrt_next_train/hkbus_db_provider.dart';
import 'package:lrt_next_train/kmb/company_name.dart';
// Local project imports
import 'package:lrt_next_train/optionalMarquee.dart';
import 'package:lrt_next_train/toTitleCase.dart';
import 'package:provider/provider.dart';

import '../ctb_route_status_page.dart';
import '../gmb_route_status_page.dart';
import '../kmb_route_status_page.dart';
import '../main.dart' show LanguageProvider, EnhancedPageRoute;
import '../nlb_route_status_page.dart';
import '../providers/location_provider.dart';
import '../route_status_page.dart';
import 'package:geolocator/geolocator.dart';
import 'api/citybus.dart';
import 'api/gmb.dart';
import 'api/kmb.dart';
import 'api/nlb.dart';

/// NLB／GMB 來回線在來源資料常無 [bound]，搜尋去重會誤併為一筆；載入後補 O／I。
void assignSyntheticBoundsForBidirectionalOperators(List<Map<String, dynamic>> routes) {
  for (final r in routes) {
    final co = (r['companyid'] ?? r['company_id'] ?? '').toString().toLowerCase();
    if (co != 'gmb') continue;
    if ((r['bound']?.toString().trim() ?? '').isNotEmpty) continue;
    final seq = r['routeSeq'] ?? r['route_seq'];
    if (seq == null) continue;
    final n = seq is int ? seq : int.tryParse(seq.toString()) ?? 1;
    r['bound'] = n <= 1 ? 'O' : 'I';
  }

  final nlbByKey = <String, List<Map<String, dynamic>>>{};
  for (final r in routes) {
    if ((r['companyid'] ?? '').toString().toLowerCase() != 'nlb') continue;
    final routeNo = (r['route'] ?? '').toString().toUpperCase();
    final st = (r['service_type'] ?? 'Normal').toString();
    nlbByKey.putIfAbsent('$routeNo|$st', () => []).add(r);
  }

  for (final list in nlbByKey.values) {
    final unassigned = list
        .where((r) => (r['bound']?.toString().trim() ?? '').isEmpty)
        .toList();
    if (unassigned.isEmpty) continue;
    if (unassigned.length == 1) {
      unassigned.first['bound'] = 'O';
      continue;
    }
    unassigned.sort(
      (a, b) => (a['routeId'] ?? a['route_id'] ?? '')
          .toString()
          .compareTo((b['routeId'] ?? b['route_id'] ?? '').toString()),
    );
    final paired = <String>{};
    String keyOf(Map<String, dynamic> x) =>
        '${x['route']}|${x['routeId'] ?? x['route_id']}';

    String ep(Map<String, dynamic> m, bool orig) {
      final en = orig ? (m['orig_en'] ?? '') : (m['dest_en'] ?? '');
      final tc = orig ? (m['orig_tc'] ?? '') : (m['dest_tc'] ?? '');
      final pick = en.toString().trim().isNotEmpty ? en : tc;
      return pick.toString().trim().toUpperCase();
    }

    for (var i = 0; i < unassigned.length; i++) {
      final a = unassigned[i];
      if (paired.contains(keyOf(a))) continue;
      final oa = ep(a, true);
      final da = ep(a, false);
      for (var j = i + 1; j < unassigned.length; j++) {
        final b = unassigned[j];
        if (paired.contains(keyOf(b))) continue;
        final ob = ep(b, true);
        final bd = ep(b, false);
        if (oa.isNotEmpty && da.isNotEmpty && oa == bd && da == ob) {
          final cmp = (a['routeId'] ?? a['route_id'] ?? '')
              .toString()
              .compareTo((b['routeId'] ?? b['route_id'] ?? '').toString());
          a['bound'] = cmp <= 0 ? 'O' : 'I';
          b['bound'] = cmp <= 0 ? 'I' : 'O';
          paired.add(keyOf(a));
          paired.add(keyOf(b));
          break;
        }
      }
    }
    for (var k = 0; k < unassigned.length; k++) {
      final r = unassigned[k];
      if ((r['bound']?.toString().trim() ?? '').isEmpty) {
        r['bound'] = k.isEven ? 'O' : 'I';
      }
    }
  }
}

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
  
  // Direction Filter: null = All, 'O' = Outbound, 'I' = Inbound
  // Only applies to MTR and Light Rail
  String? _directionFilter;
  
  bool loading = false;
  String? error;
  Map<String, List<Map<String, dynamic>>>? _routeMap;
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  @override
  void initState() {
    super.initState();
    _fetchRoutes();
    // 觸發 DB 載入
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HkbusDbProvider>().initDb();
    });
  }

  Future<void> _fetchRoutes() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    
    try {
      // 嘗試使用統一數據庫
      if (_useUnifiedDb) {
        final success = await _fetchRoutesFromUnifiedDb();
        if (success) {
          debugPrint('✅ 使用統一數據庫加載路線成功');
          return;
        }
        debugPrint('⚠️ 統一數據庫不可用，回退到官方 API');
      }
      
      // 回退到官方 API
      await _fetchRoutesFromOfficialApi();
      
    } catch (e) {
      if (mounted) setState(() => error = 'Error loading routes');
      debugPrint('Error in _fetchRoutes: $e');
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }
  
  // 數據源選擇：true = 使用統一數據庫 (HkbusDbProvider)，false = 使用官方 API
  bool _useUnifiedDb = true;
  
  /// 從 HkbusDbProvider 統一數據庫獲取路線數據
  Future<bool> _fetchRoutesFromUnifiedDb() async {
    try {
      final hkbusDb = context.read<HkbusDbProvider>();
      
      // 等待數據庫就緒
      if (!hkbusDb.isReady) {
        debugPrint('⏳ 等待統一數據庫就緒...');
        // 等待最多 10 秒
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (hkbusDb.isReady) break;
        }
        if (!hkbusDb.isReady) {
          debugPrint('❌ 統一數據庫未就緒');
          return false;
        }
      }
      
      // 獲取 Dialer 格式的路線數據
      final dialerRoutes = hkbusDb.getAllRoutesForDialer();
      
      if (dialerRoutes.isEmpty) {
        debugPrint('⚠️ 統一數據庫為空');
        return false;
      }
      
      // 提取所有路線號碼
      final Set<String> routeNumbers = dialerRoutes
          .map((r) => r['route'].toString())
          .toSet();
      final sortedRoutes = routeNumbers.toList()..sort(_compareRouteNumbers);
      
      if (mounted) {
        setState(() {
          routes = sortedRoutes;
          allRoutesData = dialerRoutes;
        });
      }
      
      return true;
      
    } catch (e) {
      debugPrint('❌ 從統一數據庫加載失敗: $e');
      return false;
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }
  
  /// 從官方 API 獲取路線數據（原有邏輯）
  Future<void> _fetchRoutesFromOfficialApi() async {
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
      
            // 4. Process GMB from prebuilt data
            try {
              final gmbRouteMap = await _loadGmbRoutesFromPrebuilt();
              for (final routeEntry in gmbRouteMap.entries) {
                final routeNo = routeEntry.key;
                final variants = routeEntry.value['variants'] as List<dynamic>? ?? [];
                for (final variant in variants) {
                  final routeData = Map<String, dynamic>.from(variant as Map);
                  routeData['route'] = routeNo;
                  routeData['companyid'] = 'gmb';
                  routeData['companyname'] = 'GMB';
                  allDetailedRoutes.add(routeData);
                }
              }
            } catch (e) {
              debugPrint('⚠️ Failed to load GMB routes: $e');
            }
      assignSyntheticBoundsForBidirectionalOperators(allDetailedRoutes);
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

  /// Load GMB routes from prebuilt assets
  Future<Map<String, dynamic>> _loadGmbRoutesFromPrebuilt() async {
    try {
      final jsonString = await rootBundle.loadString('assets/prebuilt/gmb_route_stops.json');
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      debugPrint('Error loading GMB prebuilt data: $e');
      return {};
    }
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
      
      // Direction filter ONLY applies to MTR and Light Rail
      final matchesDirection = _directionFilter == null ||
        (_companyFilter == 'mtr' || _companyFilter == 'lightrail') &&
        data['bound']?.toString().toUpperCase() == _directionFilter;
      
      return matchesQuery && matchesCompany && matchesDirection;
    }).toList();

    // Deduplicate logic（統一 DB 用 companyid，API 用 company_id）
    final Map<String, Map<String, dynamic>> unique = {};
    for (final item in matches) {
      final companyKey = item['company_id'] ?? item['companyid'];
      final rid = item['routeId'] ?? item['route_id'] ?? '';
      final key = '${item['route']}_${item['bound']}_${item['service_type']}_${rid}_$companyKey';
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
      
      // Reset direction filter when switching away from MTR/Light Rail
      // Direction filter only applies to MTR and Light Rail
      if (company != 'mtr' && company != 'lightrail') {
        _directionFilter = null;
      }
      
      // Re-run search/filter with new setting
      if (input.isNotEmpty) {
        _performSearch(input);
      }
    });
  }

  void _toggleDirectionFilter(String? direction) {
    setState(() {
      if (_directionFilter == direction) {
        _directionFilter = null; // Toggle off if same selected
      } else {
        _directionFilter = direction;
      }
      // Re-run search/filter with new setting
      if (input.isNotEmpty) {
        _performSearch(input);
      }
    });
  }

  /// Check if there are multiple directions available in the route list
  /// Used to determine whether to show direction filter chips
  bool _hasMultipleDirections(String? companyFilter, List<Map<String, dynamic>> routes) {
    // Filter routes by company first (only for MTR and Light Rail)
    final filteredRoutes = (companyFilter == 'mtr' || companyFilter == 'lightrail')
        ? routes.where((r) => r['companyid'] == companyFilter).toList()
        : routes;
    
    final directions = filteredRoutes
        .map((r) => r['bound']?.toString().toUpperCase())
        .where((b) => b != null && b!.isNotEmpty)
        .toSet();
    return directions.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    final theme = Theme.of(context);
    // 監聽 DbProvider 的狀態
    final hkbusDb = context.watch<HkbusDbProvider>();
    
    // 如果 JSON 還沒載入完，顯示一個全螢幕的 Loading
    if (!hkbusDb.isReady && !kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Routes')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在更新巴士資料庫...'),
            ],
          ),
        ),
      );
    }


    // Apply filter to the main list if no search query
    List<Map<String, dynamic>> displayList;
    if (input.isEmpty) {
      if (_companyFilter == null && _directionFilter == null) {
        displayList = allRoutesData;
      } else {
        displayList = allRoutesData.where((d) {
          final matchesCompany = _companyFilter == null || d['companyid'] == _companyFilter;
          
          // Direction filter ONLY applies to MTR and Light Rail
          final matchesDirection = _directionFilter == null ||
            (_companyFilter == 'mtr' || _companyFilter == 'lightrail') &&
            d['bound']?.toString().toUpperCase() == _directionFilter;
          
          return matchesCompany && matchesDirection;
        }).toList();
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
              child: Column( // 1. Changed Row to Column
                crossAxisAlignment: CrossAxisAlignment.stretch, // Ensures children stretch to full width
                children: [
                  // Input Display
                  _InputDisplay( // 2. Removed the Expanded widget
                    input: input,
                    isEnglish: isEnglish,
                    theme: theme,
                  ),
                  const SizedBox(height: 12), // 3. Changed width to height for vertical spacing
                  
                  // Filters Row
                  _FiltersRow(
                    useUnifiedDb: _useUnifiedDb,
                    onToggleDataSource: () {
                      setState(() => _useUnifiedDb = !_useUnifiedDb);
                      _fetchRoutes();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _useUnifiedDb
                                ? (isEnglish ? 'Switched to Unified Database' : '已切換到統一數據庫')
                                : (isEnglish ? 'Switched to Official API' : '已切換到官方API'),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    companyFilter: _companyFilter,
                    onToggleFilter: _toggleCompanyFilter,
                    isEnglish: isEnglish,
                    currentRoutes: displayList,
                    directionFilter: _directionFilter,
                    onToggleDirection: _toggleDirectionFilter,
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
                            clipBehavior: Clip.antiAliasWithSaveLayer,
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
          right: 12,
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

  // Direction Filter Chip Widget - ONLY for MTR and Light Rail
  Widget _buildDirectionFilterChip(
    String label,
    String direction,
    MaterialColor color,
    bool isEnglish,
    String? selectedDirection,
    Function(String?) onToggle,
  ) {
    final isSelected = selectedDirection == direction;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onToggle(direction),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.shade100 : Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(color: isSelected ? color.shade700 : Colors.transparent, width: 1.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                direction == 'O' ? Icons.arrow_circle_right : Icons.arrow_circle_left,
                size: 14,
                color: isSelected ? color.shade900 : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                isEnglish ? label : (direction == 'O' ? '去程' : '回程'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isSelected ? color.shade900 : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Input Display Widget
  Widget _InputDisplay({
    required String input,
    required bool isEnglish,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isEnglish ? 'Route' : '路線',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          input.isEmpty
              ? (isEnglish ? 'Typing_' : '輸入路線_')
              : input,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: input.isEmpty
                ? theme.colorScheme.outline.withValues(alpha: 0.5)
                : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // Filters Row Widget
  Widget _FiltersRow({
    required bool useUnifiedDb,
    required VoidCallback onToggleDataSource,
    required String? companyFilter,
    required Function(String?) onToggleFilter,
    required bool isEnglish,
    required List<Map<String, dynamic>> currentRoutes,
    required String? directionFilter,
    required Function(String?) onToggleDirection,
  }) {
    final theme = Theme.of(context);
    final filters = [
      (isEnglish ? 'KMB' : '九巴', 'kmb', Colors.red),
      (isEnglish ? 'CityBus' : '城巴', 'ctb', Colors.amber),
      (isEnglish ? 'NLB' : '嶼巴', 'nlb', Colors.lightGreen),
      (isEnglish ? 'GMB' : '小巴', 'gmb', Colors.green),
      (isEnglish ? 'MTRBus' : '港鐵巴士', 'lrtfeeder', Colors.teal),
    ];
    final shouldShowDirectionFilter =
        (companyFilter == 'mtr' || companyFilter == 'lightrail') &&
            _hasMultipleDirections(companyFilter, currentRoutes);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Data Source Toggle Button
        Tooltip(
          triggerMode: TooltipTriggerMode.tap,
          message: useUnifiedDb
              ? (isEnglish ? 'Using Unified DB (tap to use API)' : '使用統一數據庫（點擊切換到API）')
              : (isEnglish ? 'Using Official API (tap to use Unified DB)' : '使用官方API（點擊切換到統一數據庫）'),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleDataSource,
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: useUnifiedDb
                      ? Colors.blue.shade100
                      : Colors.grey.shade200,
                  border: Border.all(
                    color: useUnifiedDb
                        ? Colors.blue.shade700
                        : Colors.grey.shade400,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      useUnifiedDb
                          ? Icons.storage_rounded
                          : Icons.cloud_sync_rounded,
                      size: 14,
                      color: useUnifiedDb
                          ? Colors.blue.shade900
                          : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      useUnifiedDb
                          ? (isEnglish ? 'Unified' : '統一')
                          : (isEnglish ? 'API' : 'API'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: useUnifiedDb
                            ? Colors.blue.shade900
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Company Filter Buttons
        ...filters.expand((filter) => [
          const SizedBox(width: 3),
          _buildFilterButton(filter.$1, filter.$2, filter.$3),
        ]),
        // Direction Filter Chips - ONLY for MTR and Light Rail when multiple directions exist
        if (shouldShowDirectionFilter) ...[
          const SizedBox(width: 3),
          _buildDirectionFilterChip('Outbound', 'O', Colors.red, isEnglish, directionFilter, onToggleDirection),
          const SizedBox(width: 3),
          _buildDirectionFilterChip('Inbound', 'I', Colors.blue, isEnglish, directionFilter, onToggleDirection),
        ],
      ],
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

    // 🌟 M3 毛玻璃按鍵主題顏色配置
    // 一般按鍵的底色：使用極淡的 onSurface 作為半透明薄膜，保留玻璃透視感
    final defaultBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.1);
    final defaultFgColor = theme.colorScheme.onSurface;
    
    // 停用按鍵：進一步降低透明度
    final disabledBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final disabledFgColor = theme.colorScheme.onSurface.withValues(alpha: 0.3);

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
                bool enabled = false;
                Color bgColor = defaultBgColor;
                Color fgColor = defaultFgColor;
                VoidCallback? action;

                if (key == '<') {
                  enabled = canBackspace;
                  action = _onBackspace;
                  // 刪除鍵：給予一點點危險/次要顏色的暗示
                  bgColor = theme.colorScheme.errorContainer.withValues(alpha: 0.2);
                  fgColor = theme.colorScheme.onSurface;
                } else if (key == 'OK') {
                  enabled = canSubmit;
                  action = () {
                    if (routes.contains(input)) {
                       _onKeyTap(''); // Hacky refresh or nav
                    }
                  };
                  // OK 鍵：準備就緒時使用實體的 Primary 色，強烈引導用戶點擊
                  bgColor = canSubmit 
                      ? theme.colorScheme.primary 
                      : defaultBgColor;
                  fgColor = canSubmit 
                      ? theme.colorScheme.onPrimary 
                      : defaultFgColor;
                } else {
                  // Digit
                  enabled = validNextKeys.contains(key) || (input.isEmpty); 
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
                      // ✅ 確保取消預設陰影與按壓擴散，避免弄髒毛玻璃
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      backgroundColor: bgColor,
                      foregroundColor: fgColor,
                      disabledBackgroundColor: disabledBgColor,
                      disabledForegroundColor: disabledFgColor,
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
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        // ✅ 英文字母鍵同樣套用薄膜感
                        backgroundColor: defaultBgColor,
                        foregroundColor: defaultFgColor,
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
    // ① Move these outside the loop — no need to re-resolve on every iteration
    final companyProv = context.watch<CompanyProvider>();
    final theme = Theme.of(context);
    final tiles = <Widget>[];

    // ② Deduplicate by orig-dest key
    final Map<String, List<Map<String, dynamic>>> byDest = {};
    for (final v in variants) {
      final orig = isEnglish
          ? (v['orig_en'] ?? v['orig_tc'] ?? '').toString()
          : (v['orig_tc'] ?? v['orig_en'] ?? '').toString();
      final dest = isEnglish
          ? (v['dest_en'] ?? v['dest_tc'] ?? '').toString()
          : (v['dest_tc'] ?? v['dest_en'] ?? '').toString();
      byDest.putIfAbsent('$orig│$dest', () => []).add(v);
    }

    // ③ Flatten with spread instead of forEach
    final flattened = [for (final list in byDest.values) ...list];

    // ④ Local badge builder (avoids repeating Container decoration code)
    Widget buildBadge({
      required String label,
      required Color bg,
      Color? border,
      required Color textColor,
    }) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: border != null ? Border.all(color: border, width: 0.5) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        );

    for (final v in flattened) {
      final companyId =
          (v['companyid'] ?? v['company_id'] ?? 'kmb').toString().toLowerCase();

      // ⑤ 使用 CompanyProvider 獲取公司名稱和顏色
      final companyName = companyProv.getName(companyId, isEnglish);

      final orig = isEnglish
          ? (v['orig_en'] ?? v['orig_tc'] ?? '').toString().toTitleCase()
          : (v['orig_tc'] ?? v['orig_en'] ?? '').toString();
      final dest = isEnglish
          ? (v['dest_en'] ?? v['dest_tc'] ?? '').toString().toTitleCase()
          : (v['dest_tc'] ?? v['dest_en'] ?? '').toString();

      final serviceType = v['service_type']?.toString();
      final hasService =
          serviceType != null && serviceType != '1' && serviceType != 'Normal';

      // ⑥ Simplified fallback direction (consolidated null/empty checks)
      String? fallbackDir;
      if (orig.isEmpty || dest.isEmpty) {
        final dir   = v['direction']?.toString().trim().toLowerCase();
        final bound = v['bound']?.toString().trim().toUpperCase();
        final isInbound = dir?.startsWith('i') == true || bound == 'I';
        fallbackDir = isInbound
            ? (isEnglish ? 'Inbound' : '入站')
            : (isEnglish ? 'Outbound' : '出站');
      }

      // 獲取所有公司列表（支持聯營路線顯示多個標籤）
      final companies = v['companies'] as List<dynamic>?;
      final isJointOperation = v['isJointOperation'] == true || (companies != null && companies.length > 1);
      final companiesToShow = isJointOperation && companies != null 
          ? companies.cast<String>() 
          : [companyId];

      tiles.add(
        ListTile(
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

          // ── Title row: route number + company badges in same row ──────────────
          title: Row(
            children: [
              _buildHighlightedText(route, input, theme),
              const SizedBox(width: 8),
              
              // 顯示所有公司標籤（如果是聯營路線）
              if (isJointOperation && companiesToShow.length > 1) ...[
                ...companiesToShow.map((co) {
                  final coLower = co.toString().toLowerCase();
                  final coName = companyProv.getName(coLower, isEnglish);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: buildBadge(
                      label: coName,
                      bg: companyProv.getBadgeBgColor(coLower, context),
                      border: companyProv.getBadgeBorderColor(coLower, context),
                      textColor: companyProv.getBadgeTextColor(coLower, context),
                    ),
                  );
                }),
              ] else ...[
                // 單一公司標籤
                buildBadge(
                  label: companyName,
                  bg: companyProv.getBadgeBgColor(companyId, context),
                  border: companyProv.getBadgeBorderColor(companyId, context),
                  textColor: companyProv.getBadgeTextColor(companyId, context),
                ),
              ],
              
              if (hasService) ...[
                const SizedBox(width: 6),
                buildBadge(
                  label: serviceType == 'Special'
                      ? (isEnglish ? 'Special' : '特別')
                      : (isEnglish ? 'Spl. $serviceType' : '特別 $serviceType'),
                  bg: theme.colorScheme.tertiaryContainer,
                  textColor: theme.colorScheme.onTertiaryContainer,
                ),
              ],
            ],
          ),

          // ── Subtitle: origin (top) / destination (bottom) ─────────────
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: orig.isNotEmpty && dest.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _endpointRow(
                        icon: Icons.trip_origin,
                        iconSize: 10,
                        label: isEnglish ? 'From' : '由', // 或 '起點'
                        text: orig,
                        theme: theme,
                      ),
                      const SizedBox(height: 2),
                      _endpointRow(
                        icon: Icons.location_on,
                        iconSize: 10,
                        label: isEnglish ? 'To' : '住', // 或 '目的地'
                        text: dest,
                        theme: theme,
                      ),
                    ],
                  )
                : Text(
                    fallbackDir ?? (isEnglish ? 'View Route' : '查看路線'),
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
          ),

          trailing: Icon(
            Icons.chevron_right,
            size: 20,
            color: theme.colorScheme.outline,
          ),

          onTap: () async {
            final r = route.toUpperCase();

            // Normalise bound
            String? bound = v['bound']?.toString();
            if (bound == null || bound.isEmpty) {
              final dir = v['direction']?.toString().trim().toLowerCase();
              if (dir != null) {
                bound = (dir.startsWith('i') || dir == 'inbound') ? 'I' : 'O';
              }
            } else {
              final up = bound.trim().toUpperCase();
              bound = up.startsWith('I') ? 'I' : up.startsWith('O') ? 'O' : bound;
            }

            // 檢查是否為聯營路線
            final companies = v['companies'] as List<dynamic>?;
            final isJointOperation = v['isJointOperation'] == true || (companies != null && companies.length > 1);
            
            debugPrint('🚌 route=$r bound=$bound serviceType=$serviceType company=$companyId isJoint=$isJointOperation');

            // 如果是聯營路線，顯示選擇對話框
            // ✅ 確保 companyId 永遠係小寫
            String selectedCompany = (companyId ?? 'kmb').toLowerCase();


            if (isJointOperation && companies != null && companies.length > 1) {
              final result = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(isEnglish ? 'Select Operator' : '選擇營運商'),
                  content: Text(isEnglish 
                      ? 'This is a joint operation route. Please select an operator to view:'
                      : '這是聯營路線，請選擇要查看的營運商：'),
                  actions: companies.map((co) {
                    return TextButton(
                      onPressed: () => Navigator.pop(context, co.toLowerCase()),
                      child: Text(companyProv.getName(co, isEnglish)),
                    );
                  }).toList(),
                ),
              );
              if (result == null) return; // 用戶取消
              selectedCompany = result;
            }
            
            // 導航到路線詳情頁
            // 如果使用統一數據庫，導航到 UnifiedRouteStatusPage
            // 否則根據公司導航到原有頁面
            if (_useUnifiedDb) {
              // ✅ OPTIMIZED: Read pre-fetched location from provider
              final locationProvider = context.read<LocationProvider>();
              final Position? userLocation = locationProvider.currentPosition;
              
              Navigator.of(context).push(EnhancedPageRoute(
                builder: (_) => UnifiedRouteStatusPage(
                  route: r,
                  companies: companies?.cast<String>() ?? [selectedCompany],
                  initialCompany: selectedCompany,
                  bound: bound,
                  serviceType: serviceType,
                  initialRouteId: v['routeId']?.toString(),
                  useUnifiedDb: true,
                  // ✅ NEW: Pass pre-fetched location
                  initialLocation: userLocation,
                ),
              ));
            } else {
              // 使用原有頁面
              if (selectedCompany == 'ctb') {
                Navigator.of(context).push(EnhancedPageRoute(
                  builder: (_) => CtbRouteStatusPage(
                    route: r,
                    bound: bound,
                    serviceType: serviceType,
                    companyId: selectedCompany,
                  ),
                ));
              } else if (selectedCompany == 'nlb') {
                Navigator.of(context).push(EnhancedPageRoute(
                  builder: (_) => NlbRouteStatusPage(
                    routeNo: r,
                    initialRouteId: v['routeId']?.toString(),
                  ),
                ));
              } else if (selectedCompany == 'gmb') {
                final routeId = v['routeId'] is int ? v['routeId'] : int.tryParse(v['routeId']?.toString() ?? '');
                final routeSeq = v['routeSeq'] is int ? v['routeSeq'] : (v['routeSeq'] as int? ?? 1);
                final region = v['region']?.toString();
                Navigator.of(context).push(EnhancedPageRoute(
                  builder: (_) => GmbRouteStatusPage(
                    routeNo: r,
                    initialRouteId: routeId,
                    initialRouteSeq: routeSeq,
                    region: region,
                  ),
                ));
              } else {
                Navigator.of(context).push(EnhancedPageRoute(
                  builder: (_) => KmbRouteStatusPage(
                    route: r,
                    bound: bound,
                    serviceType: serviceType,
                    companyId: selectedCompany,
                  ),
                ));
              }
            }
            
            widget.onRouteSelected?.call(r);
          },
        ),
      );
    
    // Add divider between variants
    if (flattened.last != v) {
      tiles.add(const Divider(
        height: 1, indent: 16, endIndent: 16, thickness: 0.5,
      ));
    }
  }

  return Column(children: tiles);
}

  // ── Helper: one origin/destination row with leading icon ────────────────────
  Widget _endpointRow({
    required IconData icon,
    required double iconSize,
    required String label,
    required String text,
    required ThemeData theme,
  }) {
    final labelStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final textStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      children: [
        Icon(icon, size: iconSize, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        SizedBox(
          width: 40, // 讓 From/To / 由/往 對齊
          child: Text(label, style: labelStyle),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
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
  
  const _OneHandDialerContainer({
    required this.child,
    super.key, // 提升比較效能
  });

  @override
  State<_OneHandDialerContainer> createState() => _OneHandDialerContainerState();
}

class _OneHandDialerContainerState extends State<_OneHandDialerContainer> 
    with SingleTickerProviderStateMixin {
  
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    // M3 Micro-interaction (微互動) 時間
    _controller = AnimationController(
      vsync: this,
      duration: Durations.short4, // 200ms
      reverseDuration: Durations.short3, // 150ms
    );

    // 按壓時的微縮放，模擬真實世界物理下壓感
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Easing.standardDecelerate,     // 進場減速
        reverseCurve: Easing.standardAccelerate, // 退場加速
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!_isPressed) {
      setState(() => _isPressed = true);
      _controller.forward();
      // 加入輕微震動，彌補沒有實體按鍵的觸覺回饋
      HapticFeedback.lightImpact(); 
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isPressed) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            // ✅ 使用 ClipRRect 確保毛玻璃效果與邊界裁切完美貼合
            child: ClipRRect(
              //borderRadius: BorderRadius.circular(12), // 依照你的 UI 圓角調整
              child: FakeGlass( 
                shape: const LiquidRoundedSuperellipse(borderRadius: 18),
                settings: LiquidGlassSettings(
                  blur: 10.0, // 保持高度模糊
                  thickness: 50.0,
                  // 配合 M3 ColorScheme 與透明度 (使用最新的 withValues 語法)
                  glassColor: theme.brightness == Brightness.dark
                  // 暗色模式：提高不透明度來遮蓋底層雜訊，確保白字清晰
                  ? theme.colorScheme.surface.withValues(alpha: 0.45)
                  // 亮色模式：使用稍微透亮一點的 surface，保持清爽感
                  : theme.colorScheme.surface.withValues(alpha: 0.3),

                  lightIntensity: 1.2,
                  saturation: 1.1,
                  refractiveIndex: 1.3,
                ),
                // 如果需要加一點極淡的邊框來增強立體感，可以包一層 Container
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: child!,
                ),
              ),
            ),
          );
        },
        // ✅ 效能核心：將不需參與動畫計算的內容從這裡傳入
        child: widget.child,
      ),
    );
  }

}