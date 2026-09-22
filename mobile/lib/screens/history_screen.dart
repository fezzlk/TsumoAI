import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';

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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('履歴を削除しますか？'),
        content: Text(
          AuthService.currentUser == null
              ? 'この端末の利用履歴を削除します。'
              : 'この端末とアカウントに紐付いた利用履歴を削除します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteAll();
      if (mounted) setState(() => _entries = []);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クラウド履歴を削除できませんでした。通信状態を確認してください。')),
      );
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('すべて')),
                  ButtonSegment(value: 'score', label: Text('点数')),
                  ButtonSegment(value: 'wait', label: Text('待ち')),
                  ButtonSegment(value: 'advice', label: Text('AI相談')),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _filter = value.single),
              ),
            ),
            const SizedBox(height: 8),
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
            if (_entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton.icon(
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('履歴を削除'),
                ),
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
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.title),
        content: Text(entry.summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
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
