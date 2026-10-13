import 'dart:convert';
import 'local_document.dart';

class AppPreferences {
  AppPreferences._();

  static Future<void> _pendingWrite = Future.value();

  static Future<void> _update(String key, Object value) {
    final write = _pendingWrite.then((_) async {
      final values = await _read();
      values[key] = value;
      final file = await _file();
      await file.writeAsString(jsonEncode(values), flush: true);
    });
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  static const _fileName = 'app_preferences.json';
  static const _showTrainingDataKey = 'show_training_data_actions';
  static const _scanDiagnosticsKey = 'scan_diagnostics_enabled';

  static Future<LocalDocument> _file() async {
    final directory = await getApplicationSupportDirectory();
    return LocalDocument('${directory.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<String> mahjongVariant() async {
    final values = await _read();
    return values['mahjong_variant'] == 'sanma' ? 'sanma' : 'yonma';
  }

  static Future<void> setMahjongVariant(String value) {
    if (value != 'sanma' && value != 'yonma') throw ArgumentError.value(value);
    return _update('mahjong_variant', value);
  }

  static Future<bool> showTrainingDataActions() async {
    final values = await _read();
    return values[_showTrainingDataKey] as bool? ?? false;
  }

  static Future<void> setShowTrainingDataActions(bool value) =>
      _update(_showTrainingDataKey, value);

  static Future<bool> scanDiagnosticsEnabled() async {
    final values = await _read();
    return values[_scanDiagnosticsKey] as bool? ?? false;
  }

  static Future<void> setScanDiagnosticsEnabled(bool value) =>
      _update(_scanDiagnosticsKey, value);
}
