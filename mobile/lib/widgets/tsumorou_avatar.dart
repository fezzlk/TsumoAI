import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shared Tsumorou artwork for the home brand and assistant messages.
class TsumorouAvatar extends StatelessWidget {
  const TsumorouAvatar({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.appColors.soft,
      borderRadius: BorderRadius.circular(AppRadius.brandMark),
    ),
    child: Image.asset(
      'assets/branding/tsumorou.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'ツモロウ',
    ),
  );
}
