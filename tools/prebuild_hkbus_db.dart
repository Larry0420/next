// Prebuild script to fetch hkbus unified database JSON and write to assets/prebuilt
//
// This script fetches the unified route/stop database from the hkbus GitHub Pages
// and saves it as a prebuilt asset for web builds.
//
// Purpose:
// - Web builds can use this prebuilt asset instead of fetching from URL every time
// - Avoids localStorage 5MB limit issue
// - Provides offline support after first build
//
// Output:
// - assets/prebuilt/routeFareList.min.json
//
// Usage:
// dart run tools/prebuild_hkbus_db.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  print('prebuild_hkbus_db: starting');

  // Resolve project root using robust pubspec.yaml search method
  final scriptDir = File(Platform.script.toFilePath()).parent;
  Directory projectRoot = scriptDir;
  while (projectRoot.path != '/' &&
      !File('${projectRoot.path}/pubspec.yaml').existsSync()) {
    projectRoot = projectRoot.parent;
  }

  // Ensure output directory exists
  final outDir = Directory('${projectRoot.path}/assets/prebuilt');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  const dbUrl = 'https://hkbus.github.io/hk-bus-crawling/routeFareList.min.json';
  print('Fetching hkbus DB from $dbUrl...');

  try {
    final response = await http.get(Uri.parse(dbUrl)).timeout(
      const Duration(seconds: 30),
    );

    print('GET $dbUrl -> ${response.statusCode}');

    if (response.statusCode != 200) {
      stderr.writeln('Failed to fetch hkbus DB: ${response.statusCode}');
      exit(1);
    }

    final contentLength = response.body.length;
    final contentSizeKB = (contentLength / 1024).toStringAsFixed(2);
    print('Downloaded $contentSizeKB KB');

    // Validate JSON structure
    try {
      final jsonData = json.decode(response.body);
      if (jsonData is! Map) {
        stderr.writeln('Invalid JSON structure: expected Map');
        exit(1);
      }

      // Validate required fields
      if (!jsonData.containsKey('routeList')) {
        stderr.writeln('Invalid JSON: missing routeList');
        exit(1);
      }
      if (!jsonData.containsKey('stopList')) {
        stderr.writeln('Invalid JSON: missing stopList');
        exit(1);
      }
      if (!jsonData.containsKey('stopMap')) {
        stderr.writeln('Invalid JSON: missing stopMap');
        exit(1);
      }

      print('✅ JSON validation passed');
      print('   - routeList: ${(jsonData['routeList'] as Map).length} routes');
      print('   - stopList: ${(jsonData['stopList'] as Map).length} stops');
      print('   - stopMap: ${(jsonData['stopMap'] as Map).length} entries');
    } catch (e) {
      stderr.writeln('JSON validation failed: $e');
      exit(1);
    }

    // Atomic write pattern
    final outTmp = File('${outDir.path}/routeFareList.min.json.tmp');
    outTmp.writeAsStringSync(response.body);

    final out = File('${outDir.path}/routeFareList.min.json');
    if (out.existsSync()) {
      out.deleteSync();
    }
    outTmp.renameSync(out.path);

    print('✅ Wrote ${out.path} ($contentSizeKB KB)');
    print('prebuild_hkbus_db: complete');
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}