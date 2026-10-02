import 'package:flutter/material.dart';
import 'package:tsumoai_mobile/theme/app_theme.dart';

/// The app theme screens are captured with. Mirrors `TsumoAIApp`'s theme.
ThemeData screenshotTheme() => AppTheme.light();

/// Background behind result panels, as on the scan screen's results phase.
Color screenshotResultBackground() => screenshotTheme().scaffoldBackgroundColor;
