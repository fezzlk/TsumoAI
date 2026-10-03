import 'package:flutter/material.dart';

import '../models/ai_usage_status.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/status_banner.dart';

typedef AIUsageLoader = Future<AIUsageStatus> Function();

class AIUsageScreen extends StatefulWidget {
  const AIUsageScreen({super.key, this.loader});

  final AIUsageLoader? loader;

  @override
  State<AIUsageScreen> createState() => _AIUsageScreenState();
}

class _AIUsageScreenState extends State<AIUsageScreen> {
  late Future<AIUsageStatus> _status = _load();

  Future<AIUsageStatus> _load() =>
      widget.loader?.call() ?? ApiClient().fetchAiUsage();

  void _retry() => setState(() => _status = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const ScreenHeader(title: 'AI利用状況', trailing: HeaderHomeButton()),
          Expanded(
            child: FutureBuilder<AIUsageStatus>(
              future: _status,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final status = snapshot.data;
                if (snapshot.error is AILoginRequiredException) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.l),
                    child: StatusBanner(
                      kind: StatusKind.info,
                      message: 'AI相談はログインすると利用できます。ログイン後に利用状況を確認できます。',
                    ),
                  );
                }
                if (status == null) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    child: StatusBanner(
                      kind: StatusKind.error,
                      message: '利用状況を取得できませんでした',
                      action: TextButton(
                        onPressed: _retry,
                        child: const Text('再試行'),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  children: [
                    _UsageHero(status: status),
                    const SizedBox(height: AppSpacing.m),
                    _UsageCard(
                      title: '回数を使う操作',
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.appColors.soft,
                              borderRadius: BorderRadius.circular(
                                AppRadius.large,
                              ),
                            ),
                            child: Text(
                              'AI',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AIに質問を送信',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(
                                  '何切る・鳴き判断・履歴からの追加質問',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          _Pill(label: '1回', colors: context.appColors.warning),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    _UsageCard(
                      title: '回数を使わず利用できます',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.s,
                            runSpacing: AppSpacing.s,
                            children: [
                              for (final label in [
                                '点数計算',
                                '待ち確認',
                                '打牌候補',
                                '鳴き候補',
                                '牌の認識',
                              ])
                                _Pill(
                                  label: label,
                                  colors: StatusColors(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    container: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    onContainer: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.m),
                          Text(
                            'AI相談の回数がなくなっても、計算結果と候補は引き続き確認できます。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _UsageHero extends StatelessWidget {
  const _UsageHero({required this.status});

  final AIUsageStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final ratio = status.includedLimit == 0
        ? 0.0
        : (status.includedUsed / status.includedLimit).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.sessionGradient,
        ),
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.plan == 'subscription' ? '今月のAI相談' : '今月の無料AI相談',
            style: text.labelLarge?.copyWith(color: colors.sessionEyebrow),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'あと${status.remaining}回',
                  style: text.headlineMedium?.copyWith(color: colors.onDark),
                ),
              ),
              Text(
                '${status.includedUsed} / ${status.includedLimit} 回利用',
                style: text.labelMedium?.copyWith(color: colors.onDarkMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: colors.detectionBoxPending,
              backgroundColor: colors.onDark.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              Expanded(
                child: Text(
                  '次回更新',
                  style: text.labelMedium?.copyWith(color: colors.onDarkMuted),
                ),
              ),
              Text(
                '${status.resetsAt.month}月1日',
                style: text.labelLarge?.copyWith(color: colors.onDark),
              ),
            ],
          ),
          if (status.bonusRemaining > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '追加枠 ${status.bonusRemaining}回',
              style: text.labelMedium?.copyWith(color: colors.onDarkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.colors});

  final String label;
  final StatusColors colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: colors.container,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: colors.color),
    ),
  );
}
