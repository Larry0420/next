import 'package:flutter/material.dart';
import 'kmb.dart';
import 'settings_page.dart';
import 'dart:convert';

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

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
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
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: loading
            ? Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text('Error: $error', style: TextStyle(color: Colors.red)))
                : data == null
                    ? Center(child: Text('No data'))
                    : _buildStructuredView(),
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
      }

      // ETA entries (contains etaseq or eta)
      if (first.containsKey('etaseq') || first.containsKey('eta')) {
        sections.add(_buildEtaList(payload.cast<Map<String, dynamic>>()));
      }

      // If none of the above matched, fall back to raw list view
      if (!first.containsKey('route') && !first.containsKey('seq') && !first.containsKey('eta')) {
        sections.add(_buildRawJsonCard());
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
