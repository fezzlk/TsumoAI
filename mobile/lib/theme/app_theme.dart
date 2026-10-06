import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Corner radii from the design system: tiles, chips, buttons, cards,
/// modals.
abstract final class AppRadius {
  static const small = 4.0;
  static const medium = 8.0;
  static const chip = 11.0;
  static const large = 12.0;
  static const button = 14.0;
  static const card = 16.0;
  static const xLarge = 20.0;
  static const modal = 24.0;

  /// Home: brand mark, login pill, feature cards, match card.
  static const iconTile = 10.0;
  static const brandMark = 13.0;
  static const pill = 15.0;
  static const feature = 18.0;
  static const hero = 22.0;
}

/// Spacing scale (4px steps); screens use 16 side padding and 12 between
/// cards.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
}

/// Control heights from the design system.
abstract final class AppSizes {
  static const primaryButton = 52.0;
  static const tapTarget = 48.0;
  static const chip = 40.0;
}

abstract final class AppTheme {
  static const _primary = Color(0xFF176B52);
  static const _background = Color(0xFFF6F8F5);
  static const _text = Color(0xFF1A3027);
  // The design system's #718078 is 3.9:1 on the background; this slightly
  // darker tone keeps the look and meets AA (4.7:1).
  static const _muted = Color(0xFF63726B);
  static const _border = Color(0xFFD9E3DD);

  // Built once: screens wrap themselves in these on every rebuild (camera
  // frames, handle drags), and ColorScheme.fromSeed is not free.
  static final ThemeData _light = _buildLight();
  static final ThemeData _editor = _buildEditor();

  /// The app theme: light, deep green for primary actions.
  static ThemeData light() => _light;

  /// Dark theme of the photo-editing screens (crop, box editor).
  static ThemeData editor() => _editor;

  static ThemeData _buildLight() {
    final colors = AppColors.light;
    final scheme = ColorScheme.fromSeed(seedColor: _primary).copyWith(
      primary: _primary,
      onPrimary: Colors.white,
      primaryContainer: colors.soft,
      onPrimaryContainer: colors.success.onContainer,
      secondaryContainer: const Color(0xFFEDF1EE),
      onSecondaryContainer: _text,
      tertiary: colors.developer.color,
      surface: Colors.white,
      onSurface: _text,
      onSurfaceVariant: _muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F8F5),
      surfaceContainer: const Color(0xFFF1F4F1),
      surfaceContainerHigh: const Color(0xFFEEF2EF),
      surfaceContainerHighest: const Color(0xFFEDF1EE),
      outline: const Color(0xFFCAD5CF),
      outlineVariant: _border,
      error: colors.error.color,
      errorContainer: colors.error.container,
      onErrorContainer: colors.error.onContainer,
    );
    return _build(scheme, background: _background);
  }

  static ThemeData _buildEditor() {
    final editor = AppColors.light.editor;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: editor.accent,
          onPrimary: editor.onAccent,
          surface: editor.surface,
          onSurface: editor.onSurface,
          onSurfaceVariant: editor.muted,
          outlineVariant: editor.divider,
        );
    return _build(scheme, background: editor.background);
  }

  static ThemeData _build(ColorScheme scheme, {required Color background}) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final t = base.textTheme;
    TextStyle? style(TextStyle? s, double size, FontWeight weight) =>
        s?.copyWith(fontSize: size, fontWeight: weight, height: 1.35);
    // Design system scale: screen title 17/700, result number 30/800,
    // section 13/700, body 12/400, caption 10/500.
    final textTheme = t
        .copyWith(
          headlineMedium: style(t.headlineMedium, 30, FontWeight.w800),
          headlineSmall: style(t.headlineSmall, 22, FontWeight.w800),
          titleLarge: style(t.titleLarge, 17, FontWeight.w700),
          titleMedium: style(t.titleMedium, 15, FontWeight.w800),
          titleSmall: style(t.titleSmall, 13, FontWeight.w700),
          bodyLarge: style(t.bodyLarge, 13, FontWeight.w400),
          bodyMedium: style(t.bodyMedium, 12, FontWeight.w400),
          bodySmall: style(
            t.bodySmall,
            10,
            FontWeight.w500,
          )?.copyWith(color: scheme.onSurfaceVariant),
          labelLarge: style(t.labelLarge, 12, FontWeight.w800),
          labelMedium: style(t.labelMedium, 11, FontWeight.w800),
          labelSmall: style(t.labelSmall, 10, FontWeight.w700),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final bodySmall = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme.copyWith(bodySmall: bodySmall),
      extensions: const [AppColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppSizes.tapTarget, AppSizes.primaryButton),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AppSizes.tapTarget, AppSizes.tapTarget),
          shape: buttonShape,
          foregroundColor: scheme.primary,
          backgroundColor: scheme.surface,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(AppSizes.tapTarget, AppSizes.primaryButton),
          shape: buttonShape,
          elevation: 0,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSizes.tapTarget, AppSizes.tapTarget),
          shape: buttonShape,
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSizes.tapTarget, AppSizes.tapTarget),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xLarge),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.modal),
        ),
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.modal),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xEB14221C),
        contentTextStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: bodySmall,
      ),
    );
  }
}

/// Filled style for buttons that delete, discard or end something.
ButtonStyle destructiveButtonStyle(BuildContext context) {
  final colors = context.appColors.error;
  return FilledButton.styleFrom(
    backgroundColor: colors.color,
    foregroundColor: Colors.white,
  );
}

/// Outlined style for destructive actions (対局を終了, ログアウト): red text
/// and a soft red border on white, as in the design system.
ButtonStyle destructiveOutlinedButtonStyle(BuildContext context) {
  final colors = context.appColors.error;
  return OutlinedButton.styleFrom(
    foregroundColor: colors.color,
    backgroundColor: Theme.of(context).colorScheme.surface,
    side: const BorderSide(color: Color(0xFFDCA8A8)),
    minimumSize: const Size(AppSizes.tapTarget, AppSizes.primaryButton),
  );
}
