import 'package:flutter/material.dart';

import '../models/official_ai_chat_template.dart';
import '../services/official_ai_chat_template_service.dart';

class AIChatTemplateAdminScreen extends StatefulWidget {
  const AIChatTemplateAdminScreen({super.key, this.service});

  final OfficialAIChatTemplateService? service;

  @override
  State<AIChatTemplateAdminScreen> createState() =>
      _AIChatTemplateAdminScreenState();
}

class _AIChatTemplateAdminScreenState extends State<AIChatTemplateAdminScreen> {
  late final OfficialAIChatTemplateService _service =
      widget.service ?? OfficialAIChatTemplateService();
  OfficialAIChatTemplateConfig? _config;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _service.load();
    if (!mounted) return;
    setState(() => _config = config);
  }

  Future<void> _publish(List<OfficialAIChatTemplate> items) async {
    if (_saving) return;
    final previous = _config;
    setState(() {
      _saving = true;
      _error = null;
      _config = OfficialAIChatTemplateConfig(
        version: previous?.version ?? 1,
        updatedAt: previous?.updatedAt,
        items: items,
      );
    });
    try {
      final saved = await _service.publish(items);
      if (mounted) setState(() => _config = saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _config = previous;
          _error = '公開できませんでした。通信状態と管理者権限を確認してください。';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<OfficialAIChatTemplate> _kindItems(String kind) {
    final items =
        _config?.items.where((item) => item.kind == kind).toList() ?? [];
    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return items;
  }

  Future<void> _move(OfficialAIChatTemplate item, int delta) async {
    final sameKind = _kindItems(item.kind);
    final current = sameKind.indexWhere((candidate) => candidate.id == item.id);
    final target = current + delta;
    if (current == -1 || target < 0 || target >= sameKind.length) return;
    final reordered = [...sameKind];
    final moved = reordered.removeAt(current);
    reordered.insert(target, moved);
    final orders = {
      for (var i = 0; i < reordered.length; i++) reordered[i].id: i,
    };
    await _publish([
      for (final candidate in _config!.items)
        if (orders.containsKey(candidate.id))
          candidate.copyWith(sortOrder: orders[candidate.id])
        else
          candidate,
    ]);
  }

  Future<void> _edit([OfficialAIChatTemplate? existing]) async {
    final item = await _showEditor(existing);
    if (item == null || _config == null) return;
    final items = [..._config!.items];
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await _publish(items);
  }

  Future<OfficialAIChatTemplate?> _showEditor(
    OfficialAIChatTemplate? existing,
  ) {
    var kind = existing?.kind ?? 'question';
    var purpose = existing?.purpose ?? 'discard';
    final label = TextEditingController(text: existing?.label);
    final body = TextEditingController(text: existing?.body);
    return showDialog<OfficialAIChatTemplate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'テンプレートを追加' : 'テンプレートを編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'question', label: Text('質問')),
                    ButtonSegment(value: 'situation', label: Text('状況')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (value) => setDialogState(() {
                    kind = value.first;
                    if (kind == 'situation') purpose = 'all';
                  }),
                ),
                const SizedBox(height: 12),
                if (kind == 'question')
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'discard', label: Text('何切る')),
                      ButtonSegment(value: 'call_advice', label: Text('鳴き')),
                      ButtonSegment(value: 'all', label: Text('共通')),
                    ],
                    selected: {purpose},
                    onSelectionChanged: (value) =>
                        setDialogState(() => purpose = value.first),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: '表示名'),
                ),
                TextField(
                  controller: body,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: kind == 'question' ? '質問文' : 'AIへ渡す状況',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                if (label.text.trim().isEmpty || body.text.trim().isEmpty) {
                  return;
                }
                final kindCount = _kindItems(kind).length;
                Navigator.pop(
                  dialogContext,
                  OfficialAIChatTemplate(
                    id:
                        existing?.id ??
                        '$kind-${DateTime.now().microsecondsSinceEpoch}',
                    kind: kind,
                    purpose: kind == 'situation' ? 'all' : purpose,
                    label: label.text.trim(),
                    body: body.text.trim(),
                    enabled: existing?.enabled ?? true,
                    sortOrder: existing?.sortOrder ?? kindCount,
                  ),
                );
              },
              child: const Text('公開'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      label.dispose();
      body.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIチャットテンプレート'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('追加'),
      ),
      body: SafeArea(
        child: config == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (_error != null)
                    MaterialBanner(
                      content: Text(_error!),
                      actions: [
                        TextButton(
                          onPressed: _load,
                          child: const Text('再読み込み'),
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '公開バージョン ${config.version}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _section('状況', _kindItems('situation')),
                  _section('質問の型', _kindItems('question')),
                ],
              ),
      ),
    );
  }

  Widget _section(String title, List<OfficialAIChatTemplate> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      for (var index = 0; index < items.length; index++)
        ListTile(
          title: Text(items[index].label),
          subtitle: Text(
            items[index].kind == 'question'
                ? '${_purposeLabel(items[index].purpose)}・${items[index].body}'
                : items[index].body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Switch(
            value: items[index].enabled,
            onChanged: _saving
                ? null
                : (enabled) => _publish([
                    for (final candidate in _config!.items)
                      candidate.id == items[index].id
                          ? candidate.copyWith(enabled: enabled)
                          : candidate,
                  ]),
          ),
          trailing: PopupMenuButton<String>(
            enabled: !_saving,
            onSelected: (action) {
              if (action == 'up') _move(items[index], -1);
              if (action == 'down') _move(items[index], 1);
              if (action == 'edit') _edit(items[index]);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'up',
                enabled: index > 0,
                child: const Text('上へ移動'),
              ),
              PopupMenuItem(
                value: 'down',
                enabled: index < items.length - 1,
                child: const Text('下へ移動'),
              ),
              const PopupMenuItem(value: 'edit', child: Text('編集')),
            ],
          ),
        ),
    ],
  );
}

String _purposeLabel(String value) => switch (value) {
  'discard' => '何切る',
  'call_advice' => '鳴き判断',
  _ => '共通',
};
