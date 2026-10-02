import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../models/ai_chat_message.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../widgets/analysis_result_panel.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/ai_chat_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    final entries = _filter == 'all'
        ? _entries
        : _entries.where((entry) => _filterMatches(entry, _filter)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('利用履歴')),
      body: SafeArea(
        child: Column(
          children: [
            _accountStatus(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                  ? const Center(child: Text('履歴はまだありません'))
                  : RefreshIndicator(
                      onRefresh: _sync,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: entries.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (_, index) => _entryTile(entries[index]),
                      ),
                    ),
            ),
            NavigationBar(
              selectedIndex: _filterIndex,
              onDestinationSelected: (index) =>
                  setState(() => _filter = _filterForIndex(index)),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.history), label: 'すべて'),
                NavigationDestination(
                  icon: Icon(Icons.calculate_outlined),
                  label: '点数',
                ),
                NavigationDestination(
                  icon: Icon(Icons.center_focus_strong),
                  label: '待ち',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  label: 'AI相談',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountStatus() => StreamBuilder<User?>(
    stream: AuthService.authStateChanges(),
    initialData: AuthService.currentUser,
    builder: (context, snapshot) {
      final user = snapshot.data;
      return ListTile(
        leading: Icon(
          user == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
        ),
        title: Text(user?.email ?? '端末内履歴'),
        subtitle: Text(
          user == null
              ? 'ログインするとアカウントへ自動同期します'
              : _syncing
              ? '同期中…'
              : '自動同期',
        ),
        trailing: user == null
            ? TextButton(onPressed: _signInAndSync, child: const Text('ログイン'))
            : IconButton(
                onPressed: _syncing ? null : _sync,
                icon: const Icon(Icons.sync),
                tooltip: '同期',
              ),
      );
    },
  );

  int get _filterIndex => switch (_filter) {
    'score' => 1,
    'wait' => 2,
    'advice' => 3,
    _ => 0,
  };

  String _filterForIndex(int index) => switch (index) {
    1 => 'score',
    2 => 'wait',
    3 => 'advice',
    _ => 'all',
  };

  Widget _entryTile(HistoryEntry entry) => ListTile(
    leading: CircleAvatar(child: Icon(_purposeIcon(entry.purpose))),
    title: Text(entry.title),
    subtitle: Text(
      [
        _dateLabel(entry.createdAt),
        if (entry.roundLabel != null) entry.roundLabel!,
        entry.summary,
      ].join('  '),
    ),
    isThreeLine: true,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryDetailScreen(entry: entry, service: _service),
      ),
    ),
  );

  bool _filterMatches(HistoryEntry entry, String filter) => switch (filter) {
    'score' => entry.purpose == 'score',
    'wait' => entry.purpose == 'wait',
    'advice' => entry.purpose == 'discard' || entry.purpose == 'call_advice',
    _ => true,
  };

  IconData _purposeIcon(String purpose) => switch (purpose) {
    'score' => Icons.calculate_outlined,
    'wait' => Icons.center_focus_strong,
    'call_advice' => Icons.call_split,
    _ => Icons.auto_awesome_outlined,
  };

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
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
              const Text(
                '認識した牌',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
                const Text(
                  'AIとの会話',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
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
