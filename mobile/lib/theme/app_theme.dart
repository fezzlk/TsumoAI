import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Corner radii: tile images, chips/inputs, cards/buttons, dialogs/sheets.
abstract final class AppRadius {
  static const small = 4.0;
  static const medium = 8.0;
  static const large = 12.0;
  static const xLarge = 16.0;
}

/// Spacing scale; use these instead of arbitrary paddings.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
}

abstract final class AppTheme {
  static const _seed = Color(0xFF1B7F4B);
  static const _background = Color(0xFFF5F7F5);

  /// The app theme: light, with green for primary actions.
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: _seed).copyWith(
      primary: _seed,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF1A1C1A),
      onSurfaceVariant: const Color(0xFF4A524C),
      outline: const Color(0xFF8A938C),
      outlineVariant: const Color(0xFFDDE3DE),
      error: AppColors.light.error.color,
      errorContainer: AppColors.light.error.container,
      onErrorContainer: AppColors.light.error.onContainer,
    );
    return _build(scheme, background: _background);
  }

  /// Dark theme for camera and photo-editing screens only.
  static ThemeData camera() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(surface: AppColors.light.cameraBackground);
    return _build(scheme, background: AppColors.light.cameraBackground);
  }

  static ThemeData _build(ColorScheme scheme, {required Color background}) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme;
    final textTheme = text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      bodySmall: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.large)),
    );
    const buttonSize = Size(48, 48);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      extensions: const [AppColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          elevation: 0,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xLarge),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xLarge),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    );
  }
}

/// Style for buttons that delete, discard or end something.
ButtonStyle destructiveButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: scheme.error,
    foregroundColor: scheme.onError,
  );
}

/// Outlined variant of [destructiveButtonStyle] for secondary placement.
ButtonStyle destructiveOutlinedButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    foregroundColor: scheme.error,
    side: BorderSide(color: scheme.error),
  );
}
