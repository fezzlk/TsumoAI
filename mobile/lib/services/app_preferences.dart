import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppPreferences {
  AppPreferences._();

  static const _fileName = 'app_preferences.json';
  static const _showTrainingDataKey = 'show_training_data_actions';

  static Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
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

  static Future<bool> showTrainingDataActions() async {
    final values = await _read();
    return values[_showTrainingDataKey] as bool? ?? false;
  }

  static Future<void> setShowTrainingDataActions(bool value) async {
    final values = await _read();
    values[_showTrainingDataKey] = value;
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values), flush: true);
  }
}
