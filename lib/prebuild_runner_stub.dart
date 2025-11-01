/// Stub for platforms without `dart:io` (web).
Future<String> runPrebuildScript({String? startDir}) async {
  return 'Prebuild execution not supported on this platform.';
}
