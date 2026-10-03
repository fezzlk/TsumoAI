import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/section_list.dart';

/// 使い方・ヘルプ, opened from Settings: how-to by purpose and a short FAQ.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.onContact});

  /// Opens the contact page (owned by Settings).
  final VoidCallback onContact;

  static const _faq = [
    (
      '牌が正しく認識されない',
      '結果画面で牌をタップすると種類を訂正できます。枚数が違う場合は13〜18枚を選び直すと、同じ写真から再検出します。',
    ),
    ('ツモとロンはどこで選びますか？', '選択は不要です。点数計算結果にツモの場合とロンの場合を両方表示します。'),
    ('ログインしなくても使えますか？', '点数計算、待ち確認、何切る、鳴き判断はログインなしで利用できます。AI相談はログインすると利用できます。'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topics = [
      _HelpTopic(
        colors.score,
        '点',
        '点数計算',
        'ツモ・ロンの点数',
        'ホームの「点数計算」から手牌を撮影します。認識した牌と条件を確認すると、ツモの場合とロンの場合の役・翻・符・支払いを両方表示します。',
      ),
      _HelpTopic(
        colors.wait,
        '待',
        '待ち確認',
        '待ち牌を確認',
        '13枚の手牌を撮影すると、テンパイなら待ち牌を、テンパイでなければ向聴数と有効牌を表示します。',
      ),
      _HelpTopic(
        colors.discard,
        '切',
        '何切る',
        '打牌候補を比較',
        '14枚の手牌を撮影すると、牌効率で上位3つの打牌候補を受け入れ枚数とあわせて表示します。',
      ),
      _HelpTopic(
        colors.call,
        '鳴',
        '鳴き判断',
        '鳴ける候補を確認',
        '13枚の手牌から、今後鳴ける可能性のある牌とチー・ポン・カンを推奨・条件付き・見送りに分けて表示します。',
      ),
      _HelpTopic(
        colors.score,
        '東',
        '対局サポート',
        '1半荘の局進行と点数計算',
        'ホームの対局カードから始めます。和了した人の座席をタップして撮影すると点数を計算し、局・親・本場を自動で進めます。',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: '使い方・ヘルプ', trailing: HeaderHomeButton()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.xl,
                ),
                children: [
                  Text(
                    '目的から使い方を見る',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  for (var i = 0; i < topics.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.s),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: topics[i]),
                          if (i + 1 < topics.length) ...[
                            const SizedBox(width: AppSpacing.s),
                            Expanded(child: topics[i + 1]),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SectionLabel('よくある質問'),
                  SectionGroup(
                    children: [
                      for (final (question, answer) in _faq)
                        _FaqTile(question: question, answer: answer),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.m),
                  SectionGroup(
                    children: [
                      SectionTile(
                        mark: '問',
                        title: '解決しない場合',
                        subtitle: '問い合わせを送る',
                        onTap: onContact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTopic extends StatelessWidget {
  const _HelpTopic(
    this.colors,
    this.mark,
    this.title,
    this.subtitle,
    this.description,
  );

  final FeatureColors colors;
  final String mark;
  final String title;
  final String subtitle;
  final String description;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(description, style: text.bodyLarge),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.container,
                  borderRadius: BorderRadius.circular(AppRadius.iconTile),
                ),
                child: Text(
                  mark,
                  style: text.titleSmall?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: text.titleSmall),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          0,
          AppSpacing.l,
          AppSpacing.m,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(question, style: text.titleSmall),
        children: [Text(answer, style: text.bodyMedium)],
      ),
    );
  }
}
