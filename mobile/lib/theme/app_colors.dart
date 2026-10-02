import 'package:flutter/material.dart';

/// A state color with the container/foreground pair used for banners.
@immutable
class StatusColors {
  const StatusColors({
    required this.color,
    required this.container,
    required this.onContainer,
  });

  /// Icons and short emphasized text on the normal background.
  final Color color;
  final Color container;
  final Color onContainer;

  static StatusColors lerp(StatusColors a, StatusColors b, double t) =>
      StatusColors(
        color: Color.lerp(a.color, b.color, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );
}

/// Meaningful colors beyond [ColorScheme]: states and the camera surfaces.
///
/// Screens use these instead of raw `Colors.*` so that the same meaning is
/// always shown with the same color.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.cameraBackground,
    required this.cameraOnSurface,
    required this.cameraOnSurfaceVariant,
    required this.cameraScrim,
    required this.detectionBox,
    required this.detectionBoxPending,
    required this.scoreHighlight,
  });

  final StatusColors success;
  final StatusColors warning;
  final StatusColors error;
  final StatusColors info;

  /// Camera and photo-editing screens stay dark: a light frame around a
  /// photo makes it harder to read and reflects on the table.
  final Color cameraBackground;
  final Color cameraOnSurface;
  final Color cameraOnSurfaceVariant;

  /// Translucent panel drawn over a camera image.
  final Color cameraScrim;

  /// Detected tile frames on a camera image.
  final Color detectionBox;

  /// Frames that are detected but not yet stable or confirmed.
  final Color detectionBoxPending;

  /// The most important number of a result (points, waits).
  final Color scoreHighlight;

  static const light = AppColors(
    success: StatusColors(
      color: Color(0xFF1B7F4B),
      container: Color(0xFFD7F0DF),
      onContainer: Color(0xFF0B3D22),
    ),
    warning: StatusColors(
      color: Color(0xFF8A5A00),
      container: Color(0xFFFFEFCF),
      onContainer: Color(0xFF4A3000),
    ),
    error: StatusColors(
      color: Color(0xFFB3261E),
      container: Color(0xFFF9DEDC),
      onContainer: Color(0xFF410E0B),
    ),
    info: StatusColors(
      color: Color(0xFF1E5AA8),
      container: Color(0xFFDCE8F8),
      onContainer: Color(0xFF0B2A52),
    ),
    cameraBackground: Color(0xFF000000),
    cameraOnSurface: Color(0xFFFFFFFF),
    cameraOnSurfaceVariant: Color(0xB3FFFFFF),
    cameraScrim: Color(0x99000000),
    detectionBox: Color(0xFF4ADE80),
    detectionBoxPending: Color(0xFFFBBF24),
    scoreHighlight: Color(0xFF14633A),
  );

  @override
  AppColors copyWith({
    StatusColors? success,
    StatusColors? warning,
    StatusColors? error,
    StatusColors? info,
    Color? cameraBackground,
    Color? cameraOnSurface,
    Color? cameraOnSurfaceVariant,
    Color? cameraScrim,
    Color? detectionBox,
    Color? detectionBoxPending,
    Color? scoreHighlight,
  }) => AppColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
    cameraBackground: cameraBackground ?? this.cameraBackground,
    cameraOnSurface: cameraOnSurface ?? this.cameraOnSurface,
    cameraOnSurfaceVariant:
        cameraOnSurfaceVariant ?? this.cameraOnSurfaceVariant,
    cameraScrim: cameraScrim ?? this.cameraScrim,
    detectionBox: detectionBox ?? this.detectionBox,
    detectionBoxPending: detectionBoxPending ?? this.detectionBoxPending,
    scoreHighlight: scoreHighlight ?? this.scoreHighlight,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: StatusColors.lerp(success, other.success, t),
      warning: StatusColors.lerp(warning, other.warning, t),
      error: StatusColors.lerp(error, other.error, t),
      info: StatusColors.lerp(info, other.info, t),
      cameraBackground: Color.lerp(
        cameraBackground,
        other.cameraBackground,
        t,
      )!,
      cameraOnSurface: Color.lerp(cameraOnSurface, other.cameraOnSurface, t)!,
      cameraOnSurfaceVariant: Color.lerp(
        cameraOnSurfaceVariant,
        other.cameraOnSurfaceVariant,
        t,
      )!,
      cameraScrim: Color.lerp(cameraScrim, other.cameraScrim, t)!,
      detectionBox: Color.lerp(detectionBox, other.detectionBox, t)!,
      detectionBoxPending: Color.lerp(
        detectionBoxPending,
        other.detectionBoxPending,
        t,
      )!,
      scoreHighlight: Color.lerp(scoreHighlight, other.scoreHighlight, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
