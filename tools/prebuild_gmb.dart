// ignore_for_file: avoid_print
// Prebuild script to fetch GMB (Green Minibus) route-stops and stops and write to assets/prebuilt
//
// Based on GMB ETA API Specification v1.1:
// - Base URL: https://data.etagmb.gov.hk
// - Routes by region: /route
// - Route details: /route/{region}/{route_code}
// - Route stops: /route-stop/{route_id}/{route_seq}
//
// Outputs (filenames MUST NOT change):
// - assets/prebuilt/gmb_stops.json
// - assets/prebuilt/gmb_stop_routes.json
// - assets/prebuilt/gmb_route_stops.json

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  print('prebuild_gmb: starting');

  // Ensure we write to the project-root `assets/prebuilt` directory
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final projectRoot = scriptDir.parent;
  final outDir = Directory('${projectRoot.path}/assets/prebuilt');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  const baseUrl = 'https://data.etagmb.gov.hk';
  const regions = ['HKI', 'KLN', 'NT'];

  // ---------------------------------------------------------
  // 1. Fetch all routes by region
  // ---------------------------------------------------------
  print('Fetching GMB routes from all regions...');

  final Map<String, List<Map<String, dynamic>>> routesByRegion = {};
  final Map<String, Map<String, dynamic>> routeDetailsCache = {}; // routeId -> details

  for (final region in regions) {
    final url = '$baseUrl/route/$region';
    print('GET $url');

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        stderr.writeln('Failed to fetch routes for $region: ${response.statusCode}');
        continue;
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final data = jsonData['data'] as Map<String, dynamic>?;
      final routes = data?['routes'] as List<dynamic>?;

      if (routes == null) continue;

      final regionRoutes = <Map<String, dynamic>>[];

      for (final routeCode in routes) {
        final code = routeCode.toString();
        if (code.isEmpty) continue;

        // Fetch detailed route info to get route_id
        final detailUrl = '$baseUrl/route/$region/${Uri.encodeComponent(code)}';
        try {
          final detailResponse = await http.get(Uri.parse(detailUrl))
              .timeout(const Duration(seconds: 15));

          if (detailResponse.statusCode == 200) {
            final detailJson = json.decode(detailResponse.body) as Map<String, dynamic>;
            final detailData = detailJson['data'] as List<dynamic>?;

            if (detailData != null && detailData.isNotEmpty) {
              // Each route code may have multiple entries (different service types)
              for (final entry in detailData) {
                final routeId = entry['route_id'] as int?;
                if (routeId == null) continue;

                final directions = entry['directions'] as List<dynamic>? ?? [];

                for (final dir in directions) {
                  final routeSeq = dir['route_seq'] as int? ?? 1;

                  regionRoutes.add({
                    'route_code': code,
                    'route_id': routeId,
                    'route_seq': routeSeq,
                    'region': region,
                    'orig_tc': dir['orig_tc'] ?? '',
                    'orig_en': dir['orig_en'] ?? '',
                    'dest_tc': dir['dest_tc'] ?? '',
                    'dest_en': dir['dest_en'] ?? '',
                    'description_tc': entry['description_tc'] ?? '',
                    'description_en': entry['description_en'] ?? '',
                  });

                  // Cache route details for later use
                  routeDetailsCache['${routeId}_$routeSeq'] = {
                    'route_id': routeId,
                    'route_seq': routeSeq,
                    'region': region,
                    'orig_tc': dir['orig_tc'] ?? '',
                    'orig_en': dir['orig_en'] ?? '',
                    'dest_tc': dir['dest_tc'] ?? '',
                    'dest_en': dir['dest_en'] ?? '',
                  };
                }
              }
            }
          }
        } catch (e) {
          stderr.writeln('Error fetching route details for $region/$code: $e');
        }
      }

      routesByRegion[region] = regionRoutes;
      print('Region $region: ${regionRoutes.length} route variants');
    } catch (e) {
      stderr.writeln('Error fetching routes for $region: $e');
    }
  }

  final totalRoutes = routesByRegion.values.fold<int>(0, (sum, list) => sum + list.length);
  print('Total route variants fetched: $totalRoutes');

  if (totalRoutes == 0) {
    stderr.writeln('Failed to fetch any route data');
    exit(1);
  }

  // ---------------------------------------------------------
  // 2. Fetch stops for each route variant
  // ---------------------------------------------------------
  print('Fetching stops for route variants...');

  final Map<String, Map<String, dynamic>> globalStopsMap = {};
  final Map<String, Map<String, dynamic>> routeToStops = {};

  // Collect all route variants to fetch
  final List<Map<String, dynamic>> allVariants = [];
  for (final entry in routesByRegion.entries) {
    for (final route in entry.value) {
      allVariants.add(route);
    }
  }

  const int batchSize = 10;
  int successCount = 0;
  int failCount = 0;

  for (int i = 0; i < allVariants.length; i += batchSize) {
    final batch = allVariants.skip(i).take(batchSize).toList();

    final futures = batch.map((variant) async {
      final routeId = variant['route_id'] as int;
      final routeSeq = variant['route_seq'] as int;
      final routeCode = variant['route_code'] as String;

      final url = '$baseUrl/route-stop/$routeId/$routeSeq';

      try {
        final response = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final jsonBody = json.decode(response.body) as Map<String, dynamic>;
          final data = jsonBody['data'] as Map<String, dynamic>?;
          final routeStops = data?['route_stops'] as List<dynamic>?;

          if (routeStops != null) {
            final List<Map<String, dynamic>> processedStops = [];

            for (final s in routeStops) {
              final stopId = s['stop_id'] as int?;
              if (stopId == null) continue;

              final stopNameTc = s['name_tc']?.toString() ?? '';
              final stopNameEn = s['name_en']?.toString() ?? '';

              // Add to global stops map
              if (!globalStopsMap.containsKey(stopId.toString())) {
                globalStopsMap[stopId.toString()] = {
                  'stop_id': stopId,
                  'name_tc': stopNameTc,
                  'name_en': stopNameEn,
                  'lat': s['lat'] ?? s['latitude'],
                  'long': s['long'] ?? s['longitude'] ?? s['lng'],
                };
              }

              processedStops.add({
                'stop_seq': s['stop_seq'] ?? processedStops.length + 1,
                'stop_id': stopId,
                'name_tc': stopNameTc,
                'name_en': stopNameEn,
              });
            }

            return MapEntry('${routeId}_$routeSeq', {
              'route_id': routeId,
              'route_seq': routeSeq,
              'route_code': routeCode,
              'region': variant['region'],
              'orig_tc': variant['orig_tc'],
              'orig_en': variant['orig_en'],
              'dest_tc': variant['dest_tc'],
              'dest_en': variant['dest_en'],
              'stops': processedStops,
            });
          }
        }
      } catch (e) {
        stderr.writeln('Error fetching stops for route $routeId/$routeSeq: $e');
      }
      return null;
    }).toList();

    final results = await Future.wait(futures);

    for (final result in results) {
      if (result != null) {
        routeToStops[result.key] = result.value;
        successCount++;
      } else {
        failCount++;
      }
    }

    print('Processed ${i + batch.length}/${allVariants.length} variants '
        '($successCount ok, $failCount fail)');
  }

  // ---------------------------------------------------------
  // 3. Build output files
  // ---------------------------------------------------------

  // STEP A: Build gmb_stops.json (stop_id -> stop details)
  final stopsOutTmp = File('${outDir.path}/gmb_stops.json.tmp');
  stopsOutTmp.writeAsStringSync(json.encode(globalStopsMap));
  final stopsOut = File('${outDir.path}/gmb_stops.json');
  if (stopsOut.existsSync()) stopsOut.deleteSync();
  stopsOutTmp.renameSync(stopsOut.path);
  print('Wrote ${stopsOut.path} (${globalStopsMap.length} unique stops)');

  // STEP B: Build gmb_route_stops.json
  // Structure: { "routeNo": { "variants": [...] } }
  // Group by route_code, then list all variants
  final Map<String, dynamic> routeStopsMap = {};

  for (final entry in routeToStops.entries) {
    final data = entry.value;
    final routeCode = data['route_code'] as String;
    final routeId = data['route_id'] as int;
    final routeSeq = data['route_seq'] as int;

    if (!routeStopsMap.containsKey(routeCode)) {
      routeStopsMap[routeCode] = {
        'variants': <Map<String, dynamic>>[],
      };
    }

    (routeStopsMap[routeCode]!['variants'] as List).add({
      'routeId': routeId,
      'routeSeq': routeSeq,
      'region': data['region']?.toString() ?? '',
      'orig_tc': data['orig_tc']?.toString() ?? '',
      'orig_en': data['orig_en']?.toString() ?? '',
      'dest_tc': data['dest_tc']?.toString() ?? '',
      'dest_en': data['dest_en']?.toString() ?? '',
      'stops': data['stops'],
    });
  }

  // Sort variants within each route by routeSeq, then routeId
  for (final routeCode in routeStopsMap.keys) {
    final routeData = routeStopsMap[routeCode] as Map<String, dynamic>;
    final variants = (routeData['variants'] as List).cast<Map<String, dynamic>>();
    variants.sort((a, b) {
      final seqA = a['routeSeq'] as int;
      final seqB = b['routeSeq'] as int;
      if (seqA != seqB) return seqA.compareTo(seqB);
      final idA = a['routeId'] as int;
      final idB = b['routeId'] as int;
      return idA.compareTo(idB);
    });
  }

  final routeStopsOutTmp = File('${outDir.path}/gmb_route_stops.json.tmp');
  routeStopsOutTmp.writeAsStringSync(json.encode(routeStopsMap));
  final routeStopsOut = File('${outDir.path}/gmb_route_stops.json');
  if (routeStopsOut.existsSync()) routeStopsOut.deleteSync();
  routeStopsOutTmp.renameSync(routeStopsOut.path);
  print('Wrote ${routeStopsOut.path} (${routeStopsMap.length} routes)');

  // STEP C: Build gmb_stop_routes.json (for nearby stops lookup)
  // Structure: [{ "stop_id": "123", "name_en": "...", "name_tc": "...", "routes": ["69", ...] }]
  final Map<String, Map<String, dynamic>> stopRoutesIndex = {};

  // Initialize from global stops
  for (final entry in globalStopsMap.entries) {
    final stopId = entry.key;
    final stopData = entry.value;
    stopRoutesIndex[stopId] = {
      'stop_id': stopId,
      'name_en': stopData['name_en']?.toString() ?? '',
      'name_tc': stopData['name_tc']?.toString() ?? '',
      'routes': <String>[],
    };
  }

  // Populate routes list
  for (final entry in routeToStops.entries) {
    final data = entry.value;
    final routeCode = data['route_code'] as String;
    final stops = data['stops'] as List<dynamic>;

    for (final s in stops) {
      final stopId = s['stop_id'].toString();
      if (stopRoutesIndex.containsKey(stopId)) {
        final routeList = stopRoutesIndex[stopId]!['routes'] as List<String>;
        if (!routeList.contains(routeCode)) {
          routeList.add(routeCode);
        }
      }
    }
  }

  // Sort routes in each stop
  for (final stopId in stopRoutesIndex.keys) {
    final routeList = stopRoutesIndex[stopId]!['routes'] as List<String>;
    routeList.sort((a, b) => a.compareTo(b));
  }

  final stopRoutesList = stopRoutesIndex.values.toList()
    ..sort((a, b) => (a['stop_id'].toString()).compareTo(b['stop_id'].toString()));

  final stopRoutesOutTmp = File('${outDir.path}/gmb_stop_routes.json.tmp');
  stopRoutesOutTmp.writeAsStringSync(json.encode(stopRoutesList));
  final stopRoutesOut = File('${outDir.path}/gmb_stop_routes.json');
  if (stopRoutesOut.existsSync()) stopRoutesOut.deleteSync();
  stopRoutesOutTmp.renameSync(stopRoutesOut.path);
  print('Wrote ${stopRoutesOut.path} (${stopRoutesList.length} stops indexed)');

  print('prebuild_gmb: complete');
}
