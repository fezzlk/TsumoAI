import 'package:flutter/material.dart';

/// The 使い方 dialog, opened from Home's ? button and from Settings.
Future<void> showHelpDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const AlertDialog(
    title: Text('使い方'),
    content: Text(
      'ホームで目的を選び、牌をカメラに収めます。認識結果では牌・枚数・条件を訂正でき、結果へすぐ反映されます。\n\n'
      '「実際の対局進行に合わせて点数計算を行う」では、1台の端末で局・親・本場を管理できます。',
    ),
  ),
);
