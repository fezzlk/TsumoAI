import 'dart:io';
export 'dart:io' show Directory;
export 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

/// JSON documents keep their existing native paths; web uses origin storage.
class LocalDocument {
  LocalDocument(String path) : _file = File(path);
  final File _file;
  Future<bool> exists() => _file.exists();
  Future<String> readAsString() => _file.readAsString();
  Future<void> writeAsString(String value, {bool flush = false}) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(value, flush: flush);
  }
}
