import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The common header of the design system: back on the left, the screen
/// name (with an optional status line) in the center, home on the right.
class ScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.backLabel = '戻る',
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String backLabel;

  /// Defaults to popping the current route.
  final VoidCallback? onBack;

  /// Right-hand control; usually [HeaderHomeButton]. Empty when null.
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(AppSpacing.l, 2, AppSpacing.l, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.appColors.headerDivider),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack ?? () => Navigator.maybePop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                ),
                icon: const Icon(Icons.chevron_left, size: 22),
                label: Text(backLabel, maxLines: 1),
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      ),
    );
  }
}

/// Round icon button used at the right of [ScreenHeader] and on Home.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    style: IconButton.styleFrom(
      backgroundColor: context.appColors.iconButton,
      foregroundColor: context.appColors.headerIcon,
      fixedSize: const Size(AppSizes.tapTarget, AppSizes.tapTarget),
    ),
    icon: Icon(icon, size: 22),
  );
}

/// Home button for the right of [ScreenHeader]: returns to the first route.
class HeaderHomeButton extends StatelessWidget {
  const HeaderHomeButton({super.key, this.tooltip = 'ホーム', this.onPressed});

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
    icon: Icons.home_outlined,
    tooltip: tooltip,
    onPressed:
        onPressed ??
        () => Navigator.of(context).popUntil((route) => route.isFirst),
  );
}
