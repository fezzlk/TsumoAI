import 'package:flutter/foundation.dart';

void writeTrace(String message) {
  if (!kDebugMode) debugPrint(message);
}
