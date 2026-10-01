import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class AppPreferences {
  AppPreferences._();

  static const _fileName = 'app_preferences.json';
  static const _showTrainingDataKey = 'show_training_data_actions';
  static const _installationIdKey = 'installation_id';

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

  static Future<String> installationId() async {
    final values = await _read();
    final existing = values[_installationIdKey];
    if (existing is String && existing.length >= 16) return existing;
    final random = Random.secure();
    final generated = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    values[_installationIdKey] = generated;
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values), flush: true);
    return generated;
  }
}
