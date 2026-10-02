import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/theme/app_colors.dart';
import 'package:tsumoai_mobile/theme/app_theme.dart';
import 'package:tsumoai_mobile/widgets/status_banner.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final theme = AppTheme.light();
  final scheme = theme.colorScheme;
  const colors = AppColors.light;

  test('text colors meet WCAG AA (4.5:1) on their backgrounds', () {
    final pairs = <String, (Color, Color)>{
      'onSurface/surface': (scheme.onSurface, scheme.surface),
      'onSurface/background': (scheme.onSurface, theme.scaffoldBackgroundColor),
      'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
      'onSurfaceVariant/background': (
        scheme.onSurfaceVariant,
        theme.scaffoldBackgroundColor,
      ),
      'onPrimary/primary': (scheme.onPrimary, scheme.primary),
      'onPrimaryContainer/primaryContainer': (
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
      'primary/surface': (scheme.primary, scheme.surface),
      'error/surface': (scheme.error, scheme.surface),
      'scoreHighlight/surface': (colors.scoreHighlight, scheme.surface),
      for (final (name, status) in [
        ('success', colors.success),
        ('warning', colors.warning),
        ('error', colors.error),
        ('info', colors.info),
      ]) ...{
        '$name onContainer/container': (status.onContainer, status.container),
        '$name color/surface': (status.color, scheme.surface),
      },
      'camera onSurface/background': (
        colors.cameraOnSurface,
        colors.cameraBackground,
      ),
      'camera onSurfaceVariant/background': (
        Color.alphaBlend(
          colors.cameraOnSurfaceVariant,
          colors.cameraBackground,
        ),
        colors.cameraBackground,
      ),
    };
    for (final entry in pairs.entries) {
      final (foreground, background) = entry.value;
      expect(
        _contrast(foreground, background),
        greaterThanOrEqualTo(4.5),
        reason: entry.key,
      );
    }
  });

  test('detection frames stand out (3:1) against the camera background', () {
    for (final color in [colors.detectionBox, colors.detectionBoxPending]) {
      expect(
        _contrast(color, colors.cameraBackground),
        greaterThanOrEqualTo(3),
      );
    }
  });

  testWidgets('status banners carry an icon and text, not only a color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Column(
            children: [
              StatusBanner(kind: StatusKind.success, message: '成功'),
              StatusBanner(kind: StatusKind.warning, message: '注意'),
              StatusBanner(kind: StatusKind.error, message: '失敗'),
              StatusBanner(kind: StatusKind.info, message: 'お知らせ'),
            ],
          ),
        ),
      ),
    );

    for (final kind in StatusKind.values) {
      expect(find.byIcon(StatusBanner.iconFor(kind)), findsOneWidget);
    }
    expect(StatusKind.values.map(StatusBanner.iconFor).toSet(), hasLength(4));
    for (final text in ['成功', '注意', '失敗', 'お知らせ']) {
      expect(find.text(text), findsOneWidget);
    }
  });
}
