import 'package:flutter/foundation.dart';

enum Environment { production, local }

class AppConfig {
  static Environment _env = Environment.production;

  static const String _productionUrl = 'https://tsumoai.fezzlk.com';
  static const String _localUrl = 'http://localhost:8000';

  static String _customUrl = const String.fromEnvironment('API_BASE_URL');

  static Environment get environment => _env;

  static String get apiBaseUrl {
    if (_customUrl.isNotEmpty) return _customUrl;
    switch (_env) {
      case Environment.production:
        return kIsWeb ? Uri.base.origin : _productionUrl;
      case Environment.local:
        return _localUrl;
    }
  }

  static String get wsBaseUrl {
    final url = apiBaseUrl;
    if (url.startsWith('https://')) {
      return url.replaceFirst('https://', 'wss://');
    }
    return url.replaceFirst('http://', 'ws://');
  }

  static void setEnvironment(Environment env) {
    _env = env;
    _customUrl = '';
  }

  static void setApiBaseUrl(String url) {
    _customUrl = url.replaceAll(RegExp(r'/+$'), '');
  }
}
