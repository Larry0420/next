// lib/stubs/path_provider_stub.dart
import 'dart:async';

class Directory {
  final String path;
  Directory(this.path);
}

// 給 web 用的 dummy 實作（實際上不會被呼叫，因為你在 kIsWeb 時不走 _loadFromFile）
Future<Directory> getApplicationDocumentsDirectory() async {
  // 回傳一個假的路徑，只要型別對就好
  return Directory('/'); 
}
