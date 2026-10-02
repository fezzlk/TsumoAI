import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

enum StatusKind { success, warning, error, info }

/// A state message shown with an icon, text and color, so the state is
/// readable without relying on color alone.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.kind,
    required this.message,
    this.action,
  });

  final StatusKind kind;
  final String message;

  /// Optional trailing action such as a retry button.
  final Widget? action;

  static IconData iconFor(StatusKind kind) => switch (kind) {
    StatusKind.success => Icons.check_circle_outline,
    StatusKind.warning => Icons.warning_amber_rounded,
    StatusKind.error => Icons.error_outline,
    StatusKind.info => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final colors = switch (kind) {
      StatusKind.success => appColors.success,
      StatusKind.warning => appColors.warning,
      StatusKind.error => appColors.error,
      StatusKind.info => appColors.info,
    };
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.s,
        ),
        decoration: BoxDecoration(
          color: colors.container,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Row(
          children: [
            Icon(iconFor(kind), size: 20, color: colors.onContainer),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.onContainer),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.s),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
