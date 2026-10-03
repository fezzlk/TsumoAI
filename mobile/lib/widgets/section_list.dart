import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Small heading above a [SectionGroup] (利用データ, サポート, ...).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, AppSpacing.l, 4, AppSpacing.s),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// White rounded group of [SectionTile]s separated by hairlines.
class SectionGroup extends StatelessWidget {
  const SectionGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(AppRadius.card),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          children[i],
        ],
      ],
    ),
  );
}

/// A settings row: a one-character icon tile, title, optional subtitle and
/// a trailing chevron (or a custom widget such as a switch).
class SectionTile extends StatelessWidget {
  const SectionTile({
    super.key,
    required this.mark,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.developer = false,
    this.destructive = false,
    this.markColors,
  });

  /// One character shown in the icon tile (履, 牌, ?, ...).
  final String mark;
  final String title;
  final String? subtitle;

  /// Defaults to a chevron when [onTap] is set.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Developer-only rows use the developer (purple) tint.
  final bool developer;

  /// Rows that delete data use the error color for their title.
  final bool destructive;

  /// Overrides the icon tile colors (e.g. a check's feature color).
  final StatusColors? markColors;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final markColors =
        this.markColors ??
        (developer
            ? colors.developer
            : destructive
            ? colors.error
            : StatusColors(
                color: colors.success.color,
                container: colors.soft,
                onContainer: colors.success.color,
              ));
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l,
            vertical: 10,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: markColors.container,
                  borderRadius: BorderRadius.circular(AppRadius.iconTile),
                ),
                child: Text(
                  mark,
                  style: text.labelMedium?.copyWith(
                    color: markColors.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        color: destructive ? colors.error.color : null,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
