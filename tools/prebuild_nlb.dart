// Prebuild script to fetch NLB (New Lantao Bus) route-stops and stops and write to assets/prebuilt
//
// Based on NLB Open API Documentation v2.0:
// - Base URL: https://rt.data.gov.hk/v2/transport/nlb/
// - Route List: route.php?action=list
// - Stops per Route: stop.php?action=list&routeId={routeId}

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  print('prebuild_nlb: starting');

  // Ensure we write to the project-root `assets/prebuilt` directory
  // Assuming script is in lib/scripts/ or similar, navigate up to root
  final scriptDir = File(Platform.script.toFilePath()).parent;
  // Adjust parent count based on where you place the script. 
  // Assuming depth: project_root/tool/prebuild_nlb.dart or project_root/prebuild_nlb.dart
  // Modify if necessary. Standardizing to project root assets.
  
  // Safe directory resolution: look for pubspec.yaml to find root
  Directory projectRoot = scriptDir;
  while (projectRoot.path != '/' && !File('${projectRoot.path}/pubspec.yaml').existsSync()) {
    projectRoot = projectRoot.parent;
  }
  
  final outDir = Directory('${projectRoot.path}/assets/prebuilt');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  const baseUrl = 'https://rt.data.gov.hk/v2/transport/nlb';

  // 1. Fetch All Routes
  // Endpoint: route.php?action=list [cite: 16, 17]
  final routeUrl = '$baseUrl/route.php?action=list';
  print('Fetching routes from $routeUrl...');

  final Map<String, List<Map<String, dynamic>>> routesByNo = {};
  // Map to store metadata per routeId
  final Map<String, Map<String, String>> routeIdMeta = {};

  try {
    final response = await http.get(Uri.parse(routeUrl)).timeout(const Duration(seconds: 30));
    
    if (response.statusCode != 200) {
      stderr.writeln('Failed to fetch routes: ${response.statusCode}');
      exit(1);
    }

    final jsonData = json.decode(response.body);
    final routes = jsonData['routes'] as List; // [cite: 17]

    print('Found ${routes.length} route entries.');

    for (final r in routes) {
      final routeId = r['routeId'].toString();
      final routeNo = r['routeNo'].toString();
      
      // Parse names to extract Origin/Dest
      // Format is typically "Origin > Dest" e.g., "Tai O > Mui Wo Ferry Pier" [cite: 24]
      final nameC = (r['routeName_c'] ?? '').toString();
      final nameE = (r['routeName_e'] ?? '').toString();
      
      final partsC = nameC.split('>');
      final partsE = nameE.split('>');
      
      String origTc = partsC.isNotEmpty ? partsC[0].trim() : nameC;
      String destTc = partsC.length > 1 ? partsC[1].trim() : '';
      String origEn = partsE.isNotEmpty ? partsE[0].trim() : nameE;
      String destEn = partsE.length > 1 ? partsE[1].trim() : '';

      // Store meta
      routeIdMeta[routeId] = {
        'routeNo': routeNo,
        'orig_en': origEn,
        'dest_en': destEn,
        'orig_tc': origTc,
        'dest_tc': destTc,
        'overnight': r['overnightRoute'].toString(),
        'special': r['specialRoute'].toString(),
      };

      // Group by routeNo for later processing
      routesByNo.putIfAbsent(routeNo, () => []).add({
        'routeId': routeId,
        ...routeIdMeta[routeId]!,
      });
    }
  } catch (e) {
    stderr.writeln('Error fetching routes: $e');
    exit(1);
  }

  // 2. Fetch Stops for Each RouteId
  // Endpoint: stop.php?action=list&routeId={routeId} [cite: 31, 32]
  print('Fetching stops for ${routeIdMeta.length} route variants...');

  // Global map of unique stops: stopId -> stop details
  final Map<String, Map<String, dynamic>> globalStopsMap = {};
  
  // Map of routeId -> List of stops
  final Map<String, List<Map<String, dynamic>>> routeIdToStops = {};

  final routeIds = routeIdMeta.keys.toList();
  
  // Batch processing
  const int batchSize = 20;
  int successCount = 0;
  int failCount = 0;

  for (int i = 0; i < routeIds.length; i += batchSize) {
    final batch = routeIds.skip(i).take(batchSize).toList();
    
    final futures = batch.map((routeId) async {
      final url = '$baseUrl/stop.php?action=list&routeId=$routeId';
      
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          final jsonBody = json.decode(response.body);
          final stops = jsonBody['stops'] as List?; // [cite: 32]
          
          if (stops != null) {
            final List<Map<String, dynamic>> processedStops = [];
            
            int seq = 1;
            for (final s in stops) {
              final stopId = s['stopId'].toString();
              
              // Add to global stops map (deduplicated by stopId)
              if (!globalStopsMap.containsKey(stopId)) {
                globalStopsMap[stopId] = {
                  'stop': stopId,
                  'name_en': s['stopName_e'], // [cite: 34]
                  'name_tc': s['stopName_c'],
                  'lat': s['latitude'],
                  'long': s['longitude'],
                  'location_en': s['stopLocation_e'],
                  'location_tc': s['stopLocation_c'],
                };
              }
              
              // Add to route stop list
              processedStops.add({
                'seq': seq.toString(),
                'stop': stopId,
                'fare': s['fare'],
                'fareHoliday': s['fareHoliday'],
              });
              seq++;
            }
            return MapEntry(routeId, processedStops);
          }
        }
      } catch (e) {
        stderr.writeln('Error fetching stops for routeId $routeId: $e');
      }
      return null;
    });

    final results = await Future.wait(futures);
    
    for (final entry in results) {
      if (entry != null) {
        routeIdToStops[entry.key] = entry.value;
        successCount++;
      } else {
        failCount++;
      }
    }
    
    print('Processed ${i + batch.length}/${routeIds.length} variants ($successCount ok, $failCount fail)');
  }

  // 3. Save Global Stops Map (nlb_stops.json)
  final stopsOut = File('${outDir.path}/nlb_stops.json');
  stopsOut.writeAsStringSync(json.encode(globalStopsMap));
  print('Wrote ${stopsOut.path} (${globalStopsMap.length} unique stops)');


  // 4. Build Optimized Route-Stops Map (nlb_route_stops.json)
  // Structure: { "RouteNo": { "RouteId": { "orig":..., "dest":..., "stops": [...] } } }
  // Unlike KMB/CTB which use 'O'/'I' (Direction), NLB uses specific RouteIds for variants.
  // We will preserve the RouteId structure so the app can iterate keys.
  
  final Map<String, dynamic> optimizedRouteMap = {};

  for (final routeNo in routesByNo.keys) {
    final variants = routesByNo[routeNo]!;
    final Map<String, dynamic> routeData = {};

    for (final v in variants) {
      final rId = v['routeId'];
      final stops = routeIdToStops[rId];
      
      if (stops != null && stops.isNotEmpty) {
        routeData[rId] = {
          'orig_en': v['orig_en'],
          'dest_en': v['dest_en'],
          'orig_tc': v['orig_tc'],
          'dest_tc': v['dest_tc'],
          'service_type': v['special'] == '1' ? 'Special' : 'Normal', // [cite: 17]
          'stops': stops
        };
      }
    }
    
    if (routeData.isNotEmpty) {
      optimizedRouteMap[routeNo] = routeData;
    }
  }

  final routeStopsOut = File('${outDir.path}/nlb_route_stops.json');
  routeStopsOut.writeAsStringSync(json.encode(optimizedRouteMap));
  print('Wrote ${routeStopsOut.path} (${optimizedRouteMap.length} routes)');


  // 5. Build Stop -> Routes Index (nlb_stop_routes.json)
  // Useful for looking up which routes serve a specific stop
  final Map<String, Map<String, dynamic>> stopRoutesIndex = {};

  // Initialize from global stops to ensure we have names
  for (final stopId in globalStopsMap.keys) {
    stopRoutesIndex[stopId] = {
      'stop': stopId,
      'name_en': globalStopsMap[stopId]!['name_en'],
      'name_tc': globalStopsMap[stopId]!['name_tc'],
      'routes': <String>[],
    };
  }

  // Populate routes list
  for (final routeNo in optimizedRouteMap.keys) {
    final variants = optimizedRouteMap[routeNo] as Map<String, dynamic>;
    
    for (final rId in variants.keys) {
      final variantData = variants[rId] as Map<String, dynamic>;
      final stops = variantData['stops'] as List<dynamic>;
      
      for (final s in stops) {
        final stopId = s['stop'].toString();
        if (stopRoutesIndex.containsKey(stopId)) {
          final routeList = stopRoutesIndex[stopId]!['routes'] as List<String>;
          if (!routeList.contains(routeNo)) {
            routeList.add(routeNo);
          }
        }
      }
    }
  }

  final stopRoutesList = stopRoutesIndex.values.toList();
  final stopRoutesOut = File('${outDir.path}/nlb_stop_routes.json');
  stopRoutesOut.writeAsStringSync(json.encode(stopRoutesList));
  print('Wrote ${stopRoutesOut.path} (${stopRoutesList.length} stops indexed)');

  print('prebuild_nlb: complete');
}