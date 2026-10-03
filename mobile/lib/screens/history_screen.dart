import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../models/ai_chat_message.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../widgets/analysis_result_panel.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/ai_chat_sheet.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/section_list.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.service});

  final HistoryService? service;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryService _service = widget.service ?? HistoryService();
  List<HistoryEntry> _entries = [];
  String _filter = 'all';
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final local = await _service.loadLocal();
    if (!mounted) return;
    setState(() {
      _entries = local;
      _loading = false;
    });
    await _sync();
  }

  Future<void> _sync() async {
    if (AuthService.currentUser == null) return;
    setState(() => _syncing = true);
    final entries = await _service.synchronize();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _syncing = false;
    });
  }

  Future<void> _signInAndSync() async {
    try {
      await AuthService.ensureSignedIn();
      await _sync();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログインに失敗しました: $error')));
    }
  }

  static const _filters = [
    ('all', 'すべて'),
    ('score', '点数'),
    ('wait', '待ち'),
    ('discard', '何切る'),
    ('call_advice', '鳴き'),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = _filter == 'all'
        ? _entries
        : _entries.where((entry) => entry.purpose == _filter).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StreamBuilder<User?>(
              stream: AuthService.authStateChanges(),
              initialData: AuthService.currentUser,
              builder: (context, snapshot) => ScreenHeader(
                title: '利用履歴',
                subtitle: snapshot.data == null
                    ? 'この端末の履歴'
                    : _syncing
                    ? '同期中…'
                    : '過去の確認とAI相談',
                backLabel: '設定',
                trailing: const HeaderHomeButton(),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _sync,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.l,
                          AppSpacing.l,
                          AppSpacing.l,
                          AppSpacing.xl,
                        ),
                        children: [
                          _signedOutNotice(),
                          if (entries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xl * 2,
                              ),
                              child: Center(
                                child: Text(
                                  '履歴はまだありません',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            )
                          else
                            for (final group in _groupByDay(entries)) ...[
                              SectionLabel(group.$1),
                              SectionGroup(
                                children: [
                                  for (final entry in group.$2)
                                    _entryTile(entry),
                                ],
                              ),
                            ],
                        ],
                      ),
                    ),
            ),
            _filterTabs(),
          ],
        ),
      ),
    );
  }

  Widget _signedOutNotice() => StreamBuilder<User?>(
    stream: AuthService.authStateChanges(),
    initialData: AuthService.currentUser,
    builder: (context, snapshot) {
      if (snapshot.data != null) return const SizedBox.shrink();
      final text = Theme.of(context).textTheme;
      final colors = context.appColors;
      return Container(
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.xLarge),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.soft,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Icon(Icons.cloud_outlined, color: colors.success.color),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('現在はこの端末の履歴を表示しています', style: text.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'ログインすると、同じアカウントに紐づく履歴も一覧に表示します。',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  FilledButton(
                    onPressed: _signInAndSync,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(80, AppSizes.tapTarget),
                    ),
                    child: const Text('ログイン'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _filterTabs() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          for (final (value, label) in _filters) ...[
            if (value != 'all') const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _FilterTab(
                label: label,
                selected: _filter == value,
                onTap: () => setState(() => _filter = value),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entryTile(HistoryEntry entry) {
    final feature = _featureColors(context, entry.purpose);
    return SectionTile(
      mark: _purposeMark(entry.purpose),
      markColors: StatusColors(
        color: feature.accent,
        container: feature.container,
        onContainer: feature.accent,
      ),
      title: entry.title,
      subtitle: [
        if (entry.roundLabel != null) entry.roundLabel!,
        entry.summary,
      ].join('  '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _timeLabel(entry.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HistoryDetailScreen(entry: entry, service: _service),
        ),
      ),
    );
  }

  List<(String, List<HistoryEntry>)> _groupByDay(List<HistoryEntry> entries) {
    final groups = <String, List<HistoryEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(_dayLabel(entry.createdAt), () => []).add(entry);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  String _dayLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今日';
    if (diff == 1) return '昨日';
    return '${local.month}月${local.day}日';
  }

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

String _purposeMark(String purpose) => switch (purpose) {
  'score' => '点',
  'wait' => '待',
  'discard' => '切',
  'call_advice' => '鳴',
  _ => '他',
};

FeatureColors _featureColors(BuildContext context, String purpose) {
  final colors = context.appColors;
  return switch (purpose) {
    'wait' => colors.wait,
    'discard' => colors.discard,
    'call_advice' => colors.call,
    _ => colors.score,
  };
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AppSizes.tapTarget,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({super.key, required this.entry, this.service});

  final HistoryEntry entry;
  final HistoryService? service;

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  late HistoryEntry _entry = widget.entry;
  late final HistoryService _service = widget.service ?? HistoryService();
  Future<void> _historyUpdateQueue = Future.value();

  List<AIChatMessage> get _conversation =>
      (_entry.details['ai_conversation'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AIChatMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);

  Future<void> _continueChat() async {
    final tiles = (_entry.details['tiles'] as List<dynamic>? ?? const [])
        .map((tile) => tile.toString())
        .toList(growable: false);
    final analysis = _historyMap(_entry.details['result']);
    final roundContext = _historyMap(_entry.details['context']);
    await AIChatSheet.show(
      context,
      purpose: _entry.purpose,
      tiles: tiles,
      roundContext: roundContext,
      analysis: analysis,
      initialMessages: _conversation,
      onMessagesChanged: (messages) {
        // Each write is isolated: one failed save must not leave the queue
        // in an error state that silently skips every later conversation.
        _historyUpdateQueue = _historyUpdateQueue.then((_) async {
          try {
            final updated = await _service.updateDetails(_entry.id, {
              'ai_conversation': messages
                  .map((message) => message.toJson())
                  .toList(growable: false),
            });
            if (mounted && updated != null) setState(() => _entry = updated);
          } catch (error) {
            debugPrint('HistoryDetail: failed to save AI conversation: $error');
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = (_entry.details['tiles'] as List<dynamic>? ?? const [])
        .map((tile) => tile.toString())
        .toList(growable: false);
    final analysis = _historyMap(_entry.details['result']);
    final contextDetails = _historyMap(_entry.details['context']);
    return Scaffold(
      appBar: AppBar(title: Text(_entry.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              _entry.summary,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _HistoryMetaChip(
                  icon: Icons.schedule,
                  label: _historyDateLabel(_entry.createdAt),
                ),
                if (_entry.roundLabel != null)
                  _HistoryMetaChip(
                    icon: Icons.casino_outlined,
                    label: _entry.roundLabel!,
                  ),
                if (contextDetails['round_wind'] case final Object roundWind)
                  _HistoryMetaChip(
                    icon: Icons.flag_outlined,
                    label: '場風 ${_windLabel(roundWind)}',
                  ),
                if (contextDetails['seat_wind'] case final Object seatWind)
                  _HistoryMetaChip(
                    icon: Icons.event_seat_outlined,
                    label: '自風 ${_windLabel(seatWind)}',
                  ),
              ],
            ),
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('認識した牌', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < tiles.length; index++) ...[
                      if (index > 0) const SizedBox(width: 3),
                      SizedBox(
                        key: ValueKey('history-tile-$index'),
                        width: 30,
                        height: 42,
                        child: TileGlyph(tileCode: tiles[index]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_entry.purpose == 'score')
              _ScoreHistoryDetails(details: _entry.details)
            else if (analysis.isNotEmpty)
              AnalysisResultPanel(result: analysis)
            else
              const Text('詳細結果は保存されていません'),
            if (_entry.purpose == 'discard' ||
                _entry.purpose == 'call_advice') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _continueChat,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(_conversation.isEmpty ? 'AIに質問' : 'AIとの会話を続ける'),
                ),
              ),
              if (_conversation.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('AIとの会話', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final message in _conversation)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${message.role == 'user' ? 'あなた' : 'AI'}: ${message.content}',
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryMetaChip extends StatelessWidget {
  const _HistoryMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

class _ScoreHistoryDetails extends StatelessWidget {
  const _ScoreHistoryDetails({required this.details});

  final Map<String, dynamic> details;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ScoreHistorySection(
        label: 'ツモの場合',
        result: _historyMap(details['tsumo']),
      ),
      const SizedBox(height: 12),
      _ScoreHistorySection(label: 'ロンの場合', result: _historyMap(details['ron'])),
    ],
  );
}

class _ScoreHistorySection extends StatelessWidget {
  const _ScoreHistorySection({required this.label, required this.result});

  final String label;
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final yaku = (result['yaku'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (result.isEmpty)
              const Text('和了不成立')
            else ...[
              Text(
                '${_historyInt(result['han'])}翻 '
                '${_historyInt(result['fu'])}符 '
                '${result['point_label'] ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (yaku.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(yaku.join('・')),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _historyMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

int _historyInt(Object? value) => value is num ? value.toInt() : 0;

String _windLabel(Object value) => switch (value.toString()) {
  'E' => '東',
  'S' => '南',
  'W' => '西',
  'N' => '北',
  final value => value,
};

String _historyDateLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${local.month}/${local.day} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
