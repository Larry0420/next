import 'dart:convert';
import 'dart:io';

/// Runs tools/prebuild_kmb.dart by locating the project root (looking for
/// pubspec.yaml) and invoking `dart` with the script. Returns combined
/// stdout/stderr and the exit code appended.
Future<String> runPrebuildScript({String? startDir}) async {
  // Find project root by walking up directories looking for pubspec.yaml
  Directory dir = Directory(startDir ?? Directory.current.path);
  for (int i = 0; i < 12; i++) {
    final pub = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (pub.existsSync()) break;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  final projectRoot = dir;
  final scriptPath = '${projectRoot.path}${Platform.pathSeparator}tools${Platform.pathSeparator}prebuild_kmb.dart';
  final scriptFile = File(scriptPath);
  if (!scriptFile.existsSync()) {
    return 'prebuild script not found at: $scriptPath';
  }

  final sb = StringBuffer();
  try {
    final proc = await Process.start('dart', [scriptFile.path], workingDirectory: projectRoot.path);
    // collect stdout/stderr
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      sb.writeln(l);
    });
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      sb.writeln('ERR: $l');
    });
    final code = await proc.exitCode;
    sb.writeln('\nProcess exited with code $code');
  } catch (e, st) {
    sb.writeln('Failed to run prebuild: $e\n$st');
  }
  return sb.toString();
}
