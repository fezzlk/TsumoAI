import 'package:flutter/material.dart';

import '../models/ai_usage_status.dart';
import '../services/api_client.dart';

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
    appBar: AppBar(title: const Text('AI利用状況')),
    body: SafeArea(
      child: FutureBuilder<AIUsageStatus>(
        future: _status,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final status = snapshot.data;
          if (status == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('利用状況を取得できませんでした'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _retry, child: const Text('再試行')),
                  ],
                ),
              ),
            );
          }
          final reset = status.resetsAt;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                status.planLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '残り ${status.remaining}回',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: status.includedLimit == 0
                    ? 0
                    : (status.includedUsed / status.includedLimit).clamp(0, 1),
              ),
              const SizedBox(height: 8),
              Text('今月 ${status.includedUsed} / ${status.includedLimit}回利用'),
              if (status.bonusRemaining > 0) ...[
                const SizedBox(height: 4),
                Text('追加枠 ${status.bonusRemaining}回'),
              ],
              const SizedBox(height: 20),
              Text('月間枠は${reset.year}年${reset.month}月1日に更新されます。'),
              const SizedBox(height: 8),
              const Text('点数計算・待ち確認・何切る・鳴き判断の基本結果は、AI相談の残り回数に関係なく利用できます。'),
            ],
          );
        },
      ),
    ),
  );
}
