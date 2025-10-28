import 'package:flutter/material.dart';
import 'kmb.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'settings_page.dart';
import 'package:provider/provider.dart';
import 'main.dart' show LanguageProvider;
import 'widgets/saved_files_list.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class KmbRouteStatusPage extends StatefulWidget {
  final String route;
  const KmbRouteStatusPage({Key? key, required this.route}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    _fetch();
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
        _loadVariantsFromCache(r);
      } else {
        final result = await Kmb.fetchRouteStatus(r);
        setState(() { data = result; });
        _loadVariantsFromCache(r);
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
        // enrich with stop metadata if available
        try {
          final stopMap = await Kmb.buildStopMap();
          final enriched = entries.map((e) {
            final sid = e['stop']?.toString() ?? '';
            return {
              ...e,
              'stopInfo': stopMap[sid],
            };
          }).toList();
          setState(() {
            data = {
              'type': 'RouteStopList',
              'version': 'prebuilt-asset',
              'generatedtimestamp': DateTime.now().toIso8601String(),
              'data': enriched,
            };
            // also set combined data so combined card shows stopInfo and empty etas
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
        } catch (_) {
          setState(() {
            data = {
              'type': 'RouteStopList',
              'version': 'prebuilt-asset',
              'generatedtimestamp': DateTime.now().toIso8601String(),
              'data': entries,
            };
          });
        }
        // populate variants from cache by ensuring route->stops map is built
        try { await Kmb.buildRouteToStopsMap(); } catch (_) {}
        _loadVariantsFromCache(r);
        return true;
      }

      // Try base numeric key
      final base = RegExp(r'^(\d+)').firstMatch(r)?.group(1);
      if (base != null && decoded.containsKey(base)) {
        final entries = List<Map<String, dynamic>>.from((decoded[base] as List).map((e) => Map<String, dynamic>.from(e)));
        try {
          final stopMap = await Kmb.buildStopMap();
          final enriched = entries.map((e) {
            final sid = e['stop']?.toString() ?? '';
            return {
              ...e,
              'stopInfo': stopMap[sid],
            };
          }).toList();
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
        } catch (_) {
          setState(() {
            data = {
              'type': 'RouteStopList',
              'version': 'prebuilt-asset',
              'generatedtimestamp': DateTime.now().toIso8601String(),
              'data': entries,
            };
          });
        }
        try { await Kmb.buildRouteToStopsMap(); } catch (_) {}
        _loadVariantsFromCache(r);
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Route ${widget.route}'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _fetch,
          ),
          IconButton(
            icon: Icon(Icons.cloud_download),
            tooltip: 'Fetch combined status (route + stops + ETA)',
            onPressed: _fetchCombined,
          ),
          IconButton(
            icon: Icon(Icons.save_alt),
            tooltip: 'Save current response to file',
            onPressed: () async {
              // Prepare filename and payload similarly to helper
              final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
              final rawFilename = 'kmb_route_${widget.route}_$timestamp';
              dynamic toSave = _combinedData ?? data;
              if (toSave == null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nothing to save')));
                return;
              }
              if (toSave is Map == false) {
                try {
                  toSave = json.decode(json.encode(toSave));
                } catch (e) {
                  toSave = {'value': toSave.toString()};
                }
              }
              final res = await Kmb.saveRequestJsonToFile(rawFilename, toSave);
              if (res.ok) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${res.path}')));
              } else {
                final msg = res.error ?? 'Unknown error while saving';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $msg')));
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.folder_open),
            tooltip: 'Open saved responses',
            onPressed: () async {
              final restored = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SavedFilesPage()));
              if (restored != null) {
                // restored contains the JSON data returned from preview->Restore
                setState(() {
                  data = Map<String, dynamic>.from(restored as Map);
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored saved snapshot')));
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage())),
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

  Widget _buildStructuredView() {
    final type = data!['type'] ?? '';
    final version = data!['version'] ?? '';
    final generated = data!['generatedtimestamp'] ?? '';
    final payload = data!['data'];

    List<Widget> sections = [];

    sections.add(Card(
      child: ListTile(
        title: Text('Response'),
        subtitle: Text('type: $type\nversion: $version\ngenerated: $generated'),
      ),
    ));

    // If payload is a list, inspect the first item to determine its shape
    if (payload is List && payload.isNotEmpty) {
      final first = payload.first as Map<String, dynamic>;

      // Route info/list (contains route, co, bound)
      if (first.containsKey('route') && first.containsKey('co')) {
        // Render each unique route entry
        sections.add(_buildRouteInfoList(payload.cast<Map<String, dynamic>>()));
      }

      // Route-stop list (contains seq and stop)
      if (first.containsKey('seq') && first.containsKey('stop')) {
        sections.add(_buildStopsList(payload.cast<Map<String, dynamic>>()));
        sections.add(_buildOptimizedStationList());
      }

      // ETA entries (contains etaseq or eta)
      if (first.containsKey('etaseq') || first.containsKey('eta')) {
        sections.add(_buildEtaList(payload.cast<Map<String, dynamic>>()));
      }

      // If none of the above matched, fall back to raw list view
      if (!first.containsKey('route') && !first.containsKey('seq') && !first.containsKey('eta')) {
        sections.add(_buildRawJsonCard());
      }

      // If we have combined data, show it prominently
      if (_combinedData != null) {
        sections.insert(0, _buildCombinedCard(_combinedData!));
      }
    } else if (payload is Map<String, dynamic>) {
      // Single-object payload: show its fields
      sections.add(_buildKeyValueCard('Data', payload));
    } else {
      sections.add(_buildRawJsonCard());
    }

    // If we have discovered service types, show selectors and route-level ETA controls
    if (_serviceTypes.isNotEmpty) {
      sections.insert(1, _buildSelectorsCard());
      sections.insert(2, _buildRouteEtaCard());
    }

    // Always include raw JSON at the end for debugging
    sections.add(_buildRawJsonCard());

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
                  setState(() => _selectedDirection = v);
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
                    if (v != null) _fetchRouteEta(widget.route.trim().toUpperCase(), v);
                  });
                },
              ),
            ],
          ],
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
          final etaseq = r['etaseq']?.toString() ?? '';
          final eta = r['eta']?.toString() ?? '';
          final dest = r['desten'] ?? r['desttc'] ?? '';
          final remark = r['rmken'] ?? r['rmktc'] ?? '';
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
            final etas = (s['etas'] as List?) ?? [];
            final stopName = stopInfo != null ? (stopInfo['nameen'] ?? stopInfo['nametc'] ?? stopId) : stopId;
            return ListTile(
              title: Text('$stopId · $stopName'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (etas.isEmpty) Text('No ETAs'),
                  for (final e in etas)
                    Text('${e['etaseq'] ?? ''} · ${e['eta'] ?? ''} · ${e['desten'] ?? e['desttc'] ?? ''}'),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  void _loadVariantsFromCache(String r) async {
    try {
      await Kmb.buildRouteToStopsMap();
      final variants = Kmb.discoverRouteVariants(r);
      setState(() {
        _directions = variants['directions'] ?? [];
        _serviceTypes = variants['serviceTypes'] ?? [];
        _selectedDirection = _directions.isNotEmpty ? _directions.first : null;
        _selectedServiceType = _serviceTypes.isNotEmpty ? _serviceTypes.first : null;
      });
      if (_selectedServiceType != null) {
        _fetchRouteEta(r, _selectedServiceType!);
      }
    } catch (_) {}
  }

  Future<void> _fetchRouteEta(String route, String serviceType) async {
    setState(() {
      _routeEtaLoading = true;
      _routeEtaError = null;
      _routeEtaEntries = null;
    });
    try {
      final entries = await Kmb.fetchRouteEta(route, serviceType);
      entries.sort((a, b) {
        final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
        final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
        return ai.compareTo(bi);
      });
      setState(() { _routeEtaEntries = entries; });
    } catch (e) {
      setState(() { _routeEtaError = e.toString(); });
    } finally {
      setState(() { _routeEtaLoading = false; });
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
          final eta = entry['eta']?.toString() ?? '';
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

  Widget _buildOptimizedStationList() {
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
        if (entries.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(12.0), child: Text('No station data for route')));

        // Language preference
        final lang = context.watch<LanguageProvider>();
        final isEnglish = lang.isEnglish;

        // Filter by bound O/I (keep all if not present) and sort by seq
        final stops = List<Map<String, dynamic>>.from(entries.where((e) => e.containsKey('seq')));
        stops.sort((a, b) {
          final ai = int.tryParse(a['seq']?.toString() ?? '') ?? 0;
          final bi = int.tryParse(b['seq']?.toString() ?? '') ?? 0;
          return ai.compareTo(bi);
        });

        return Card(
          child: ExpansionTile(
            title: Text('User-Friendly Station List (${stops.length})'),
            children: stops.map((s) {
              final seq = s['seq']?.toString() ?? '';
              final stopId = s['stop']?.toString() ?? '';
              final bound = s['bound'] ?? '';

              // prefer stop metadata from stopMap
              final meta = stopMap[stopId];
              final nameEn = meta != null ? (meta['name_en'] ?? meta['nameen'] ?? meta['nameen_us'] ?? '')?.toString() ?? '' : (s['nameen']?.toString() ?? '');
              final nameTc = meta != null ? (meta['name_tc'] ?? meta['nametc'] ?? meta['name_tc_tw'] ?? '')?.toString() ?? '' : (s['nametc']?.toString() ?? '');
              final displayName = isEnglish
                  ? (nameEn.isNotEmpty ? nameEn : (nameTc.isNotEmpty ? nameTc : stopId))
                  : (nameTc.isNotEmpty ? nameTc : (nameEn.isNotEmpty ? nameEn : stopId));

              return ExpansionTile(
                title: Text('$seq · $displayName ${bound != '' ? '· $bound' : ''}'),
                children: [
                  ListTile(
                    title: Text('Stop details'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((meta?['lat'] ?? s['lat']) != null) Text('Lat: ${meta?['lat'] ?? s['lat']}'),
                        if ((meta?['long'] ?? meta?['lng'] ?? s['long'] ?? s['lng']) != null) Text('Lng: ${meta?['long'] ?? meta?['lng'] ?? s['long'] ?? s['lng']}'),
                        Text('ID: $stopId'),
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: StopEtaTile(stopId: stopId),
                        ),
                      ],
                    ),
                  )
                ],
              );
            }).toList(),
          ),
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
        final eta = e['eta'] ?? '';
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
