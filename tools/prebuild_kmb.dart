// Prebuild script to fetch KMB route-stops and stops and write to assets/prebuilt
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  print('prebuild_kmb: starting');
  final outDir = Directory('assets/prebuilt');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  // stream-parse route-stops using json_stream (efficient streaming of large arrays)
  final routeStopsUrls = [
    'https://data.etabus.gov.hk/v1/transport/kmb/route-stop',
    'https://data.etabus.gov.hk/v1/transport/kmb/route/route-stop',
  ];
  Map<String, List<Map<String, dynamic>>> routeMap = {};
  bool routeOk = false;
  for (final u in routeStopsUrls) {
    try {
      final req = http.Request('GET', Uri.parse(u));
      // ensure the request can't hang indefinitely
      final streamed = await req.send().timeout(Duration(seconds: 30));
      print('GET $u -> ${streamed.statusCode}');
      if (streamed.statusCode != 200) continue;
      final contentLength = streamed.headers['content-length'];
      if (contentLength != null) print('Content-Length: $contentLength');

  // Stream-parse top-level "data" array without loading the whole body.
  await for (final item in _streamArrayElements(streamed.stream, 'data')) {
        try {
          final entry = Map<String, dynamic>.from(item as Map);
          final route = (entry['route'] ?? '').toString().toUpperCase();
          routeMap.putIfAbsent(route, () => []).add(entry);
        } catch (_) {}
      }
      routeOk = routeMap.isNotEmpty;
      if (routeOk) break;
    } catch (e) {
      stderr.writeln('failed $u: $e');
    }
  }

  if (!routeOk) {
    stderr.writeln('Failed to fetch route-stops');
    exit(1);
  }

  // write atomically
  final routeStopsOutTmp = File('${outDir.path}/kmb_route_stops.json.tmp');
  routeStopsOutTmp.writeAsStringSync(json.encode(routeMap));
  final routeStopsOut = File('${outDir.path}/kmb_route_stops.json');
  if (routeStopsOut.existsSync()) routeStopsOut.deleteSync();
  routeStopsOutTmp.renameSync(routeStopsOut.path);
  print('Wrote ${routeStopsOut.path} (${routeMap.length} routes)');

  // stream-parse stops list using json_stream
  final stopsUrls = [
    'https://data.etabus.gov.hk/v1/transport/kmb/stop',
    'https://data.etabus.gov.hk/v1/transport/kmb/stop/',
  ];
  Map<String, Map<String, dynamic>> stopsMap = {};
  bool stopsOk = false;
  for (final u in stopsUrls) {
    try {
      final req = http.Request('GET', Uri.parse(u));
      final streamed = await req.send().timeout(Duration(seconds: 30));
      print('GET $u -> ${streamed.statusCode}');
      if (streamed.statusCode != 200) continue;
      final contentLength = streamed.headers['content-length'];
      if (contentLength != null) print('Content-Length: $contentLength');

      await for (final item in _streamArrayElements(streamed.stream, 'data')) {
        try {
          final s = Map<String, dynamic>.from(item as Map);
          final id = s['stop']?.toString() ?? '';
          if (id.isEmpty) continue;
          stopsMap[id] = s;
        } catch (_) {}
      }
      stopsOk = stopsMap.isNotEmpty;
      if (stopsOk) break;
    } catch (e) {
      stderr.writeln('failed $u: $e');
    }
  }

  if (!stopsOk) {
    stderr.writeln('Failed to fetch stops');
    exit(1);
  }

  final stopsOutTmp = File('${outDir.path}/kmb_stops.json.tmp');
  stopsOutTmp.writeAsStringSync(json.encode(stopsMap));
  final stopsOut = File('${outDir.path}/kmb_stops.json');
  if (stopsOut.existsSync()) stopsOut.deleteSync();
  stopsOutTmp.renameSync(stopsOut.path);
  print('Wrote ${stopsOut.path} (${stopsMap.length} stops)');

  // Build combined stop -> routes mapping with localized names
  // Structure: list of objects { stop, name_en, name_tc, routes: [route,...] }
  final Map<String, Map<String, dynamic>> stopRoutes = {};
  for (final route in routeMap.keys) {
    final entries = routeMap[route]!;
    for (final e in entries) {
      try {
        final sid = (e['stop'] ?? '').toString();
        if (sid.isEmpty) continue;
        final existing = stopRoutes.putIfAbsent(sid, () => {
          'stop': sid,
          'name_en': '',
          'name_tc': '',
          'routes': <String>[],
        });
        // get names from stopsMap preferentially, then route entry
        final stopMeta = stopsMap[sid];
        String nameEn = '';
        String nameTc = '';
        if (stopMeta != null) {
          nameEn = (stopMeta['name_en'] ?? stopMeta['nameen'] ?? stopMeta['nameen_us'] ?? '')?.toString() ?? '';
          nameTc = (stopMeta['name_tc'] ?? stopMeta['nametc'] ?? stopMeta['name_tc_tw'] ?? '')?.toString() ?? '';
        }
        // fallback to route entry fields
        nameEn = nameEn.isNotEmpty ? nameEn : ((e['nameen'] ?? e['name_en'])?.toString() ?? '');
        nameTc = nameTc.isNotEmpty ? nameTc : ((e['nametc'] ?? e['name_tc'])?.toString() ?? '');

        if ((existing['name_en'] as String).isEmpty && nameEn.isNotEmpty) existing['name_en'] = nameEn;
        if ((existing['name_tc'] as String).isEmpty && nameTc.isNotEmpty) existing['name_tc'] = nameTc;

        final routesList = existing['routes'] as List;
        if (!routesList.contains(route)) routesList.add(route);
      } catch (_) {}
    }
  }

  // Write stopRoutes as an array for simplicity
  final stopRoutesList = stopRoutes.values.toList();
  final stopRoutesOutTmp = File('${outDir.path}/kmb_stop_routes.json.tmp');
  stopRoutesOutTmp.writeAsStringSync(json.encode(stopRoutesList));
  final stopRoutesOut = File('${outDir.path}/kmb_stop_routes.json');
  if (stopRoutesOut.existsSync()) stopRoutesOut.deleteSync();
  stopRoutesOutTmp.renameSync(stopRoutesOut.path);
  print('Wrote ${stopRoutesOut.path} (${stopRoutesList.length} stops with routes)');

  print('Prebuild complete');
}

// Streams decoded JSON elements from a top-level array with the given key.
// This is a conservative, streaming approach that searches for the key name
// and then emits each complete JSON value inside the array as a decoded Dart
// object. It does not attempt to be a full JSON tokenizer — it balances
// braces/brackets and handles strings/escapes so objects/arrays may be
// extracted without holding the entire response in memory.
Stream<dynamic> _streamArrayElements(Stream<List<int>> byteStream, String key) async* {
  final decoder = utf8.decoder.bind(byteStream);
  final buffer = StringBuffer();
  var foundKey = false;
  var inArray = false;
  bool verbose = true; // set true for more logging

  await for (final chunk in decoder) {
    buffer.write(chunk);
    final sAll = buffer.toString();

    if (!foundKey) {
      // look for pattern "key"\s*:\s*[
      final reg = RegExp('"' + RegExp.escape(key) + '"\\s*:\\s*\\[', dotAll: true);
      final m = reg.firstMatch(sAll);
      if (m == null) {
        // keep a sliding window to avoid unbounded buffer
        if (sAll.length > 64 * 1024) {
          final tail = sAll.substring(sAll.length - 64 * 1024);
          buffer.clear();
          buffer.write(tail);
        }
        continue; // wait for more data
      }
      // Found the key and the opening '['; keep remainder after '['
      final after = sAll.substring(m.end);
      buffer.clear();
      buffer.write(after);
      foundKey = true;
      inArray = true;
      if (verbose) print('Found key "$key" and array start');
    }

    if (!inArray) continue;

    // Extract elements from the array
    while (true) {
      final s = buffer.toString();
      if (s.isEmpty) break;
      var pos = 0;
      // skip whitespace and commas
      while (pos < s.length && (s.codeUnitAt(pos) == 32 || s.codeUnitAt(pos) == 10 || s.codeUnitAt(pos) == 13 || s.codeUnitAt(pos) == 9 || s[pos] == ',')) pos++;
      if (pos >= s.length) {
        // nothing left yet
        break;
      }
      if (s[pos] == ']') {
        // end of array
        return;
      }

      // Determine element type
      if (s[pos] == '{' || s[pos] == '[') {
        // balanced object/array
        var i = pos;
        var depth = 0;
        var inString = false;
        var escape = false;
        for (; i < s.length; i++) {
          final ch = s[i];
          if (inString) {
            if (escape) {
              escape = false;
            } else if (ch == '\\') {
              escape = true;
            } else if (ch == '"') {
              inString = false;
            }
            continue;
          }
          if (ch == '"') {
            inString = true;
            continue;
          }
          if (ch == '{' || ch == '[') {
            depth++;
          } else if (ch == '}' || ch == ']') {
            depth--;
            if (depth == 0) {
              // i is at the closing brace
              final piece = s.substring(pos, i + 1);
              try {
                yield json.decode(piece);
              } catch (e) {
                if (verbose) stderr.writeln('element decode error: $e');
              }
              // remove consumed part
              final rest = s.substring(i + 1);
              buffer.clear();
              buffer.write(rest);
              // continue outer while to find next element
              break;
            }
          }
        }
        // if we didn't close the element yet, need more data
        if (depth != 0) break;
      } else if (s[pos] == '"') {
        // string primitive
        var i = pos + 1;
        var escape = false;
        for (; i < s.length; i++) {
          final ch = s[i];
          if (escape) {
            escape = false;
            continue;
          }
          if (ch == '\\') {
            escape = true;
            continue;
          }
          if (ch == '"') {
            // end of string
            final piece = s.substring(pos, i + 1);
            try {
              yield json.decode(piece);
            } catch (e) {
              if (verbose) stderr.writeln('string decode error: $e');
            }
            final rest = s.substring(i + 1);
            buffer.clear();
            buffer.write(rest);
            break;
          }
        }
        // need more data to close string
        break;
      } else {
        // number, true, false, null — find comma or closing bracket
        final commaIdx = s.indexOf(',');
        final endIdx = s.indexOf(']');
        int emitEnd = -1;
        if (endIdx != -1 && (commaIdx == -1 || endIdx < commaIdx)) {
          emitEnd = endIdx;
        } else if (commaIdx != -1) {
          emitEnd = commaIdx;
        }
        if (emitEnd == -1) break; // need more data
        final piece = s.substring(0, emitEnd).trim();
        if (piece.isNotEmpty) {
          try {
            yield json.decode(piece);
          } catch (e) {
            if (verbose) stderr.writeln('primitive decode error: $e');
          }
        }
        final rest = s.substring(emitEnd + 1);
        buffer.clear();
        buffer.write(rest);
        // continue to find next element
        continue;
      }
    }
  }
}
