import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'tsumorou_avatar.dart';

/// Tsumorou, the owl mentor next to the TsumoAI wordmark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => const TsumorouAvatar();
}

/// One of the four checks on Home: a tinted card with an icon frame,
/// title, short description and a chevron.
class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final FeatureColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: '$title $subtitle',
      excludeSemantics: true,
      child: Material(
        color: colors.container,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.feature),
          side: BorderSide(color: ink.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 13, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: context.appColors.onDark.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Icon(icon, size: 22, color: colors.accent),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: text.bodySmall?.copyWith(
                                color: ink.withValues(alpha: 0.66),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: ink.withValues(alpha: 0.44),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Home's match card: a deep-green panel (orange while a match is in
/// progress) with a tile pattern in the corner.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.playing,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.action,
    required this.onTap,
  });

  final bool playing;
  final String eyebrow;
  final String title;
  final String description;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final gradient = playing
        ? colors.sessionPlayingGradient
        : colors.sessionGradient;
    return Semantics(
      button: true,
      child: Material(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned(
                  right: 2,
                  top: 14,
                  child: CustomPaint(
                    size: const Size(134, 106),
                    painter: _TilePatternPainter(colors.onDark),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 102),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              eyebrow,
                              style: text.labelSmall?.copyWith(
                                color: playing
                                    ? colors.sessionPlayingEyebrow
                                    : colors.sessionEyebrow,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              title,
                              style: text.titleLarge?.copyWith(
                                color: colors.onDark,
                                fontWeight: FontWeight.w800,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              description,
                              style: text.bodySmall?.copyWith(
                                color: colors.onDarkMuted,
                                fontWeight: FontWeight.w600,
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.l),
                      // A solid white button so the card reads as something
                      // to press rather than a notice (device check
                      // 2026-10-04); the whole card stays tappable too.
                      SizedBox(
                        height: AppSizes.tapTarget,
                        child: FilledButton.icon(
                          onPressed: onTap,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.onDark,
                            foregroundColor: gradient.first,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(action),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TilePatternPainter extends CustomPainter {
  const _TilePatternPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color.withValues(alpha: 0.10);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    void tile(Offset center, double degrees, Offset crossCenter) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(degrees * 3.1415926535 / 180);
      final rect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-19, -27, 38, 54),
        const Radius.circular(7),
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, stroke);
      canvas.drawLine(
        Offset(crossCenter.dx - 5, crossCenter.dy - 8),
        Offset(crossCenter.dx + 5, crossCenter.dy - 8),
        stroke,
      );
      canvas.drawLine(
        Offset(crossCenter.dx, crossCenter.dy - 13),
        Offset(crossCenter.dx, crossCenter.dy + 5),
        stroke,
      );
      canvas.restore();
    }

    tile(const Offset(45, 41), -13, Offset.zero);
    tile(const Offset(89, 61), 8, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _TilePatternPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A dashed-outline card for developer-only shortcuts on Home.
class DeveloperShortcutCard extends StatelessWidget {
  const DeveloperShortcutCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    return CustomPaint(
      painter: _DashedBorderPainter(color: colors.shortcut.border),
      child: Material(
        color: colors.shortcut.container,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.shortcut.onContainer,
                      borderRadius: BorderRadius.circular(AppRadius.iconTile),
                    ),
                    child: Icon(icon, size: 22, color: colors.primaryDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(subtitle, style: text.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.card),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
