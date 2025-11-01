import 'package:flutter/material.dart';
import 'dart:async';
import 'kmb.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'kmb_route_status_page.dart';
import 'main.dart' show LanguageProvider;

class KmbNearbyPage extends StatefulWidget {
  const KmbNearbyPage({Key? key}) : super(key: key);

  @override
  State<KmbNearbyPage> createState() => _KmbNearbyPageState();
}

class _KmbNearbyPageState extends State<KmbNearbyPage> {
  bool _loading = true;
  String? _error;
  Position? _position;
  List<_StopDistance> _nearby = [];
  // Cache for stop ETAs to avoid repeated fetches
  final Map<String, List<Map<String, dynamic>>> _stopEtaCache = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
      _nearby = [];
    });

    // Get language preference early for error messages
    LanguageProvider? langProv;
    if (mounted) {
      langProv = context.read<LanguageProvider>();
    }

    try {
      // Request location permission using permission_handler for consistent UX
      final status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() {
          _error = langProv?.isEnglish ?? true ? 'Location permission denied' : '位置權限被拒絕';
          _loading = false;
        });
        return;
      }

      // Use Geolocator to obtain a position
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _position = pos;

      // Build stop map and compute distances
      final stopMap = await Kmb.buildStopMap();
      final List<_StopDistance> list = [];
      stopMap.forEach((stopId, meta) {
        try {
          final latRaw = meta['lat'] ?? meta['latitude'] ?? meta['latitud'] ?? meta['lat'];
          final lngRaw = meta['long'] ?? meta['lng'] ?? meta['lon'] ?? meta['longitude'] ?? meta['long'];
          if (latRaw == null || lngRaw == null) return;
          final lat = double.tryParse(latRaw.toString());
          final lng = double.tryParse(lngRaw.toString());
          if (lat == null || lng == null) return;
          final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
          list.add(_StopDistance(stopId: stopId, lat: lat, lng: lng, distanceMeters: dist, meta: meta));
        } catch (_) {}
      });

      list.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      // Cap results to 50 nearby stops to avoid too many API calls
      setState(() {
        _nearby = list.take(50).toList();
        _loading = false;
      });

      // Fetch ETAs for nearby stops
      _fetchEtasForNearbyStops();
      
      // Set up auto-refresh every 30 seconds
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
        _fetchEtasForNearbyStops();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchEtasForNearbyStops() async {
    for (final stop in _nearby) {
      try {
        final etas = await Kmb.fetchStopEta(stop.stopId);
        if (mounted) {
          setState(() {
            _stopEtaCache[stop.stopId] = etas;
          });
        }
      } catch (_) {
        // Silently ignore ETA fetch failures for individual stops
      }
    }
  }

  String _fmtDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  @override
  Widget build(BuildContext context) {
    final langProv = context.watch<LanguageProvider>();
    
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(child: Text('${langProv.isEnglish ? "Error" : "錯誤"}: $_error', style: const TextStyle(color: Colors.red)))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text('${langProv.isEnglish ? "Location" : "位置"}: ${_position?.latitude.toStringAsFixed(6) ?? '-'}, ${_position?.longitude.toStringAsFixed(6) ?? '-'}'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _nearby.length,
                        itemBuilder: (context, idx) {
                          final s = _nearby[idx];
                          final nameEn = s.meta['name_en'] ?? s.meta['nameen'] ?? s.meta['nameen_us'] ?? s.meta['name_en_us'] ?? '';
                          final nameTc = s.meta['name_tc'] ?? s.meta['nametc'] ?? s.meta['name_tc_tw'] ?? '';
                          final displayName = langProv.isEnglish
                              ? ((nameEn?.toString().isNotEmpty ?? false) ? nameEn.toString() : (nameTc?.toString().isNotEmpty ?? false ? nameTc.toString() : s.stopId))
                              : ((nameTc?.toString().isNotEmpty ?? false) ? nameTc.toString() : (nameEn?.toString().isNotEmpty ?? false ? nameEn.toString() : s.stopId));
                          
                          // Get ETAs for this stop
                          final etas = _stopEtaCache[s.stopId] ?? [];
                          
                          // Group ETAs by route
                          final Map<String, List<Map<String, dynamic>>> etasByRoute = {};
                          for (final eta in etas) {
                            final route = eta['route']?.toString() ?? '';
                            if (route.isEmpty) continue;
                            etasByRoute.putIfAbsent(route, () => []).add(eta);
                          }
                          
                          // Build subtitle with upcoming ETAs
                          final List<String> etaLines = [];
                          etasByRoute.forEach((route, routeEtas) {
                            // Sort by eta time
                            routeEtas.sort((a, b) {
                              final etaA = a['eta']?.toString() ?? '';
                              final etaB = b['eta']?.toString() ?? '';
                              return etaA.compareTo(etaB);
                            });
                            
                            // Get first 2 ETAs for this route
                            final nextEtas = routeEtas.take(2).map((e) {
                              final etaStr = e['eta']?.toString() ?? '';
                              if (etaStr.isEmpty) return '—';
                              try {
                                final dt = DateTime.parse(etaStr).toLocal();
                                final now = DateTime.now();
                                final diff = dt.difference(now);
                                if (diff.inMinutes <= 0) return langProv.isEnglish ? 'Due' : '即到';
                                if (diff.inMinutes < 60) return '${diff.inMinutes}m';
                                return DateFormat.Hm().format(dt);
                              } catch (_) {
                                return '—';
                              }
                            }).join(', ');
                            
                            final destEn = routeEtas.first['dest_en'] ?? routeEtas.first['desten'] ?? '';
                            final destTc = routeEtas.first['dest_tc'] ?? routeEtas.first['desttc'] ?? '';
                            final displayDest = langProv.isEnglish 
                                ? (destEn.toString().isNotEmpty ? destEn : (destTc.toString().isNotEmpty ? destTc : '?'))
                                : (destTc.toString().isNotEmpty ? destTc : (destEn.toString().isNotEmpty ? destEn : '?'));
                            etaLines.add('$route → $displayDest: $nextEtas');
                          });
                          
                          final subtitleText = etaLines.isEmpty 
                            ? '${s.stopId} · ${_fmtDistance(s.distanceMeters)}'
                            : '${_fmtDistance(s.distanceMeters)} · ${etaLines.take(2).join(' | ')}';
                          
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(child: Text('${idx + 1}', style: TextStyle(fontSize: 12))),
                              title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(subtitleText, style: TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                _showStopDetails(context, s, etas);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )),
    );
  }

  void _showStopDetails(BuildContext context, _StopDistance stop, List<Map<String, dynamic>> etas) {
    final langProv = context.read<LanguageProvider>();
    final nameEn = stop.meta['name_en'] ?? stop.meta['nameen'] ?? '';
    final nameTc = stop.meta['name_tc'] ?? stop.meta['nametc'] ?? '';
    final displayName = langProv.isEnglish
        ? ((nameEn?.toString().isNotEmpty ?? false) ? nameEn.toString() : (nameTc?.toString().isNotEmpty ?? false ? nameTc.toString() : stop.stopId))
        : ((nameTc?.toString().isNotEmpty ?? false) ? nameTc.toString() : (nameEn?.toString().isNotEmpty ?? false ? nameEn.toString() : stop.stopId));
    
    // Group ETAs by route
    final Map<String, List<Map<String, dynamic>>> etasByRoute = {};
    for (final eta in etas) {
      final route = eta['route']?.toString() ?? '';
      if (route.isEmpty) continue;
      etasByRoute.putIfAbsent(route, () => []).add(eta);
    }
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(displayName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(langProv.isEnglish ? 'Stop ID: ${stop.stopId}' : '站點編號: ${stop.stopId}', style: TextStyle(fontSize: 12)),
              Text(langProv.isEnglish ? 'Distance: ${_fmtDistance(stop.distanceMeters)}' : '距離: ${_fmtDistance(stop.distanceMeters)}', style: TextStyle(fontSize: 12)),
              Text('Lat: ${stop.lat.toStringAsFixed(6)}, Lng: ${stop.lng.toStringAsFixed(6)}', style: TextStyle(fontSize: 11, color: Colors.grey)),
              SizedBox(height: 12),
              if (etasByRoute.isEmpty)
                Text(langProv.isEnglish ? 'No upcoming ETAs' : '沒有即將到站的班次', style: TextStyle(color: Colors.grey))
              else
                ...etasByRoute.entries.map((entry) {
                  final route = entry.key;
                  final routeEtas = entry.value;
                  
                  // Sort by eta time
                  routeEtas.sort((a, b) {
                    final etaA = a['eta']?.toString() ?? '';
                    final etaB = b['eta']?.toString() ?? '';
                    return etaA.compareTo(etaB);
                  });
                  
                  final destEn = routeEtas.first['dest_en'] ?? routeEtas.first['desten'] ?? '';
                  final destTc = routeEtas.first['dest_tc'] ?? routeEtas.first['desttc'] ?? '';
                  final displayDest = langProv.isEnglish ? destEn : (destTc.isNotEmpty ? destTc : destEn);
                  final bound = routeEtas.first['dir'] ?? routeEtas.first['bound'] ?? '';
                  final serviceType = routeEtas.first['service_type'] ?? routeEtas.first['servicetype'] ?? '';
                  
                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      title: Text('Route $route → $displayDest', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: routeEtas.take(3).map((eta) {
                          final etaStr = eta['eta']?.toString() ?? '';
                          final rmkEn = eta['rmk_en'] ?? eta['rmken'] ?? '';
                          final rmkTc = eta['rmk_tc'] ?? eta['rmktc'] ?? '';
                          final rmk = langProv.isEnglish ? rmkEn : (rmkTc.isNotEmpty ? rmkTc : rmkEn);
                          
                          String timeDisplay = '—';
                          if (etaStr.isNotEmpty) {
                            try {
                              final dt = DateTime.parse(etaStr).toLocal();
                              final now = DateTime.now();
                              final diff = dt.difference(now);
                              if (diff.inMinutes <= 0) {
                                timeDisplay = langProv.isEnglish ? 'Due' : '即將到站';
                              } else if (diff.inMinutes < 60) {
                                timeDisplay = langProv.isEnglish ? '${diff.inMinutes} min' : '${diff.inMinutes}分鐘';
                              } else {
                                timeDisplay = DateFormat.Hm().format(dt);
                              }
                            } catch (_) {}
                          }
                          
                          return Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              rmk.toString().isNotEmpty ? '$timeDisplay · $rmk' : timeDisplay,
                              style: TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        // Navigate to route status page
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => KmbRouteStatusPage(
                            route: route,
                            bound: bound.toString().isNotEmpty ? bound.toString().toUpperCase() : null,
                            serviceType: serviceType.toString().isNotEmpty ? serviceType.toString() : null,
                          ),
                        ));
                      },
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(langProv.isEnglish ? 'Close' : '關閉'),
          ),
        ],
      ),
    );
  }
}

class _StopDistance {
  final String stopId;
  final double lat;
  final double lng;
  final double distanceMeters;
  final Map<String, dynamic> meta;
  _StopDistance({required this.stopId, required this.lat, required this.lng, required this.distanceMeters, required this.meta});
}
