import 'package:flutter/material.dart';
import 'dart:ui';
import 'kmb.dart';
import 'kmb_route_status_page.dart';

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
    final theme = Theme.of(context);
  final filteredRoutes = input.isEmpty
    ? <String>[]
    : routes.where((r) => r.toLowerCase().contains(input.toLowerCase())).toList();
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
              child: Text('Enter Route:', style: TextStyle(fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(input, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            ),
            SizedBox(height: 8),

            // status indicators
            if (loading) Center(child: CircularProgressIndicator(year2023: false,)),
            if (error != null) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Error: $error', style: TextStyle(color: Colors.red)),
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
                                tiles.add(
                                  Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    color: theme.colorScheme.surfaceVariant,
                                    child: ListTile(
                                      title: _buildHighlightedText(route, input),
                                      onTap: () {
                                        final r = route.trim().toUpperCase();
                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: r)));
                                        widget.onRouteSelected?.call(r);
                                      },
                                    ),
                                  ),
                                );
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
                                      children: variants.map((route) => ListTile(
                                        title: _buildHighlightedText(route, input),
                                        onTap: () {
                                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => KmbRouteStatusPage(route: route)));
                                          widget.onRouteSelected?.call(route);
                                        },
                                      )).toList(),
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
                            final idx = r * 2 + c;
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
