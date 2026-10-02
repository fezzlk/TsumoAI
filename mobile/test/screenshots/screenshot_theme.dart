import 'package:flutter/material.dart';
import 'package:tsumoai_mobile/theme/app_theme.dart';

/// The app theme screens are captured with. Mirrors `TsumoAIApp`'s theme.
ThemeData screenshotTheme() => AppTheme.light();

/// Background behind result panels, as on the scan screen's results phase.
// The scan screen still draws its results on black until its styles move to
// the theme tokens.
Color screenshotResultBackground() => Colors.black;
