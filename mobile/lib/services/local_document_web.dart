import 'package:web/web.dart' as web;

/// Logical namespace only. No browser filesystem access is required.
class Directory {
  const Directory(this.path);
  final String path;
}

Future<Directory> getApplicationSupportDirectory() async =>
    const Directory('tsumoai');

class LocalDocument {
  LocalDocument(String path) : _key = 'tsumoai.document.v1:$path';
  final String _key;
  Future<bool> exists() async => web.window.localStorage.getItem(_key) != null;
  Future<String> readAsString() async {
    final value = web.window.localStorage.getItem(_key);
    if (value == null) throw StateError('保存データが見つかりません');
    return value;
  }

  Future<void> writeAsString(String value, {bool flush = false}) async {
    // Quota/security errors must reach callers instead of silently losing data.
    web.window.localStorage.setItem(_key, value);
  }
}
