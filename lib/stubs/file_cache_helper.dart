import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> loadFromFileCache(String url, String filename, bool forceUpdate, Future<String> Function() downloader) async {
  final dir  = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');

  bool needsUpdate = forceUpdate || !file.existsSync();
  if (!needsUpdate) {
    final age = DateTime.now().difference(file.lastModifiedSync());
    if (age.inHours > 12) needsUpdate = true;
  }

  if (needsUpdate) {
    try {
      final content = await downloader();
      await file.writeAsString(content);
      return content;
    } catch (_) {
      if (file.existsSync()) return file.readAsString();
      return null;
    }
  }
  return file.readAsString();
}
