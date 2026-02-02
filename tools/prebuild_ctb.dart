// Prebuild script to fetch CTB route-stops and stops and write to assets/prebuilt
//
// Based on CTB API Specifications v2.01 (July 2023):
// - Base URL: https://rt.data.gov.hk/v2/transport/citybus/
// - Routes: route-stop/{company_id}/{route}/{direction}
// - Stops: stop/{stop_id}
// - Company: CTB

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  print('prebuild_ctb: starting');

  // Ensure we write to the project-root `assets/prebuilt` directory
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final projectRoot = scriptDir.parent;
  final outDir = Directory('${projectRoot.path}/assets/prebuilt');

  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  const baseUrl = 'https://rt.data.gov.hk/v2/transport/citybus';
  const companyId = 'CTB';

  // 1. Fetch route list for destinations and directions
  final routeUrls = ['$baseUrl/route/$companyId'];
  final Map<String, Map<String, String>> routeInfo = {};
  bool routeInfoOk = false;

  for (final u in routeUrls) {
    try {
      final response =
          await http.get(Uri.parse(u)).timeout(const Duration(seconds: 30));
      print('GET $u -> ${response.statusCode}');

      if (response.statusCode != 200) continue;

      final jsonData = json.decode(response.body);
      final data = jsonData['data'] as List;

      for (final item in data) {
        final route = (item['route'] ?? '').toString().toUpperCase();
        final origEn = (item['orig_en'] ?? item['origen'] ?? '').toString();
        final origTc = (item['orig_tc'] ?? item['origtc'] ?? '').toString();
        final destEn = (item['dest_en'] ?? item['desten'] ?? '').toString();
        final destTc = (item['dest_tc'] ?? item['desttc'] ?? '').toString();

        routeInfo[route] = {
          'orig_en': origEn,
          'orig_tc': origTc,
          'dest_en': destEn,
          'dest_tc': destTc,
        };
      }

      routeInfoOk = routeInfo.isNotEmpty;
      print('Fetched ${routeInfo.length} routes with origins and destinations');

      if (routeInfoOk) break;
    } catch (e) {
      stderr.writeln('failed $u: $e');
    }
  }

  if (!routeInfoOk) {
    stderr.writeln('Failed to fetch route info');
    exit(1);
  }

  // ---------------------------------------------------------
  // 2. Fetch Route-Stops (Discovery Phase)
  // We fetch this FIRST to discover all valid Stop IDs
  // ---------------------------------------------------------
  
  print('Fetching route-stops for ${routeInfo.length} routes...');

  final Map<String, dynamic> routeMap = {};
  final Set<String> discoveredStopIds = {}; // Collection of all stops found
  
  const int routeBatchSize = 30;

  // Build list of all route/direction combinations
  final List<({String route, String direction})> routeDirections = [];
  for (final route in routeInfo.keys) {
    for (final direction in ['inbound', 'outbound']) {
      routeDirections.add((route: route, direction: direction));
    }
  }

  print('Total ${routeDirections.length} route-directions to fetch');

  int routeSuccessCount = 0;
  int routeSkipCount = 0;

  // Hardcoded blacklist for known dirty data (Route 969 issues)
  const badStopsFor969 = {
    '001476', // Cross Harbour Tunnel
    '002570', // Elizabeth House
    '002417', // Gloucester Rd
    '002421', // Fenwick St
    '001074', // Admiralty Centre
    '001181', // Queen Victoria St
    '001037', // Rumsey St
    '001027', // Central (Macau Ferry)
  };

  for (int i = 0; i < routeDirections.length; i += routeBatchSize) {
    final batch = routeDirections.skip(i).take(routeBatchSize).toList();
    
    final futures = batch.map((rd) async {
      final routeStopsUrl = '$baseUrl/route-stop/$companyId/${rd.route}/${rd.direction}';
      
      try {
        final response = await http.get(Uri.parse(routeStopsUrl))
            .timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          final jsonData = json.decode(response.body);
          final data = jsonData['data'] as List?;
          
          if (data == null || data.isEmpty) return null;
          
          final normalizedDir = rd.direction == 'inbound' ? 'I' : 'O';
          final routeStops = <Map<String, dynamic>>[];
          
          for (final item in data) {
            try {
              final entry = Map<String, dynamic>.from(item as Map);
              
              final r = (entry['route'] ?? '').toString().toUpperCase().trim();
              final dir = (entry['dir'] ?? '').toString().toUpperCase().trim();
              String stopId = (entry['stop'] ?? '').toString().trim();
              
              if (r != rd.route || dir != normalizedDir) continue;

              // ---------------------------------------------------------
              // FIX: HARDCODED DATA SANITIZER
              // Filter out known dirty data without needing an external file
              // ---------------------------------------------------------
              if (r == '969' && badStopsFor969.contains(stopId)) {
                // Silently skip (or log if debugging needed)
                // print('SANITIZER: Removed dirty stop $stopId from Route 969');
                continue;
              }
              // ---------------------------------------------------------

              // Stop is valid, add to discovery set
              discoveredStopIds.add(stopId);
              routeStops.add(entry);

            } catch (e) {
              stderr.writeln('Parse error in ${rd.route}/${rd.direction}: $e');
            }
          }
          
          if (routeStops.isNotEmpty) {
            return (route: rd.route, direction: normalizedDir, stops: routeStops);
          }
        } else if (response.statusCode == 422 || response.statusCode == 404) {
          return null; 
        } else {
          stderr.writeln('Failed $routeStopsUrl: ${response.statusCode}');
        }
      } catch (e) {
        stderr.writeln('Error fetching ${rd.route}/${rd.direction}: $e');
      }
      
      return null;
    }).toList();
    
    final results = await Future.wait(futures);
    
    for (final result in results) {
      if (result != null) {
        routeMap
            .putIfAbsent(result.route, () => {})
            .putIfAbsent(result.direction, () => [])
            .addAll(result.stops);
        routeSuccessCount++;
      } else {
        routeSkipCount++;
      }
    }
    
    print('Processed ${i + batch.length}/${routeDirections.length} route-directions '
          '($routeSuccessCount successful, $routeSkipCount skipped)');
  }

  if (routeMap.isEmpty) {
    stderr.writeln('Failed to fetch any route-stops');
    exit(1);
  }

  // ---------------------------------------------------------
  // 3. Fetch Details for Discovered Stops
  // Now that we have the list of stops from the routes, we fetch their names
  // ---------------------------------------------------------

  final List<String> stopList = discoveredStopIds.toList();
  print('Fetching details for ${stopList.length} discovered unique stops...');

  final Map<String, Map<String, dynamic>> stopsMap = {};
  const int stopBatchSize = 50;
  int stopSuccessCount = 0;
  int stopFailCount = 0;

  for (int i = 0; i < stopList.length; i += stopBatchSize) {
    final batch = stopList.skip(i).take(stopBatchSize).toList();
    
    final futures = batch.map((stopId) async {
      final url = '$baseUrl/stop/$stopId';
      
      try {
        final response = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final jsonData = json.decode(response.body);
          final stopData = jsonData['data'] as Map<String, dynamic>?;
          
          if (stopData != null) {
            return MapEntry(stopId, Map<String, dynamic>.from(stopData));
          }
        }
      } catch (e) {
        stderr.writeln('Error fetching $stopId: $e');
      }
      return null;
    }).toList();
    
    final results = await Future.wait(futures);
    
    for (final entry in results) {
      if (entry != null) {
        stopsMap[entry.key] = entry.value;
        stopSuccessCount++;
      } else {
        stopFailCount++;
      }
    }
    
    print('Processed ${i + batch.length}/${stopList.length} stops '
          '($stopSuccessCount successful, $stopFailCount failed)');
  }

  // Write stops map
  final stopsOutTmp = File('${outDir.path}/ctb_stops.json.tmp');
  stopsOutTmp.writeAsStringSync(json.encode(stopsMap));

  final stopsOut = File('${outDir.path}/ctb_stops.json');
  if (stopsOut.existsSync()) stopsOut.deleteSync();
  stopsOutTmp.renameSync(stopsOut.path);

  print('Wrote ${stopsOut.path} (${stopsMap.length} stops)');

  // ---------------------------------------------------------
  // 4. Build and Write Output Files
  // ---------------------------------------------------------

  // Build optimized route-stops mapping
  final Map<String, dynamic> optimizedRouteMap = {};

  for (final route in routeMap.keys) {
    final directionData = routeMap[route]!;
    final Map<String, dynamic> routeData = {};

    final routeMeta = routeInfo[route];
    final routeOrigEn = routeMeta?['orig_en'] ?? '';
    final routeOrigTc = routeMeta?['orig_tc'] ?? '';
    final routeDestEn = routeMeta?['dest_en'] ?? '';
    final routeDestTc = routeMeta?['dest_tc'] ?? '';

    for (final direction in directionData.keys) {
      final stops = directionData[direction] as List;
      if (stops.isEmpty) continue;

      String origEn, origTc, destEn, destTc;

      if (direction == 'O') {
        origEn = routeOrigEn;
        origTc = routeOrigTc;
        destEn = routeDestEn;
        destTc = routeDestTc;
      } else {
        origEn = routeDestEn;
        origTc = routeDestTc;
        destEn = routeOrigEn;
        destTc = routeOrigTc;
      }

      routeData[direction] = {
        'orig_en': origEn,
        'orig_tc': origTc,
        'dest_en': destEn,
        'dest_tc': destTc,
        'stops': stops
            .map((s) => {
                  'seq': s['seq'],
                  'stop': s['stop'],
                  'dir': s['dir'],
                  'co': s['co'],
                })
            .toList(),
      };
    }

    if (routeData.isNotEmpty) {
      optimizedRouteMap[route] = routeData;
    }
  }

  final routeStopsOutTmp = File('${outDir.path}/ctb_route_stops.json.tmp');
  routeStopsOutTmp.writeAsStringSync(json.encode(optimizedRouteMap));

  final routeStopsOut = File('${outDir.path}/ctb_route_stops.json');
  if (routeStopsOut.existsSync()) routeStopsOut.deleteSync();
  routeStopsOutTmp.renameSync(routeStopsOut.path);

  print('Wrote ${routeStopsOut.path} (${optimizedRouteMap.length} routes)');

  // Build combined stop -> routes mapping
  final Map<String, Map<String, dynamic>> stopRoutes = {};

  for (final route in routeMap.keys) {
    final directionData = routeMap[route]!;

    for (final direction in directionData.keys) {
      final stops = directionData[direction] as List<dynamic>;

      for (final e in stops) {
        try {
          final entry = Map<String, dynamic>.from(e as Map);
          final sid = (entry['stop'] ?? '').toString();
          if (sid.isEmpty) continue;

          final existing = stopRoutes.putIfAbsent(sid, () => {
            'stop': sid,
            'name_en': '',
            'name_tc': '',
            'routes': <String>[],
          });
          
          final stopMeta = stopsMap[sid];
          String nameEn = '';
          String nameTc = '';
          if (stopMeta != null) {
            nameEn = (stopMeta['name_en'] ?? stopMeta['nameen'] ?? '')?.toString() ?? '';
            nameTc = (stopMeta['name_tc'] ?? stopMeta['nametc'] ?? '')?.toString() ?? '';
          }

          nameEn = nameEn.isNotEmpty ? nameEn : ((entry['name_en'] ?? entry['nameen'])?.toString() ?? '');
          nameTc = nameTc.isNotEmpty ? nameTc : ((entry['name_tc'] ?? entry['nametc'])?.toString() ?? '');

          if ((existing['name_en'] as String).isEmpty && nameEn.isNotEmpty) {
            existing['name_en'] = nameEn;
          }

          if ((existing['name_tc'] as String).isEmpty && nameTc.isNotEmpty) {
            existing['name_tc'] = nameTc;
          }

          final routesList = existing['routes'] as List<dynamic>;
          if (!routesList.contains(route)) {
            routesList.add(route);
          }
        } catch (_) {}
      }
    }
  }

  final stopRoutesList = stopRoutes.values.toList();
  final stopRoutesOutTmp = File('${outDir.path}/ctb_stop_routes.json.tmp');
  stopRoutesOutTmp.writeAsStringSync(json.encode(stopRoutesList));

  final stopRoutesOut = File('${outDir.path}/ctb_stop_routes.json');
  if (stopRoutesOut.existsSync()) stopRoutesOut.deleteSync();
  stopRoutesOutTmp.renameSync(stopRoutesOut.path);

  print('Wrote ${stopRoutesOut.path} (${stopRoutesList.length} stops indexed)');
  print('prebuild_ctb: complete');
}