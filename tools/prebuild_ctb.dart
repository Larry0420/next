// Prebuild script to fetch CTB route-stops and stops and write to assets/prebuilt
//
// Based on CTB API Specifications v2.01 (July 2023):
// - Base URL: https://rt.data.gov.hk/v2/transport/citybus
// - Routes list: route/{company_id}
// - Route-stops: route-stop/{company_id}/{route}/{direction}
// - Stops: stop/{stop_id}
// - Company: CTB
//
// Outputs (filenames MUST NOT change):
// - assets/prebuilt/ctb_stops.json
// - assets/prebuilt/ctb_stop_routes.json
// - assets/prebuilt/ctb_route_stops.json
//
// Key rule implemented:
// - ctb_route_stops.json is strictly regulated by ctb_stop_routes.json structure built in-memory:
//   If stopRoutes[stopId].routes is missing/empty OR does not contain the route, remove that stop
//   from the route's stops list, and resequence seq to 1..N.

import 'dart:convert';
import 'dart:io';

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

  // ---------------------------------------------------------
  // 1. Fetch route list (for origins/destinations metadata)
  // ---------------------------------------------------------
  final routeUrls = <String>['$baseUrl/route/$companyId'];

  final Map<String, Map<String, String>> routeInfo = {};
  var routeInfoOk = false;

  for (final u in routeUrls) {
    try {
      final response =
          await http.get(Uri.parse(u)).timeout(const Duration(seconds: 30));
      print('GET $u -> ${response.statusCode}');
      if (response.statusCode != 200) continue;

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final data = (jsonData['data'] as List?) ?? const [];
      for (final item in data) {
        final m = Map<String, dynamic>.from(item as Map);
        final route = (m['route'] ?? '').toString().toUpperCase().trim();
        if (route.isEmpty) continue;

        final origEn = (m['orig_en'] ?? m['origen'] ?? '').toString();
        final origTc = (m['orig_tc'] ?? m['origtc'] ?? '').toString();
        final destEn = (m['dest_en'] ?? m['desten'] ?? '').toString();
        final destTc = (m['dest_tc'] ?? m['desttc'] ?? '').toString();

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
  // 2. Fetch Route-Stops (discovery phase)
  //    We fetch this FIRST to discover all valid Stop IDs
  // ---------------------------------------------------------
  print('Fetching route-stops for ${routeInfo.length} routes...');

  // routeMap: route -> direction('I'/'O') -> list of entries (maps from API)
  final Map<String, Map<String, List<Map<String, dynamic>>>> routeMap = {};
  final Set<String> discoveredStopIds = {};

  const int routeBatchSize = 30;

  // Build list of all route/direction combinations
  final List<({String route, String direction})> routeDirections = [];
  for (final route in routeInfo.keys) {
    for (final direction in const ['inbound', 'outbound']) {
      routeDirections.add((route: route, direction: direction));
    }
  }
  print('Total ${routeDirections.length} route-directions to fetch');

  int routeSuccessCount = 0;
  int routeSkipCount = 0;

  // Hardcoded blacklist for known dirty data (Route 969 issues)
  const badStopsFor969 = <String>{
    '001476', // Cross Harbour Tunnel
    '002570', // Elizabeth House
    '002417', // Gloucester Rd
    '002421', // Fenwick St
    '001074', // Admiralty Centre
    '001181', // Queen Victoria St
    '001037', // Rumsey St
    '001027', // Central (Macao Ferry)
  };

  for (int i = 0; i < routeDirections.length; i += routeBatchSize) {
    final batch = routeDirections.skip(i).take(routeBatchSize).toList();

    final futures = batch.map((rd) async {
      final routeStopsUrl =
          '$baseUrl/route-stop/$companyId/${rd.route}/${rd.direction}';

      try {
        final response = await http
            .get(Uri.parse(routeStopsUrl))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          final data = (jsonData['data'] as List?) ?? const [];
          if (data.isEmpty) return null;

          final normalizedDir = rd.direction == 'inbound' ? 'I' : 'O';
          final List<Map<String, dynamic>> routeStops = [];

          for (final item in data) {
            try {
              final entry = Map<String, dynamic>.from(item as Map);

              final r = (entry['route'] ?? '').toString().toUpperCase().trim();
              final dir = (entry['dir'] ?? '').toString().toUpperCase().trim();
              final stopId = (entry['stop'] ?? '').toString().trim();

              if (r != rd.route || dir != normalizedDir) continue;
              if (stopId.isEmpty) continue;

              // Sanitizer (known dirty data)
              if (r == '969' && badStopsFor969.contains(stopId)) {
                continue;
              }

              discoveredStopIds.add(stopId);
              routeStops.add(entry);
            } catch (e) {
              stderr.writeln('Parse error in ${rd.route}/${rd.direction}: $e');
            }
          }

          if (routeStops.isNotEmpty) {
            return (
              route: rd.route,
              direction: normalizedDir,
              stops: routeStops,
            );
          }

          return null;
        }

        if (response.statusCode == 422 || response.statusCode == 404) {
          return null;
        }

        stderr.writeln('Failed $routeStopsUrl: ${response.statusCode}');
        return null;
      } catch (e) {
        stderr.writeln('Error fetching ${rd.route}/${rd.direction}: $e');
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);

    for (final result in results) {
      if (result != null) {
        final r = result.route;
        final d = result.direction;
        routeMap.putIfAbsent(r, () => {});
        routeMap[r]!.putIfAbsent(d, () => []);
        routeMap[r]![d]!.addAll(result.stops);
        routeSuccessCount++;
      } else {
        routeSkipCount++;
      }
    }

    print('Processed ${i + batch.length}/${routeDirections.length} '
        'route-directions ($routeSuccessCount successful, $routeSkipCount skipped)');
  }

  if (routeMap.isEmpty) {
    stderr.writeln('Failed to fetch any route-stops');
    exit(1);
  }

  // ---------------------------------------------------------
  // 3. Fetch details for discovered stops (names/lat/long)
  // ---------------------------------------------------------
  final stopList = discoveredStopIds.toList();
  print('Fetching details for ${stopList.length} discovered unique stops...');

  final Map<String, Map<String, dynamic>> stopsMap = {};
  const int stopBatchSize = 50;

  int stopSuccessCount = 0;
  int stopFailCount = 0;

  for (int i = 0; i < stopList.length; i += stopBatchSize) {
    final batch = stopList.skip(i).take(stopBatchSize).toList();

    final futures = batch.map((String stopId) async {
      final url = '$baseUrl/stop/$stopId';
      try {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return null;

        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final stopData = jsonData['data'];
        if (stopData is Map) {
          return MapEntry(stopId, Map<String, dynamic>.from(stopData));
        }
        return null;
      } catch (e) {
        stderr.writeln('Error fetching $stopId: $e');
        return null;
      }
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

  // Write stops map (ctb_stops.json)
  final stopsOutTmp = File('${outDir.path}/ctb_stops.json.tmp');
  stopsOutTmp.writeAsStringSync(json.encode(stopsMap));
  final stopsOut = File('${outDir.path}/ctb_stops.json');
  if (stopsOut.existsSync()) stopsOut.deleteSync();
  stopsOutTmp.renameSync(stopsOut.path);
  print('Wrote ${stopsOut.path} (${stopsMap.length} stops)');

  // ---------------------------------------------------------
  // 4. Build and write output files (strict regulation)
  // ---------------------------------------------------------

  // STEP A: Build stop -> routes mapping FIRST (ctb_stop_routes.json)
  // This is the "regulator" for route-stops.
  final Map<String, Map<String, dynamic>> stopRoutes = {};

  for (final route in routeMap.keys) {
    final directionData = routeMap[route]!;
    for (final direction in directionData.keys) {
      final stops = directionData[direction]!;
      for (final e in stops) {
        try {
          final entry = Map<String, dynamic>.from(e);
          final sid = (entry['stop'] ?? '').toString().trim();
          if (sid.isEmpty) continue;

          final existing = stopRoutes.putIfAbsent(sid, () {
            return <String, dynamic>{
              'stop': sid,
              'name_en': '',
              'name_tc': '',
              'routes': <String>[],
            };
          });

          // Fill stop name from stopsMap if possible
          final stopMeta = stopsMap[sid];
          var nameEn = '';
          var nameTc = '';
          if (stopMeta != null) {
            nameEn = (stopMeta['name_en'] ?? stopMeta['nameen'] ?? '')
                .toString()
                .trim();
            nameTc = (stopMeta['name_tc'] ?? stopMeta['nametc'] ?? '')
                .toString()
                .trim();
          }

          if (nameEn.isEmpty) {
            nameEn = (entry['name_en'] ?? entry['nameen'] ?? '')
                .toString()
                .trim();
          }
          if (nameTc.isEmpty) {
            nameTc = (entry['name_tc'] ?? entry['nametc'] ?? '')
                .toString()
                .trim();
          }

          if ((existing['name_en'] as String).isEmpty && nameEn.isNotEmpty) {
            existing['name_en'] = nameEn;
          }
          if ((existing['name_tc'] as String).isEmpty && nameTc.isNotEmpty) {
            existing['name_tc'] = nameTc;
          }

          final routesList = (existing['routes'] as List<String>);
          if (!routesList.contains(route)) {
            routesList.add(route);
          }
        } catch (_) {
          // ignore
        }
      }
    }
  }

  // Optional: keep deterministic output (sort each stop's routes)
  for (final sid in stopRoutes.keys) {
    final routesList = (stopRoutes[sid]!['routes'] as List<String>);
    routesList.sort((a, b) => a.compareTo(b));
  }

  // =========================================================
  // DEVELOPER HOOK (REGULATOR):
  // Modify stopRoutes HERE if you need to force-remove relationships.
  //
  // Examples:
  // - Remove a single route from a stop:
  //   (stopRoutes['001476']?['routes'] as List<String>?)?.remove('969');
  //
  // - Clear all routes of a stop (then it will be removed from ALL route-stops):
  //   stopRoutes['001476']?['routes'] = <String>[];
  //
  // - Delete the stop entry entirely (treated as missing routes):
  //   stopRoutes.remove('001476');
  // =========================================================

  // -> Write ctb_stop_routes.json (list format)
  final stopRoutesList = stopRoutes.values.toList()
    ..sort((a, b) => (a['stop'] as String).compareTo(b['stop'] as String));

  final stopRoutesOutTmp = File('${outDir.path}/ctb_stop_routes.json.tmp');
  stopRoutesOutTmp.writeAsStringSync(json.encode(stopRoutesList));
  final stopRoutesOut = File('${outDir.path}/ctb_stop_routes.json');
  if (stopRoutesOut.existsSync()) stopRoutesOut.deleteSync();
  stopRoutesOutTmp.renameSync(stopRoutesOut.path);
  print('Wrote ${stopRoutesOut.path} (${stopRoutesList.length} stops indexed)');

  // STEP B: Build optimized route-stops mapping STRICTLY regulated by stopRoutes
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
      final stops = directionData[direction]!;
      if (stops.isEmpty) continue;

      String origEn, origTc, destEn, destTc;
      if (direction == 'O') {
        origEn = routeOrigEn;
        origTc = routeOrigTc;
        destEn = routeDestEn;
        destTc = routeDestTc;
      } else {
        // inbound: swap endpoints (keep same behavior as original script)
        origEn = routeDestEn;
        origTc = routeDestTc;
        destEn = routeOrigEn;
        destTc = routeOrigTc;
      }

      final List<Map<String, dynamic>> validStops = [];
      int seq = 1;

      for (final s in stops) {
        final stopId = (s['stop'] ?? '').toString().trim();
        if (stopId.isEmpty) continue;

        // STRICT REGULATION CHECK:
        // - stop entry must exist
        // - routes must exist and be non-empty
        // - routes must contain this route
        final sr = stopRoutes[stopId];
        final routesField = sr?['routes'];
        final allowedRoutes =
            (routesField is List) ? routesField.cast<String>() : <String>[];

        final isAllowed = allowedRoutes.contains(route);
        if (!isAllowed) {
          continue;
        }

        validStops.add({
          'seq': seq,
          'stop': stopId,
          'dir': (s['dir'] ?? direction).toString(),
          'co': (s['co'] ?? companyId).toString(),
        });
        seq++;
      }

      if (validStops.isNotEmpty) {
        routeData[direction] = {
          'orig_en': origEn,
          'orig_tc': origTc,
          'dest_en': destEn,
          'dest_tc': destTc,
          'stops': validStops,
        };
      }
    }

    if (routeData.isNotEmpty) {
      optimizedRouteMap[route] = routeData;
    }
  }

  // -> Write ctb_route_stops.json
  final routeStopsOutTmp = File('${outDir.path}/ctb_route_stops.json.tmp');
  routeStopsOutTmp.writeAsStringSync(json.encode(optimizedRouteMap));
  final routeStopsOut = File('${outDir.path}/ctb_route_stops.json');
  if (routeStopsOut.existsSync()) routeStopsOut.deleteSync();
  routeStopsOutTmp.renameSync(routeStopsOut.path);
  print('Wrote ${routeStopsOut.path} (${optimizedRouteMap.length} routes)');

  print('prebuild_ctb: complete');
}
