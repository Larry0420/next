import 'package:flutter/material.dart';
import 'kmb.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show compute;
import 'main.dart' show LanguageProvider;
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

class KmbRouteStatusPage extends StatefulWidget {
  final String route;
  final String? bound;
  final String? serviceType;
  const KmbRouteStatusPage({Key? key, required this.route, this.bound, this.serviceType}) : super(key: key);

  @override
  State<KmbRouteStatusPage> createState() => _KmbRouteStatusPageState();
}

class _KmbRouteStatusPageState extends State<KmbRouteStatusPage> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  // route variant selectors and route-level ETA state
  List<String> _directions = [];
  List<String> _serviceTypes = [];
  String? _selectedDirection;
  String? _selectedServiceType;

  bool _routeEtaLoading = false;
  String? _routeEtaError;
  List<Map<String, dynamic>>? _routeEtaEntries;
  
  // O(1) ETA lookup cache - precomputed HashMap for instant seq->ETAs mapping
  Map<String, List<Map<String, dynamic>>>? _etaBySeqCache;

  // Route details for verification and display
  Map<String, dynamic>? _routeDetails;
  bool _routeDetailsLoading = false;
  String? _routeDetailsError;

  @override
  void initState() {
    super.initState();
    _fetch();
    _addToHistory();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _addToHistory() async {
    // Add this route to history automatically
    final r = widget.route.trim().toUpperCase();
    String label = r;
    
    // Wait a bit for route details to load
    await Future.delayed(Duration(milliseconds: 500));
    
    if (_routeDetails != null) {
      final routeData = _routeDetails!.containsKey('data') 
        ? (_routeDetails!['data'] as Map<String, dynamic>?)
        : _routeDetails!;
      
      if (routeData != null && mounted) {
        final lang = context.read<LanguageProvider>();
        final isEnglish = lang.isEnglish;
        
        final orig = isEnglish 
          ? (routeData['orig_en'] ?? routeData['orig_tc'] ?? '')
          : (routeData['orig_tc'] ?? routeData['orig_en'] ?? '');
        final dest = isEnglish
          ? (routeData['dest_en'] ?? routeData['dest_tc'] ?? '')
          : (routeData['dest_tc'] ?? routeData['dest_en'] ?? '');
        
        if (orig.isNotEmpty && dest.isNotEmpty) {
          label = '$r: $orig → $dest';
        }
      }
    }
    
    await Kmb.addToHistory(
      r,
      _selectedDirection ?? widget.bound ?? 'O',
      _selectedServiceType ?? widget.serviceType ?? '1',
      label,
    );
  }

  String _formatEta(BuildContext context, dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      // Respect device/user 24-hour preference when available
      final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
      if (use24) {
        return DateFormat.Hm().format(dt); // 24-hour HH:mm
      } else {
        // jm() will format as e.g. 5:08 PM for en_US, or follow locale conventions
        final locale = Localizations.localeOf(context).toString();
        return DateFormat.jm(locale).format(dt);
      }
    } catch (_) {
      return raw?.toString() ?? '—';
    }
  }

  /// Return a compact relative + absolute ETA string suitable for quick glance.
  /// Examples: "5 min (19:56)", "Due (19:56)", "Departed".
  String _formatEtaWithRelative(BuildContext context, dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final diff = dt.difference(now);
      String relative;
      if (diff.inSeconds.abs() < 30) {
        relative = 'Due';
      } else if (diff.isNegative) {
        final mins = diff.abs().inMinutes;
        if (mins < 1) {
          relative = 'Departed';
        } else if (mins < 60) {
          relative = '${mins} min ago';
        } else {
          final h = diff.abs().inHours;
          final m = diff.abs().inMinutes % 60;
          relative = '${h}h${m > 0 ? ' ${m}m' : ''} ago';
        }
      } else {
        final mins = diff.inMinutes;
        if (mins < 1) {
          relative = 'Due';
        } else if (mins < 60) {
          relative = '${mins} min';
        } else {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          relative = '${h}h${m > 0 ? ' ${m}m' : ''}';
        }
      }
      final abs = _formatEta(context, raw);
      // If relative is 'Departed' with no extra info, show just that.
      if (relative == 'Departed') return 'Departed ($abs)';
      return '$relative ($abs)';
    } catch (_) {
      return raw?.toString() ?? '—';
    }
  }

  /// Get color for ETA based on time remaining
  Color _getEtaColor(dynamic raw) {
    if (raw == null) return Colors.grey;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final diff = dt.difference(now);
      
      if (diff.isNegative) return Colors.grey; // Departed
      if (diff.inMinutes <= 2) return Colors.red; // Due soon
      if (diff.inMinutes <= 5) return Colors.orange; // Coming soon
      if (diff.inMinutes <= 10) return Colors.green; // On time
      return Colors.blue; // Later
    } catch (_) {
      return Colors.grey;
    }
  }


  bool _combinedLoading = false;
  String? _combinedError;
  Map<String, dynamic>? _combinedData;
  

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // Try to load prebuilt assets first (fast startup)
      final rnorm = widget.route.trim().toUpperCase();
      final prebuiltLoaded = await _attemptLoadPrebuilt(rnorm);
      if (prebuiltLoaded) {
        setState(() { loading = false; });
        return;
      }
  final useRouteApi = await Kmb.getUseRouteApiSetting();
      final r = widget.route.trim().toUpperCase();
      final base = RegExp(r'^(\\d+)').firstMatch(r)?.group(1) ?? r;

      if (useRouteApi) {
        // User prefers freshest per-route API
        final result = await Kmb.fetchRouteStatus(r);
        setState(() { data = result; });
        return;
      }

      // Default: use prebuilt map first, fall back to per-route API
      final map = await Kmb.buildRouteToStopsMap();
      if (map.containsKey(r) || map.containsKey(base)) {
        final entries = map[r] ?? map[base]!;
        setState(() {
          data = {
            'type': 'RouteStopList',
            'version': 'prebuilt',
            'generatedtimestamp': DateTime.now().toIso8601String(),
            'data': entries,
          };
        });
        _loadVariantsFromCache(r, widget.bound, widget.serviceType);
      } else {
        final result = await Kmb.fetchRouteStatus(r);
        setState(() { data = result; });
        _loadVariantsFromCache(r, widget.bound, widget.serviceType);
      }
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  /// Try to read prebuilt JSON assets and populate `data` if the route is present.
  /// Returns true when prebuilt data was found and applied.
  Future<bool> _attemptLoadPrebuilt(String route) async {
    try {
      String? raw;
      // Try app documents prebuilt first (written by Regenerate prebuilt data)
      try {
        final doc = await getApplicationDocumentsDirectory();
        final f = File('${doc.path}/prebuilt/kmb_route_stops.json');
        if (f.existsSync()) raw = await f.readAsString();
      } catch (_) {}

      // Fallback to bundled asset
      if (raw == null) {
        try {
          raw = await rootBundle.loadString('assets/prebuilt/kmb_route_stops.json');
        } catch (_) {
          raw = null;
        }
      }
      if (raw == null || raw.isEmpty) return false;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      // Keys are route strings; try exact or base match
      final r = route.toUpperCase();
      if (decoded.containsKey(r)) {
        final entries = List<Map<String, dynamic>>.from((decoded[r] as List).map((e) => Map<String, dynamic>.from(e)));
        // Immediately show the raw entries to avoid blocking UI while we enrich
        setState(() {
          data = {
            'type': 'RouteStopList',
            'version': 'prebuilt-asset',
            'generatedtimestamp': DateTime.now().toIso8601String(),
            'data': entries,
          };
          _combinedData = null;
        });

        // Enrich stop entries with metadata off the main isolate to avoid jank
        try {
          final stopMap = await Kmb.buildStopMap();
          final enriched = await compute(_enrichEntriesForStopMap, {'entries': entries, 'stopMap': stopMap});
          if (mounted) {
            setState(() {
              data = {
                'type': 'RouteStopList',
                'version': 'prebuilt-asset',
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': enriched,
              };
              _combinedData = {
                'type': 'CombinedRouteStatus',
                'route': r,
                'serviceType': null,
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': {
                  'stops': enriched,
                  'routeEta': [],
                }
              };
            });
          }
        } catch (_) {
          // ignore enrichment failures; raw entries already displayed
        }
        // populate variants from cache by ensuring route->stops map is built
        try { await Kmb.buildRouteToStopsMap(); } catch (_) {}
        _loadVariantsFromCache(r, widget.bound, widget.serviceType);
        return true;
      }

      // Try base numeric key
      final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1);
      if (base != null && decoded.containsKey(base)) {
        final entries = List<Map<String, dynamic>>.from((decoded[base] as List).map((e) => Map<String, dynamic>.from(e)));
        setState(() {
          data = {
            'type': 'RouteStopList',
            'version': 'prebuilt-asset',
            'generatedtimestamp': DateTime.now().toIso8601String(),
            'data': entries,
          };
          _combinedData = null;
        });
        try {
          final stopMap = await Kmb.buildStopMap();
          final enriched = await compute(_enrichEntriesForStopMap, {'entries': entries, 'stopMap': stopMap});
          if (mounted) {
            setState(() {
              data = {
                'type': 'RouteStopList',
                'version': 'prebuilt-asset',
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': enriched,
              };
              _combinedData = {
                'type': 'CombinedRouteStatus',
                'route': r,
                'serviceType': null,
                'generatedtimestamp': DateTime.now().toIso8601String(),
                'data': {
                  'stops': enriched,
                  'routeEta': [],
                }
              };
            });
          }
        } catch (_) {}
        try { await Kmb.buildRouteToStopsMap(); } catch (_) {}
        _loadVariantsFromCache(r, widget.bound, widget.serviceType);
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('${lang.route} ${widget.route}'),
        actions: [
          IconButton(
            icon: Icon(Icons.push_pin_outlined),
            tooltip: lang.pinRoute,
            onPressed: _pinRoute,
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _fetch,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : (error != null
                ? Center(child: Text('Error: $error', style: const TextStyle(color: Colors.red)))
                : (data == null
                    ? const Center(child: Text('No data'))
                    : Column(
                        children: [
                          if (_combinedLoading) const Padding(padding: EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),
                          if (_combinedError != null) Padding(padding: const EdgeInsets.all(8.0), child: Text('Combined error: $_combinedError', style: const TextStyle(color: Colors.red))),
                          Expanded(child: _buildStructuredView()),
                        ],
                      ))),
      ),
    );
  }

  void _pinRoute() async {
    final lang = context.read<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    // Get route details for the pin
    String routeLabel = widget.route;
    if (_routeDetails != null) {
      final routeData = _routeDetails!.containsKey('data') 
        ? (_routeDetails!['data'] as Map<String, dynamic>?)
        : _routeDetails!;
      
      if (routeData != null) {
        final orig = isEnglish 
          ? (routeData['orig_en'] ?? routeData['orig_tc'] ?? '')
          : (routeData['orig_tc'] ?? routeData['orig_en'] ?? '');
        final dest = isEnglish
          ? (routeData['dest_en'] ?? routeData['dest_tc'] ?? '')
          : (routeData['dest_tc'] ?? routeData['dest_en'] ?? '');
        if (orig.isNotEmpty && dest.isNotEmpty) {
          routeLabel = '${widget.route}: $orig → $dest';
        }
      }
    }
    
    // Save to preferences (you'll need to implement this in kmb.dart)
    await Kmb.pinRoute(
      widget.route, 
      _selectedDirection ?? widget.bound ?? 'O',
      _selectedServiceType ?? widget.serviceType ?? '1',
      routeLabel,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lang.routePinned} ${widget.route}'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildStructuredView() {
    final payload = data!['data'];

    List<Widget> sections = [];

    // Hide technical response info - users don't need to see this
    // sections.add(Card(
    //   child: ListTile(
    //     title: Text('Response'),
    //     subtitle: Text('type: $type\nversion: $version\ngenerated: $generated'),
    //   ),
    // ));

    // If payload is a list, inspect the first item to determine its shape
    if (payload is List && payload.isNotEmpty) {
      final first = payload.first as Map<String, dynamic>;

      // Hide route info/list - not user-friendly
      // if (first.containsKey('route') && first.containsKey('co')) {
      //   sections.add(_buildRouteInfoList(payload.cast<Map<String, dynamic>>()));
      // }

      // Route-stop list (contains seq and stop)
      if (first.containsKey('seq') && first.containsKey('stop')) {
        // Hide technical stops list - keep only user-friendly version
        // sections.add(_buildStopsList(payload.cast<Map<String, dynamic>>()));
        sections.add(_buildOptimizedStationList());
      }

      // Hide ETA entries list - shown in optimized station list instead
      // if (first.containsKey('etaseq') || first.containsKey('eta')) {
      //   sections.add(_buildEtaList(payload.cast<Map<String, dynamic>>()));
      // }

      // If none of the above matched, fall back to raw list view
      if (!first.containsKey('route') && !first.containsKey('seq') && !first.containsKey('eta')) {
        // Hide raw JSON for unknown formats
        // sections.add(_buildRawJsonCard());
      }

      // Hide combined data card - information shown in optimized list instead
      // if (_combinedData != null) {
      //   sections.insert(0, _buildCombinedCard(_combinedData!));
      // }
    } else if (payload is Map<String, dynamic>) {
      // Hide key-value card - not user-friendly
      // sections.add(_buildKeyValueCard('Data', payload));
    } else {
      // Hide raw JSON
      // sections.add(_buildRawJsonCard());
    }

    // If we have discovered service types, show selectors and route details
    if (_serviceTypes.isNotEmpty) {
      sections.insert(0, _buildSelectorsCard());
      // Show destination card separately after selectors
      if (_routeDetails != null) {
        sections.insert(1, _buildRouteDetailsCard());
      }
    }

    // Hide raw JSON at the end - users don't need debug info
    // sections.add(_buildRawJsonCard());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      ),
    );
  }

  Widget _buildSelectorsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_directions.isNotEmpty) ...[
              Text('Direction'),
              DropdownButton<String>(
                value: _selectedDirection,
                items: _directions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedDirection = v;
                    // Fetch route details and stops if both direction and service type are selected
                    if (v != null && _selectedServiceType != null) {
                      _fetchRouteDetails(widget.route.trim().toUpperCase(), v, _selectedServiceType!);
                    }
                  });
                },
              ),
            ],
            if (_serviceTypes.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('Service Type'),
              DropdownButton<String>(
                value: _selectedServiceType,
                items: _serviceTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedServiceType = v;
                    if (v != null) {
                      _fetchRouteEta(widget.route.trim().toUpperCase(), v);
                      // Also fetch route details and stops if direction is selected
                      if (_selectedDirection != null) {
                        _fetchRouteDetails(widget.route.trim().toUpperCase(), _selectedDirection!, v);
                      }
                    }
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRouteDetailsCard() {
    // Loading state
    if (_routeDetailsLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Error state
    if (_routeDetailsError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Text('Route Details Error: $_routeDetailsError', style: TextStyle(color: Colors.red)),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  if (_selectedDirection != null && _selectedServiceType != null) {
                    _fetchRouteDetails(widget.route.trim().toUpperCase(), _selectedDirection!, _selectedServiceType!);
                  }
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No data state
    if (_routeDetails == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text('Select direction and service type to view route details'),
        ),
      );
    }

    // Language preference
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    // Handle both response formats: direct data or wrapped in 'data' field
    final routeData = _routeDetails!.containsKey('data') 
      ? (_routeDetails!['data'] as Map<String, dynamic>?)
      : _routeDetails!;
    
    if (routeData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text('Invalid route details data'),
        ),
      );
    }

    // Extract fields with language preference
    final dest = isEnglish
      ? (routeData['dest_en'] ?? routeData['dest_tc'] ?? '')
      : (routeData['dest_tc'] ?? routeData['dest_en'] ?? '');
    
    final bound = routeData['bound'] as String?;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Direction icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (bound == 'O' ? Colors.green : Colors.orange).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      bound == 'O' ? Icons.arrow_circle_right : Icons.arrow_circle_left,
                      color: bound == 'O' ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  
                  // Destination label
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${lang.isEnglish ? 'Destination' : '目的地'}:',
                          style: TextStyle(
                            fontSize: 11, 
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          dest,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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

  Widget _buildRouteEtaCard() {
    if (_routeEtaLoading) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Center(child: CircularProgressIndicator())));
    if (_routeEtaError != null) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('Error: $_routeEtaError', style: TextStyle(color: Colors.red))));
    if (_routeEtaEntries == null || _routeEtaEntries!.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('No route ETA data')));

    // Group entries by stop sequence
    final Map<String, List<Map<String, dynamic>>> byStop = {};
    for (final e in _routeEtaEntries!) {
      final stop = e['stop']?.toString() ?? 'unknown';
      byStop.putIfAbsent(stop, () => []).add(e);
    }

    String _fmtEta(dynamic raw) {
      return _formatEta(context, raw);
    }

  final widgets = byStop.entries.map((entry) {
      final stopId = entry.key;
      final rows = entry.value;
      rows.sort((a, b) => (int.tryParse(a['etaseq']?.toString() ?? '') ?? 0).compareTo(int.tryParse(b['etaseq']?.toString() ?? '') ?? 0));
      return ExpansionTile(
        title: FutureBuilder<Map<String, dynamic>?>(
          future: Kmb.getStopById(stopId),
          builder: (context, snap) {
            final name = snap.data != null ? (snap.data!['nameen'] ?? snap.data!['nametc'] ?? stopId) : stopId;
            return Text('$stopId · $name');
          },
        ),
        children: rows.map((r) {
          final etaseq = r['etaseq']?.toString() ?? r['eta_seq']?.toString() ?? '';
          final etaRaw = r['eta'] ?? r['eta_time'] ?? null;
          final eta = _fmtEta(etaRaw);
          final dest = r['desten'] ?? r['desttc'] ?? r['dest'] ?? '';
          final remark = r['rmken'] ?? r['rmktc'] ?? r['rmk'] ?? '';
          return ListTile(
            title: Text('ETA #$etaseq · $dest'),
            subtitle: Text('eta: $eta\n$remark'),
          );
        }).toList(),
      );
    }).toList();

    return Card(child: Column(children: widgets));
  }

  Future<void> _fetchCombined() async {
    setState(() {
      _combinedLoading = true;
      _combinedError = null;
      _combinedData = null;
    });
    try {
      final combined = await Kmb.fetchCombinedRouteStatus(widget.route);
      setState(() { _combinedData = combined; });
    } catch (e) {
      setState(() { _combinedError = e.toString(); });
    } finally {
      setState(() { _combinedLoading = false; });
    }
  }

  Widget _buildCombinedCard(Map<String, dynamic> combined) {
    final meta = combined['data'] ?? {};
  final List stops = meta['stops'] ?? [];

    if (stops.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('No combined stops')));

    final combinedRouteEta = meta['routeEta'] ?? [];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(title: Text('Combined status for ${combined['route']} · svc: ${combined['serviceType'] ?? 'n/a'} · ETAs: ${combinedRouteEta.length}')),
      ...stops.map((s) {
      final stopId = s['stop'] ?? '';
      final stopInfo = s['stopInfo'] as Map<String, dynamic>?;
      final List<Map<String, dynamic>> etas = (s['etas'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ?? <Map<String, dynamic>>[];
            final stopName = stopInfo != null ? (stopInfo['nameen'] ?? stopInfo['nametc'] ?? stopId) : stopId;
            return ListTile(
              title: Text('$stopId · $stopName'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (etas.isEmpty) Text('No ETAs'),
                  for (final e in etas)
                    Text('${e['etaseq'] ?? ''} · ${_formatEtaWithRelative(context, e['eta'] ?? e['eta_time'] ?? null)} · ${e['desten'] ?? e['desttc'] ?? ''}'),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  void _loadVariantsFromCache(String r, [String? initialDirection, String? initialServiceType]) async {
    try {
      await Kmb.buildRouteToStopsMap();
      final variants = Kmb.discoverRouteVariants(r);
      setState(() {
        _directions = variants['directions'] ?? [];
        _serviceTypes = variants['serviceTypes'] ?? [];
        _selectedDirection = initialDirection != null && _directions.contains(initialDirection) ? initialDirection : (_directions.isNotEmpty ? _directions.first : null);
        _selectedServiceType = initialServiceType != null && _serviceTypes.contains(initialServiceType) ? initialServiceType : (_serviceTypes.isNotEmpty ? _serviceTypes.first : null);
      });
      if (_selectedServiceType != null) {
        _fetchRouteEta(r, _selectedServiceType!);
      }
      // If both direction and serviceType are selected, fetch variant-specific stops
      if (_selectedDirection != null && _selectedServiceType != null) {
        _fetchRouteDetails(r, _selectedDirection!, _selectedServiceType!);
      }
    } catch (_) {}
  }

  Future<void> _fetchRouteEta(String route, String serviceType, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _routeEtaLoading = true;
        _routeEtaError = null;
        _routeEtaEntries = null;
        _etaBySeqCache = null; // Clear cache when fetching new data
      });
    }
    try {
      final entries = await Kmb.fetchRouteEta(route, serviceType);
      entries.sort((a, b) {
        final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
        final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });
      
      // Build O(1) lookup cache: HashMap seq -> List<ETA>
      // Pre-filter by selected direction to avoid redundant filtering in builders
      final selectedBoundChar = _selectedDirection?.trim().toUpperCase()[0];
      final Map<String, List<Map<String, dynamic>>> etaBySeq = {};
      
      for (final e in entries) {
        // Filter by direction if selected
        if (selectedBoundChar != null) {
          final etaBound = e['dir']?.toString().trim().toUpperCase() ?? '';
          if (etaBound.isEmpty || etaBound[0] != selectedBoundChar) continue;
        }
        
        final seqNum = e['seq']?.toString() ?? '';
        if (seqNum.isEmpty) continue;
        
        etaBySeq.putIfAbsent(seqNum, () => []).add(Map<String, dynamic>.from(e));
      }
      
      // Sort each ETA list by eta_seq once during cache build
      // Use toList() to avoid concurrent modification during iteration
      for (final k in etaBySeq.keys.toList()) {
        etaBySeq[k]!.sort((a, b) {
          final ai = int.tryParse(a['eta_seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['eta_seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });
      }
      
      setState(() { 
        _routeEtaEntries = entries;
        _etaBySeqCache = etaBySeq; // Store precomputed HashMap for O(1) lookups
      });
    } catch (e) {
      setState(() { _routeEtaError = e.toString(); });
    } finally {
      setState(() { _routeEtaLoading = false; });
    }
  }

  Future<void> _fetchRouteDetails(String route, String direction, String serviceType) async {
    setState(() {
      _routeDetailsLoading = true;
      _routeDetailsError = null;
      _routeDetails = null;
    });
    try {
      final details = await Kmb.fetchRouteWithParams(route, direction, serviceType);
      setState(() { _routeDetails = details; });
      
      // Also fetch route-stops for this specific variant
      _fetchRouteStopsForVariant(route, direction, serviceType);
    } catch (e) {
      setState(() { _routeDetailsError = e.toString(); });
    } finally {
      setState(() { _routeDetailsLoading = false; });
    }
  }

  // State for variant-specific route stops
  List<Map<String, dynamic>>? _variantStops;
  bool _variantStopsLoading = false;
  String? _variantStopsError;

  /// Fetch route-stops for a specific route/direction/service_type combination using the Route-Stop API
  Future<void> _fetchRouteStopsForVariant(String route, String direction, String serviceType) async {
    setState(() {
      _variantStopsLoading = true;
      _variantStopsError = null;
      _variantStops = null;
    });
    
    try {
      final stops = await Kmb.fetchRouteStops(route, direction, serviceType);
      
      // Enrich with stop metadata
      final stopMap = await Kmb.buildStopMap();
      final enriched = stops.map((stopEntry) {
        final stopId = stopEntry['stop'] as String?;
        final stopInfo = stopId != null ? stopMap[stopId] : null;
        
        return {
          ...stopEntry,
          if (stopInfo != null) ...{
            'name_en': stopInfo['name_en'],
            'name_tc': stopInfo['name_tc'],
            'name_sc': stopInfo['name_sc'],
            'lat': stopInfo['lat'],
            'long': stopInfo['long'],
          }
        };
      }).toList();
      
      setState(() { _variantStops = enriched; });
    } catch (e) {
      setState(() { _variantStopsError = e.toString(); });
    } finally {
      setState(() { _variantStopsLoading = false; });
    }
  }

  Widget _buildRouteInfoList(List<Map<String, dynamic>> list) {
    return Card(
      child: ExpansionTile(
        title: Text('Route info (${list.length})'),
        children: list.map((item) {
          final route = item['route'] ?? '';
          final co = item['co'] ?? '';
          final bound = item['bound'] ?? '';
          final service = item['servicetype'] ?? '';
          final origin = item['origen'] ?? item['origtc'] ?? '';
          final dest = item['desten'] ?? item['desttc'] ?? '';
          return ListTile(
            title: Text('$route ($co)'),
            subtitle: Text('bound: $bound · service: $service\n$origin → $dest'),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStopsList(List<Map<String, dynamic>> list) {
    // Sort by seq
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });

    return Card(
      child: ExpansionTile(
        title: Text('Stops (${sorted.length})'),
        children: sorted.map((stop) {
          final seq = stop['seq']?.toString() ?? '';
          final stopId = stop['stop'] ?? '';
          final nameen = stop['nameen'] ?? stop['nametc'] ?? '';
          final lat = stop['lat'] ?? '';
          final lng = stop['long'] ?? stop['lng'] ?? '';
          return ExpansionTile(
            title: Text('$seq · $stopId'),
            subtitle: Text('$nameen\nlat: $lat, long: $lng'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: StopEtaTile(stopId: stopId),
              )
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEtaList(List<Map<String, dynamic>> list) {
    // Group by stop id
    final Map<String, List<Map<String, dynamic>>> byStop = {};
    for (final item in list) {
      final stop = item['stop']?.toString() ?? 'unknown';
      byStop.putIfAbsent(stop, () => []).add(item);
    }

    final tiles = byStop.entries.map((e) {
      final stopId = e.key;
      final entries = e.value;
      entries.sort((a, b) {
        final ai = int.tryParse(a['etaseq']?.toString() ?? '') ?? 0;
        final bi = int.tryParse(b['etaseq']?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });

      return ExpansionTile(
        title: Text('Stop $stopId (${entries.length})'),
        children: entries.map((entry) {
          final etaseq = entry['etaseq']?.toString() ?? '';
          final eta = _formatEtaWithRelative(context, entry['eta'] ?? entry['eta_time'] ?? null);
          final dest = entry['desten'] ?? entry['desttc'] ?? '';
          final remark = entry['rmken'] ?? entry['rmktc'] ?? '';
          return ListTile(
            title: Text('ETA #$etaseq · $dest'),
            subtitle: Text('eta: $eta\n$remark'),
          );
        }).toList(),
      );
    }).toList();

    return Card(
      child: Column(children: tiles),
    );
  }

  Widget _buildKeyValueCard(String title, Map<String, dynamic> map) {
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: map.entries.map((e) {
          final label = kmb.lookup(e.key) ?? e.key;
          return ListTile(
            title: Text(label),
            subtitle: Text(e.value.toString()),
          );
        }).toList(),
      ),
    );
  }

  /// Build station list for a specific route variant using Route-Stop API data
  Widget _buildVariantStationList(List<Map<String, dynamic>> stops) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    // Sort by sequence
    final sortedStops = List<Map<String, dynamic>>.from(stops);
    sortedStops.sort((a, b) {
      final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
      final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
      return ai.compareTo(bi);
    });
    
    // Use cached ETA HashMap for O(1) lookup - no API call needed!
    final etaByStop = _etaBySeqCache ?? <String, List<Map<String, dynamic>>>{};
    
    // Loading state
    if (_routeEtaLoading) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Build optimized stop cards using cached data
    return Column(
      children: [
        // Independent Route Destination Widget
        RouteDestinationWidget(
          route: widget.route,
          direction: _selectedDirection,
          serviceType: _selectedServiceType,
        ),
        SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            shrinkWrap: false,
            itemCount: sortedStops.length,
            itemBuilder: (context, index) {
              final s = sortedStops[index];
              final seq = s['seq']?.toString() ?? '';
              final stopId = s['stop']?.toString() ?? '';
              
              // Get stop names from enriched data
              final nameEn = (s['name_en'] ?? s['nameen'] ?? '')?.toString() ?? '';
              final nameTc = (s['name_tc'] ?? s['nametc'] ?? '')?.toString() ?? '';
              final displayName = isEnglish
                  ? (nameEn.isNotEmpty ? nameEn : (nameTc.isNotEmpty ? nameTc : stopId))
                  : (nameTc.isNotEmpty ? nameTc : (nameEn.isNotEmpty ? nameEn : stopId));
              
              // Get coordinates
              final lat = (s['lat'] ?? s['latitude'])?.toString();
              final lng = (s['long'] ?? s['lng'] ?? s['longitude'])?.toString();
              
              // O(1) HashMap lookup - instant access!
              final List<Map<String, dynamic>> etas = etaByStop[seq] ?? [];

              return _buildCompactStopCard(
                context: context,
                seq: seq,
                stopId: stopId,
                displayName: displayName,
                nameEn: nameEn,
                nameTc: nameTc,
                etas: etas,
                isEnglish: isEnglish,
                latitude: lat,
                longitude: lng,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOptimizedStationList() {
    // If we have variant-specific stops (from Route-Stop API), use those instead of cached data
    if (_variantStops != null && _selectedDirection != null && _selectedServiceType != null) {
      return _buildVariantStationList(_variantStops!);
    }
    
    if (_variantStopsLoading) {
      return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Center(child: CircularProgressIndicator())));
    }
    
    if (_variantStopsError != null) {
      return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('Error loading route stops: $_variantStopsError', style: TextStyle(color: Colors.red))));
    }
    
    // Fallback to cached route-stop data (from Route-Stop List API)
    // Use the cached/compute helpers in Kmb to get both route->stops and stop metadata maps.
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([Kmb.buildRouteToStopsMap(), Kmb.buildStopMap()]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Center(child: CircularProgressIndicator())));
        if (snap.hasError) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('Error loading maps: ${snap.error}', style: TextStyle(color: Colors.red))));

        final routeMap = (snap.data?[0] as Map<String, List<Map<String, dynamic>>>?) ?? {};
        final stopMap = (snap.data?[1] as Map<String, Map<String, dynamic>>?) ?? {};

        final r = widget.route.trim().toUpperCase();
        final base = RegExp(r'^(\\d+)').firstMatch(r)?.group(1) ?? r;
        final entries = routeMap[r] ?? routeMap[base] ?? [];
  if (entries.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('No stop data for route')));

        // Language preference
        final lang = context.watch<LanguageProvider>();
        final isEnglish = lang.isEnglish;

        // Helper: normalize direction/bound values to a single char 'I' or 'O'
        String? _normChar(dynamic v) {
          if (v == null) return null;
          final s = v.toString().trim().toUpperCase();
          if (s.isEmpty) return null;
          // Accept values starting with I or O (covers 'I','O','IN','OUT','INBOUND','OUTBOUND')
          final c = s[0];
          if (c == 'I' || c == 'O') return c;
          return null;
        }

        // Determine selected bound char from state (if any). If null, keep both directions.
        final selectedBoundChar = _normChar(_selectedDirection);
        final selectedService = _selectedServiceType;

        // Filter by bound O/I AND service_type (keep all if not selected), then sort by seq
        final stops = List<Map<String, dynamic>>.from(
            entries.where((e) {
              if (!e.containsKey('seq')) return false;
              
              // Filter by bound/direction if selected
              if (selectedBoundChar != null && _normChar(e['bound']) != selectedBoundChar) return false;
              
              // Filter by service_type if selected
              if (selectedService != null) {
                final entryServiceType = e['service_type']?.toString() ?? e['servicetype']?.toString() ?? '';
                if (entryServiceType != selectedService) return false;
              }
              
              return true;
            }));
        stops.sort((a, b) {
          final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        // Use cached ETA HashMap for O(1) lookup instead of FutureBuilder
        // Cache is already filtered by direction and sorted in _fetchRouteEta
        final etaByStop = _etaBySeqCache ?? <String, List<Map<String, dynamic>>>{};
        
        // Loading state
        if (_routeEtaLoading) {
          return Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        // Build optimized stop cards using cached data - no redundant API calls!
        return Column(
          children: [
            // Independent Route Destination Widget
            RouteDestinationWidget(
              route: r,
              direction: selectedBoundChar,
              serviceType: selectedService,
            ),
            SizedBox(height: 8),
            // Use shrinkWrap instead of Expanded since we're inside a SingleChildScrollView
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: stops.length,
              itemBuilder: (context, index) {
                  final s = stops[index];
                  final seq = s['seq']?.toString() ?? '';
                  final stopId = s['stop']?.toString() ?? '';

                  // Get stop metadata
                  final meta = stopMap[stopId];
                  final nameEn = meta != null ? (meta['name_en'] ?? meta['nameen'] ?? '')?.toString() ?? '' : '';
                  final nameTc = meta != null ? (meta['name_tc'] ?? meta['nametc'] ?? '')?.toString() ?? '' : '';
                  final displayName = isEnglish
                      ? (nameEn.isNotEmpty ? nameEn : (nameTc.isNotEmpty ? nameTc : stopId))
                      : (nameTc.isNotEmpty ? nameTc : (nameEn.isNotEmpty ? nameEn : stopId));

                  // Get coordinates from metadata
                  final lat = meta != null ? (meta['lat'] ?? meta['latitude'])?.toString() : null;
                  final lng = meta != null ? (meta['long'] ?? meta['lng'] ?? meta['longitude'])?.toString() : null;

                  // O(1) HashMap lookup - instant access to ETAs!
                  final List<Map<String, dynamic>> etas = etaByStop[seq] ?? [];

                  return _buildCompactStopCard(
                    context: context,
                    seq: seq,
                    stopId: stopId,
                    displayName: displayName,
                    etas: etas,
                    isEnglish: isEnglish,
                    latitude: lat,
                    longitude: lng,
                  );
                },
            ),
          ],
        );
      },
    );
  }

  Widget _buildRawJsonCard() {
    return Card(
      child: ExpansionTile(
        title: Text('Raw JSON'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SelectableText(const JsonEncoder.withIndent('  ').convert(data)),
          )
        ],
      ),
    );
  }

  /// Build compact route header showing origin → destination
  Widget _buildCompactRouteHeader() {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;
    
    final routeData = _routeDetails!.containsKey('data') 
      ? (_routeDetails!['data'] as Map<String, dynamic>?)
      : _routeDetails!;
    
    if (routeData == null) return SizedBox.shrink();

    final orig = isEnglish 
      ? (routeData['orig_en'] ?? routeData['orig_tc'] ?? '')
      : (routeData['orig_tc'] ?? routeData['orig_en'] ?? '');
    final dest = isEnglish
      ? (routeData['dest_en'] ?? routeData['dest_tc'] ?? '')
      : (routeData['dest_tc'] ?? routeData['dest_en'] ?? '');
    
    final bound = routeData['bound'] as String?;
    final serviceType = routeData['service_type'] as String?;
    
    // Direction icon
    IconData dirIcon = Icons.arrow_forward;
    Color dirColor = Colors.blue;
    if (bound == 'O') {
      dirIcon = Icons.arrow_circle_right;
      dirColor = Colors.green;
    } else if (bound == 'I') {
      dirIcon = Icons.arrow_circle_left;
      dirColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 3,
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(dirIcon, color: dirColor, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '$orig → $dest',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (serviceType != null && serviceType != '1')
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${lang.type} $serviceType',
                  style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build compact stop card without destination (shown in header)
  Widget _buildCompactStopCard({
    required BuildContext context,
    required String seq,
    required String stopId,
    required String displayName,
    String? nameEn,
    String? nameTc,
    required List<Map<String, dynamic>> etas,
    required bool isEnglish,
    String? latitude,
    String? longitude,
  }) {
    // Get destination from route details
    String? destEn;
    String? destTc;
    
    if (_routeDetails != null) {
      final routeData = _routeDetails!.containsKey('data') 
        ? (_routeDetails!['data'] as Map<String, dynamic>?)
        : _routeDetails!;
      
      if (routeData != null) {
        destEn = routeData['dest_en'];
        destTc = routeData['dest_tc'];
      }
    }
    
    return ExpandableStopCard(
      key: ValueKey('${widget.route}_$seq'), // Unique key to preserve expansion state
      seq: seq,
      stopId: stopId,
      displayName: displayName,
      nameEn: nameEn,
      nameTc: nameTc,
      etas: etas,
      isEnglish: isEnglish,
      route: widget.route,
      selectedServiceType: _selectedServiceType,
      latitude: latitude,
      longitude: longitude,
      destEn: destEn,
      destTc: destTc,
      direction: _selectedDirection,
    );
  }

// Compute helper to enrich entries with stop metadata off the main isolate.
// Arg must be a Map with keys 'entries' (List) and 'stopMap' (Map).
List<Map<String, dynamic>> _enrichEntriesForStopMap(Map<String, dynamic> arg) {
  final rawEntries = arg['entries'] as List<dynamic>? ?? [];
  final rawStopMap = arg['stopMap'] as Map<dynamic, dynamic>? ?? {};
  final stopMap = <String, Map<String, dynamic>>{};
  
  // Use for-loop instead of forEach to avoid concurrent modification
  for (final entry in rawStopMap.entries) {
    try {
      stopMap[entry.key.toString()] = Map<String, dynamic>.from(entry.value as Map);
    } catch (_) {}
  }

  final out = <Map<String, dynamic>>[];
  for (final re in rawEntries) {
    try {
      final e = Map<String, dynamic>.from(re as Map);
      final sid = e['stop']?.toString() ?? '';
      e['stopInfo'] = stopMap[sid];
      out.add(e);
    } catch (_) {}
  }
  return out;
}
}

// Expandable Stop Card with Auto-Refresh
class ExpandableStopCard extends StatefulWidget {
  final String seq;
  final String displayName;
  final String? nameEn;
  final String? nameTc;
  final List<Map<String, dynamic>> etas;
  final bool isEnglish;
  final String route;
  final String? selectedServiceType;
  final String? stopId;
  final String? latitude;
  final String? longitude;
  final String? destEn;
  final String? destTc;
  final String? direction;

  const ExpandableStopCard({
    Key? key,
    required this.seq,
    required this.displayName,
    this.nameEn,
    this.nameTc,
    required this.etas,
    required this.isEnglish,
    required this.route,
    this.selectedServiceType,
    this.stopId,
    this.latitude,
    this.longitude,
    this.destEn,
    this.destTc,
    this.direction,
  }) : super(key: key);

  @override
  State<ExpandableStopCard> createState() => _ExpandableStopCardState();
}

class _ExpandableStopCardState extends State<ExpandableStopCard> with AutomaticKeepAliveClientMixin {
  bool _isExpanded = false;
  Timer? _etaRefreshTimer;
  List<Map<String, dynamic>> _currentEtas = [];

  @override
  bool get wantKeepAlive => true; // Keep state alive during parent rebuilds

  @override
  void initState() {
    super.initState();
    _currentEtas = List.from(widget.etas);
    _startEtaRefresh();
  }

  @override
  void dispose() {
    _etaRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ExpandableStopCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update ETAs when parent provides new data
    if (oldWidget.etas != widget.etas) {
      setState(() {
        _currentEtas = List.from(widget.etas);
      });
    }
  }

  void _startEtaRefresh() {
    // Each stop card refreshes its own ETAs every 30 seconds independently
    _etaRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      if (!mounted) return;
      
      try {
        // Fetch fresh ETA data for this specific stop
        final route = widget.route.trim().toUpperCase();
        final serviceType = widget.selectedServiceType ?? '1';
        
        final entries = await Kmb.fetchRouteEta(route, serviceType);
        
        // Filter for this specific stop sequence
        final freshEtas = entries
            .where((e) => e['seq']?.toString() == widget.seq)
            .toList();
        
        // Sort by eta_seq
        freshEtas.sort((a, b) {
          final ai = int.tryParse(a['eta_seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['eta_seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });
        
        if (mounted) {
          setState(() {
            _currentEtas = freshEtas;
          });
        }
      } catch (e) {
        // Silently fail - keep showing old data
        print('Stop ${widget.seq} ETA refresh failed: $e');
      }
    });
  }

  Future<void> _pinStop(BuildContext context) async {
    try {
      await Kmb.pinStop(
        route: widget.route,
        stopId: widget.stopId ?? '',
        seq: widget.seq,
        stopName: widget.displayName,
        stopNameEn: widget.nameEn,
        stopNameTc: widget.nameTc,
        latitude: widget.latitude,
        longitude: widget.longitude,
        direction: widget.direction,
        serviceType: widget.selectedServiceType,
        destEn: widget.destEn,
        destTc: widget.destTc,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEnglish 
                ? 'Stop pinned: ${widget.displayName}' 
                : '已釘選站點: ${widget.displayName}'
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEnglish 
                ? 'Failed to pin stop: $e' 
                : '釘選失敗: $e'
            ),
            duration: Duration(seconds: 2),
          ),
        );
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: _isExpanded ? 2 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // Main row - always visible
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Platform/sequence number on the left
                  Column(
                    children: [
                      Icon(Icons.square, size: 18, color: Theme.of(context).primaryColor),
                      SizedBox(height: 2),
                      Text(
                        widget.seq,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 12),
                  
                  // ETAs and stop name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ETA times in a row
                        if (_currentEtas.isEmpty)
                          Text(
                            widget.isEnglish ? 'No upcoming buses' : '沒有即將到站的巴士',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          )
                        else
                          Row(
                            children: [
                              ..._currentEtas.take(3).expand((e) sync* {
                                final etaRaw = e['eta'] ?? e['eta_time'];
                                final rmkEn = e['rmk_en']?.toString() ?? e['rmken']?.toString() ?? '';
                                final rmkTc = e['rmk_tc']?.toString() ?? e['rmktc']?.toString() ?? '';
                                final rmk = widget.isEnglish
                                    ? (rmkEn.isNotEmpty ? rmkEn : rmkTc)
                                    : (rmkTc.isNotEmpty ? rmkTc : rmkEn);
                                
                                // Format ETA as "X min" or time
                                String etaText = '—';
                                bool isDeparted = false;
                                bool isNearlyArrived = false;
                                if (etaRaw != null) {
                                  try {
                                    final dt = DateTime.parse(etaRaw.toString()).toLocal();
                                    final now = DateTime.now();
                                    final diff = dt.difference(now);
                                    
                                    if (diff.inMinutes <= 0 && diff.inSeconds > -60) {
                                      etaText = widget.isEnglish ? 'Arriving' : '到達中';
                                      isNearlyArrived = true;
                                    } else if (diff.isNegative) {
                                      etaText = '-';
                                      isDeparted = true;
                                    } else {
                                      final mins = diff.inMinutes;
                                      if (mins < 1) {
                                        etaText = widget.isEnglish ? 'Due' : '即將抵達';
                                        isNearlyArrived = true;
                                      } else {
                                        etaText = widget.isEnglish ? '$mins min' : '$mins分鐘';
                                      }
                                    }
                                  } catch (_) {}
                                }
                                
                                // Yield the ETA widget
                                yield Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        etaText,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDeparted 
                                            ? Colors.grey[400] 
                                            : (isNearlyArrived ? Colors.green : _getEtaColor(etaRaw)),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (rmk.isNotEmpty)
                                        Text(
                                          rmk,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey[600],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                    ],
                                  ),
                                );
                                
                                // Add separator after each ETA except the last one
                                final index = widget.etas.indexOf(e);
                                if (index < widget.etas.take(3).length - 1) {
                                  yield Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                    child: Text(
                                      '|',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[400],
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                  );
                                }
                              }).toList(),
                            ],
                          ),
                        
                        SizedBox(height: 8),
                        
                        // Stop name below
                        Text(
                          widget.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: _isExpanded ? null : 2,
                          overflow: _isExpanded ? null : TextOverflow.ellipsis,
                        ),
                        
                        // Coordinates display
                        if (widget.latitude != null && widget.longitude != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              '📍 ${widget.latitude}, ${widget.longitude}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Pin button
                  IconButton(
                    icon: Icon(Icons.push_pin_outlined, size: 18),
                    tooltip: widget.isEnglish ? 'Pin this stop' : '釘選此站',
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () => _pinStop(context),
                  ),
                  SizedBox(width: 4),
                  
                  // Expand indicator
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                ],
              ),
              
              // Expanded details
              if (_isExpanded && _currentEtas.isNotEmpty) ...[
                Divider(height: 20),
                ..._currentEtas.map((e) {
                  final etaRaw = e['eta'] ?? e['eta_time'];
                  final etaSeq = e['eta_seq']?.toString() ?? '';
                  final rmkEn = e['rmk_en']?.toString() ?? e['rmken']?.toString() ?? '';
                  final rmkTc = e['rmk_tc']?.toString() ?? e['rmktc']?.toString() ?? '';
                  final rmk = widget.isEnglish
                      ? (rmkEn.isNotEmpty ? rmkEn : rmkTc)
                      : (rmkTc.isNotEmpty ? rmkTc : rmkEn);
                  
                  String fullEtaText = '—';
                  if (etaRaw != null) {
                    try {
                      final dt = DateTime.parse(etaRaw.toString()).toLocal();
                      final now = DateTime.now();
                      final diff = dt.difference(now);
                      final mins = diff.inMinutes;
                      
                      if (diff.inMinutes <= 0 && diff.inSeconds > -60) {
                        fullEtaText = widget.isEnglish ? 'Arriving now' : '正在到達';
                      } else if (diff.isNegative) {
                        fullEtaText = widget.isEnglish ? 'Departed' : '已開出';
                      } else if (mins < 1) {
                        fullEtaText = widget.isEnglish ? 'Due now' : '即將抵達';
                      } else {
                        fullEtaText = widget.isEnglish ? '$mins min (${DateFormat.jm().format(dt)})' : '$mins分鐘 (${DateFormat.Hm().format(dt)})';
                      }
                    } catch (_) {}
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _getEtaColor(etaRaw).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              etaSeq,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _getEtaColor(etaRaw),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullEtaText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _getEtaColor(etaRaw),
                                ),
                              ),
                              if (rmk.isNotEmpty)
                                Text(
                                  rmk,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange[700],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StopEtaTile extends StatefulWidget {
  final String stopId;
  const StopEtaTile({Key? key, required this.stopId}) : super(key: key);

  @override
  State<StopEtaTile> createState() => _StopEtaTileState();
}

class _StopEtaTileState extends State<StopEtaTile> {
  bool loading = false;
  String? error;
  List<Map<String, dynamic>>? etas;

  String _formatEtaLocal(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
      // compute relative
      final now = DateTime.now();
      final diff = dt.difference(now);
      String relative;
      if (diff.inSeconds.abs() < 30) {
        relative = 'Due';
      } else if (diff.isNegative) {
        final mins = diff.abs().inMinutes;
        if (mins < 1) {
          relative = 'Departed';
        } else if (mins < 60) {
          relative = '${mins} min ago';
        } else {
          final h = diff.abs().inHours;
          final m = diff.abs().inMinutes % 60;
          relative = '${h}h${m > 0 ? ' ${m}m' : ''} ago';
        }
      } else {
        final mins = diff.inMinutes;
        if (mins < 1) {
          relative = 'Due';
        } else if (mins < 60) {
          relative = '${mins} min';
        } else {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          relative = '${h}h${m > 0 ? ' ${m}m' : ''}';
        }
      }
      final locale = Localizations.localeOf(context).toString();
      final abs = use24 ? DateFormat.Hm().format(dt) : DateFormat.jm(locale).format(dt);
      if (relative == 'Departed') return 'Departed ($abs)';
      return '$relative ($abs)';
    } catch (_) {
      return raw?.toString() ?? '—';
    }
  }

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await Kmb.fetchStopEta(widget.stopId);
      setState(() {
        etas = list;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator()));
    if (error != null) return Padding(padding: const EdgeInsets.all(8.0), child: Text('Error: $error', style: TextStyle(color: Colors.red)));
    if (etas == null || etas!.isEmpty) return Padding(padding: const EdgeInsets.all(8.0), child: Text('No ETA data'));

    return Column(
      children: etas!.map((e) {
        final route = e['route'] ?? '';
        final eta = _formatEtaLocal(e['eta'] ?? null);
        final dest = e['desten'] ?? e['desttc'] ?? '';
        final remark = e['rmken'] ?? e['rmktc'] ?? '';
        return ListTile(
          title: Text('$route → $dest'),
          subtitle: Text('eta: $eta\n$remark'),
        );
      }).toList(),
    );
  }
}

// Independent Route Destination Widget - fetches from Route API
class RouteDestinationWidget extends StatefulWidget {
  final String route;
  final String? direction;
  final String? serviceType;

  const RouteDestinationWidget({
    Key? key,
    required this.route,
    this.direction,
    this.serviceType,
  }) : super(key: key);

  @override
  State<RouteDestinationWidget> createState() => _RouteDestinationWidgetState();
}

class _RouteDestinationWidgetState extends State<RouteDestinationWidget> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _routeData;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchRouteData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    // Refresh route data every 60 seconds (less frequent than ETAs since route info changes rarely)
    _refreshTimer = Timer.periodic(Duration(seconds: 60), (timer) {
      if (mounted) {
        _fetchRouteData(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(RouteDestinationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetch if route parameters change
    if (oldWidget.route != widget.route ||
        oldWidget.direction != widget.direction ||
        oldWidget.serviceType != widget.serviceType) {
      _refreshTimer?.cancel();
      _fetchRouteData();
      _startAutoRefresh();
    }
  }

  Future<void> _fetchRouteData({bool silent = false}) async {
    // Skip fetch if route is empty
    if (widget.route.isEmpty) {
      if (!silent) {
        setState(() {
          _loading = false;
          _error = 'No route specified';
        });
      }
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Construct direction parameter from single char or full string
      String dirParam = 'outbound';
      if (widget.direction != null && widget.direction!.isNotEmpty) {
        final dirStr = widget.direction!.trim().toUpperCase();
        if (dirStr.isNotEmpty) {
          // Handle both single char ('O', 'I') and full strings ('OUTBOUND', 'INBOUND')
          final firstChar = dirStr[0];
          dirParam = (firstChar == 'I') ? 'inbound' : 'outbound';
        }
      }

      final svcType = widget.serviceType ?? '1';
      final routeUpper = widget.route.trim().toUpperCase();
      
      final details = await Kmb.fetchRouteWithParams(
        routeUpper, 
        dirParam, 
        svcType
      );
      
      if (!mounted) return; // Check if widget is still mounted
      
      setState(() {
        _routeData = details.containsKey('data')
            ? (details['data'] as Map<String, dynamic>?)
            : details;
        if (!silent) {
          _loading = false;
        }
      });
    } catch (e) {
      if (!mounted) return; // Check if widget is still mounted
      
      if (!silent) {
        print('RouteDestinationWidget error for route ${widget.route}: $e');
      }
      setState(() {
        _error = e.toString();
        if (!silent) {
          _loading = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isEnglish = lang.isEnglish;

    // Loading state
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Error state
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error loading route',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // No data state
    if (_routeData == null) {
      return SizedBox.shrink();
    }

    // Extract route information
    final orig = isEnglish
        ? (_routeData!['orig_en'] ?? _routeData!['orig_tc'] ?? '')
        : (_routeData!['orig_tc'] ?? _routeData!['orig_en'] ?? '');
    final dest = isEnglish
        ? (_routeData!['dest_en'] ?? _routeData!['dest_tc'] ?? '')
        : (_routeData!['dest_tc'] ?? _routeData!['dest_en'] ?? '');
    final bound = _routeData!['bound'] as String?;

    // Direction icon
    IconData dirIcon = Icons.arrow_forward;
    Color dirColor = Colors.blue;
    if (bound == 'O') {
      dirIcon = Icons.arrow_circle_right;
      dirColor = Colors.green;
    } else if (bound == 'I') {
      dirIcon = Icons.arrow_circle_left;
      dirColor = Colors.orange;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Direction icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: dirColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      dirIcon,
                      color: dirColor,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),

                  // Route origin and destination
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (orig.isNotEmpty) ...[
                          Text(
                            '${isEnglish ? 'From' : '由'}: $orig',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                        ],
                        Text(
                          '${isEnglish ? 'To' : '往'}: $dest',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
