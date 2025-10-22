import 'package:flutter/material.dart';
import 'kmb.dart';
import 'kmb_route_status_page.dart';

class KmbDialer extends StatefulWidget {
  final void Function(String route)? onRouteSelected;
  const KmbDialer({Key? key, this.onRouteSelected}) : super(key: key);

  @override
  State<KmbDialer> createState() => _KmbDialerState();
}

class _KmbDialerState extends State<KmbDialer> {
  String input = '';
  List<String> routes = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    setState(() { loading = true; error = null; });
    try {
      routes = await Kmb.fetchRoutes();
    } catch (e) {
      error = e.toString();
    }
    setState(() { loading = false; });
  }

  void _onKeyTap(String value) {
    setState(() {
      input += value;
    });
  }

  void _onBackspace() {
    setState(() {
      if (input.isNotEmpty) input = input.substring(0, input.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredRoutes = routes.where((r) => r.startsWith(input)).toList();
    return Column(
      children: [
        Text('Enter Route:', style: TextStyle(fontSize: 18)),
        Text(input, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        _buildDialer(),
        SizedBox(height: 16),
        if (loading) CircularProgressIndicator(),
        if (error != null) Text('Error: $error', style: TextStyle(color: Colors.red)),
        if (!loading && error == null)
          Expanded(
            child: Builder(builder: (_) {
              // Group filtered routes by their numeric base (e.g., '11', '11A' -> base '11')
              final Map<String, List<String>> groups = {};
              final baseRe = RegExp(r'^(\d+)');
              for (final route in filteredRoutes) {
                final m = baseRe.firstMatch(route);
                final base = m != null ? m.group(1)! : route;
                groups.putIfAbsent(base, () => []).add(route);
              }

              // Sort group keys numerically where possible
              final sortedBases = groups.keys.toList()
                ..sort((a, b) {
                  final ai = int.tryParse(a);
                  final bi = int.tryParse(b);
                  if (ai != null && bi != null) return ai.compareTo(bi);
                  return a.compareTo(b);
                });

              final List<Widget> tiles = [];
              for (final base in sortedBases) {
                final variants = groups[base]!..sort((x, y) {
                  // prefer the plain numeric base (e.g. '11') before letter variants (e.g. '11A')
                  if (x == base && y != base) return -1;
                  if (y == base && x != base) return 1;
                  // otherwise fallback to lexical order
                  return x.compareTo(y);
                });

                if (variants.length == 1) {
                  final route = variants.first;
                  tiles.add(ListTile(
                    title: Text(route),
                    onTap: () {
                      final r = route.trim().toUpperCase();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r)));
                      widget.onRouteSelected?.call(r);
                    },
                  ));
                } else {
                  tiles.add(ExpansionTile(
                    title: Text('$base (${variants.length})'),
                    children: variants.map((route) => ListTile(
                      title: Text(route),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: route)));
                        widget.onRouteSelected?.call(route);
                      },
                    )).toList(),
                  ));
                }
              }

              if (tiles.isEmpty) {
                return Center(child: Text('No routes found'));
              }

              return ListView(children: tiles);
            }),
          ),
      ],
    );
  }

  Widget _buildDialer() {
    // Build next possible keys based on actual routes and current input.
    // Avoid substring/index errors by using startsWith and checking lengths.
    final Set<String> nextKeys = {};

    for (final route in routes) {
      if (!route.startsWith(input)) continue;
      // If route equals input exactly, no next key from this route
      if (route.length == input.length) continue;
      // The next character after the input is a valid next key (digit or letter)
      final nextChar = route[input.length];
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

    // Add special keys
    final List<String> specialKeys = ['<', 'OK'];
    final List<String> allKeys = [...keys, ...specialKeys];

    // Display keys in rows of 4
    final int rowLength = 4;
    final List<List<String>> keyRows = [];
    for (int i = 0; i < allKeys.length; i += rowLength) {
      keyRows.add(allKeys.sublist(i, (i + rowLength > allKeys.length) ? allKeys.length : i + rowLength));
    }

    return Column(
      children: keyRows.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((key) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                if (key == '<') _onBackspace();
                else if (key == 'OK') {
                  if (routes.contains(input)) {
                    // Navigate to route status page for exact match
                    final r = input.trim().toUpperCase();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r)));
                    widget.onRouteSelected?.call(r);
                  }
                } else {
                  _onKeyTap(key);
                }
              },
              child: Text(key, style: TextStyle(fontSize: 24)),
              style: ElevatedButton.styleFrom(minimumSize: Size(64, 64)),
            ),
          );
        }).toList(),
      )).toList(),
    );
  }
}
