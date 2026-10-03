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
}

/// A tinted card: background, border and the text drawn on it.
@immutable
class TintColors {
  const TintColors({
    required this.container,
    required this.border,
    required this.onContainer,
  });

  final Color container;
  final Color border;
  final Color onContainer;
}

/// The color pair of one of the four checks (score, wait, discard, call):
/// the accent used for its icon and the tint of its card.
@immutable
class FeatureColors {
  const FeatureColors({required this.accent, required this.container});

  final Color accent;
  final Color container;
}

/// Colors of the dark photo-editing screens (crop, box editor).
@immutable
class EditorColors {
  const EditorColors({
    required this.background,
    required this.surface,
    required this.divider,
    required this.onSurface,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.selection,
  });

  final Color background;
  final Color surface;
  final Color divider;
  final Color onSurface;
  final Color muted;

  /// Main action on the dark editor (mint).
  final Color accent;
  final Color onAccent;

  /// Crop or box selection frame.
  final Color selection;
}

/// Meaningful colors beyond [ColorScheme], from the TsumoAI mobile design
/// system (Codex mockups, 2026-09-29).
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
    required this.developer,
    required this.primaryDark,
    required this.soft,
    required this.iconButton,
    required this.headerDivider,
    required this.score,
    required this.wait,
    required this.discard,
    required this.call,
    required this.sessionGradient,
    required this.sessionPlayingGradient,
    required this.tsumoCard,
    required this.ronCard,
    required this.recommended,
    required this.conditional,
    required this.photoGradient,
    required this.cameraBackground,
    required this.cameraOnSurface,
    required this.cameraOnSurfaceVariant,
    required this.cameraScrim,
    required this.cameraGuide,
    required this.detectionBox,
    required this.detectionBoxPending,
    required this.scoreHighlight,
    required this.winningTile,
    required this.meldTile,
    required this.tileFace,
    required this.tileBorder,
    required this.tileShade,
    required this.tileRed,
    required this.editor,
    required this.onDark,
    required this.onDarkMuted,
    required this.sessionEyebrow,
    required this.sessionPlayingEyebrow,
    required this.shortcut,
    required this.headerIcon,
  });

  final StatusColors success;
  final StatusColors warning;
  final StatusColors error;
  final StatusColors info;

  /// Developer-only features (training data, admin tools).
  final StatusColors developer;

  final Color primaryDark;

  /// Light primary tint: selected chips, icon frames, section badges.
  final Color soft;

  /// Background of round icon buttons (home, settings).
  final Color iconButton;

  /// Hairline under the common screen header.
  final Color headerDivider;

  final FeatureColors score;
  final FeatureColors wait;
  final FeatureColors discard;
  final FeatureColors call;

  /// Home's match card; the playing variant when a match is in progress.
  final List<Color> sessionGradient;
  final List<Color> sessionPlayingGradient;

  /// Score results: tsumo (green tint) and ron (blue tint).
  final TintColors tsumoCard;
  final TintColors ronCard;

  /// Call groups and the best discard: recommended / conditional.
  final TintColors recommended;
  final TintColors conditional;

  /// Deep-green frame behind a photo of the hand and the camera preview.
  final List<Color> photoGradient;

  final Color cameraBackground;
  final Color cameraOnSurface;
  final Color cameraOnSurfaceVariant;

  /// Translucent panel drawn over a camera image.
  final Color cameraScrim;

  /// Guide frame drawn over the camera preview.
  final Color cameraGuide;

  /// Detected tile frames on a camera image.
  final Color detectionBox;

  /// Frames that are detected but not yet stable or confirmed.
  final Color detectionBoxPending;

  /// The most important number of a result (points, waits).
  final Color scoreHighlight;

  /// Frame and arrow marking the あがり牌 in tile rows.
  final Color winningTile;

  /// Frame around tiles that belong to a confirmed 副露.
  final Color meldTile;

  /// Drawn tile glyphs (large tiles in result rows).
  final Color tileFace;
  final Color tileBorder;
  final Color tileShade;
  final Color tileRed;

  final EditorColors editor;

  /// Text and icons on deep-green or photo surfaces.
  final Color onDark;
  final Color onDarkMuted;

  /// Small label on Home's match card (idle / playing).
  final Color sessionEyebrow;
  final Color sessionPlayingEyebrow;

  /// Dashed developer shortcut on Home.
  final TintColors shortcut;

  /// Foreground of round header icon buttons.
  final Color headerIcon;

  static const light = AppColors(
    success: StatusColors(
      color: Color(0xFF176B52),
      container: Color(0xFFEAF5EF),
      onContainer: Color(0xFF1E4537),
    ),
    warning: StatusColors(
      color: Color(0xFF895F08),
      container: Color(0xFFFFF0C8),
      onContainer: Color(0xFF694B0A),
    ),
    error: StatusColors(
      color: Color(0xFFAA3232),
      container: Color(0xFFFBE4E4),
      onContainer: Color(0xFF8A2626),
    ),
    info: StatusColors(
      color: Color(0xFF285B89),
      container: Color(0xFFE2EDF7),
      onContainer: Color(0xFF23465C),
    ),
    developer: StatusColors(
      color: Color(0xFF674590),
      container: Color(0xFFEEE5F8),
      onContainer: Color(0xFF56387B),
    ),
    primaryDark: Color(0xFF0D4F3B),
    soft: Color(0xFFE8F2ED),
    iconButton: Color(0xFFE9EFEB),
    headerDivider: Color(0xFFE4E8E5),
    score: FeatureColors(
      accent: Color(0xFF167257),
      container: Color(0xFFE7F4ED),
    ),
    wait: FeatureColors(
      accent: Color(0xFF31729A),
      container: Color(0xFFE7F0F6),
    ),
    discard: FeatureColors(
      accent: Color(0xFF9C651E),
      container: Color(0xFFF8EFE2),
    ),
    call: FeatureColors(
      accent: Color(0xFF76508A),
      container: Color(0xFFF2EAF5),
    ),
    sessionGradient: [Color(0xFF126448), Color(0xFF0B4B3B)],
    sessionPlayingGradient: [Color(0xFF9F6421), Color(0xFF754413)],
    tsumoCard: TintColors(
      container: Color(0xFFEAF5EF),
      border: Color(0xFFB7DACA),
      onContainer: Color(0xFF1E4537),
    ),
    ronCard: TintColors(
      container: Color(0xFFEAF2F7),
      border: Color(0xFFC5D7E3),
      onContainer: Color(0xFF23465C),
    ),
    recommended: TintColors(
      container: Color(0xFFEEF8F3),
      border: Color(0xFF9BD2BA),
      onContainer: Color(0xFF1E4537),
    ),
    conditional: TintColors(
      container: Color(0xFFFFF9E8),
      border: Color(0xFFDEC98B),
      onContainer: Color(0xFF694B0A),
    ),
    photoGradient: [Color(0xFF26775E), Color(0xFF14533F)],
    cameraBackground: Color(0xFF104B37),
    cameraOnSurface: Color(0xFFFFFFFF),
    cameraOnSurfaceVariant: Color(0xFFD9F5E8),
    cameraScrim: Color(0x94081C14),
    cameraGuide: Color(0xCCAAF2D3),
    detectionBox: Color(0xFF53DF9F),
    detectionBoxPending: Color(0xFFFBBF24),
    scoreHighlight: Color(0xFF176B52),
    winningTile: Color(0xFF176B52),
    meldTile: Color(0xFF285B89),
    tileFace: Color(0xFFFFFFFF),
    tileBorder: Color(0xFFCBD4CE),
    tileShade: Color(0xFFD9DFDB),
    tileRed: Color(0xFF8A2924),
    editor: EditorColors(
      background: Color(0xFF111713),
      surface: Color(0xFF151E1A),
      divider: Color(0xFF2D3933),
      onSurface: Color(0xFFEDF7F2),
      muted: Color(0xFF9DB0A7),
      accent: Color(0xFF62E2AD),
      onAccent: Color(0xFF09291C),
      selection: Color(0xFF53DF9F),
    ),
    onDark: Color(0xFFFFFFFF),
    onDarkMuted: Color(0xBFFFFFFF),
    sessionEyebrow: Color(0xFFBDE7D5),
    sessionPlayingEyebrow: Color(0xFFFFE0A9),
    shortcut: TintColors(
      container: Color(0xFFF0F7F3),
      border: Color(0xFF7DA795),
      onContainer: Color(0xFFDCECE4),
    ),
    headerIcon: Color(0xFF315247),
  );

  @override
  AppColors copyWith() => this;

  // These are fixed brand colors; a theme change snaps rather than animates.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      other is AppColors && t >= 0.5 ? other : this;
}

extension AppColorsContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
