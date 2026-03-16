// Web stub — no file system
Future<String?> loadFromFileCache(String url, String filename, bool forceUpdate, Future<String> Function() downloader) async {
  return null; // Web 唔支持 file，直接返回 null
}
