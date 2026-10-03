import 'package:flutter/material.dart';

import '../models/official_ai_chat_template.dart';
import '../services/official_ai_chat_template_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/status_banner.dart';

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

  /// Tab shown: 'situation' (状況) or 'question' (質問の型).
  String _kind = 'situation';

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
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final situation = _kind == 'situation';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'AIテンプレート',
              subtitle: '開発者設定',
              trailing: config == null
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.developer.container,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'v${config.version}',
                        style: text.labelMedium?.copyWith(
                          color: colors.developer.onContainer,
                        ),
                      ),
                    ),
            ),
            if (_saving) const LinearProgressIndicator(),
            Expanded(
              child: config == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      children: [
                        if (_error != null) ...[
                          StatusBanner(
                            kind: StatusKind.error,
                            message: _error!,
                            action: TextButton(
                              onPressed: _load,
                              child: const Text('再読み込み'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.m),
                        ],
                        _kindTabs(),
                        const SizedBox(height: AppSpacing.l),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    situation ? '状況テンプレート' : '質問の型テンプレート',
                                    style: text.titleMedium,
                                  ),
                                  Text(
                                    situation
                                        ? 'AIへ渡す卓況を複数選択できます'
                                        : 'タップで質問文を入力欄に入れます',
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _saving ? null : () => _edit(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('追加'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.m),
                        ..._rows(_kindItems(_kind)),
                        const SizedBox(height: AppSpacing.s),
                        Text(
                          '並べ替え・表示変更・追加内容は保存時に新しいversionとして公開され、アプリは次回取得時に反映します。',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindTabs() {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String kind, String label) {
      final selected = _kind == kind;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _kind = kind),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.surface : null,
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(children: [tab('situation', '状況'), tab('question', '質問の型')]),
    );
  }

  List<Widget> _rows(List<OfficialAIChatTemplate> items) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return [
      for (var index = 0; index < items.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                PopupMenuButton<int>(
                  enabled: !_saving,
                  tooltip: '並べ替え',
                  icon: Icon(Icons.drag_handle, color: scheme.onSurfaceVariant),
                  onSelected: (delta) => _move(items[index], delta),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: -1,
                      enabled: index > 0,
                      child: const Text('上へ移動'),
                    ),
                    PopupMenuItem(
                      value: 1,
                      enabled: index < items.length - 1,
                      child: const Text('下へ移動'),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[index].label, style: text.titleSmall),
                      Text(
                        items[index].kind == 'question'
                            ? '${_purposeLabel(items[index].purpose)}・${items[index].body}'
                            : items[index].body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _edit(items[index]),
                  child: const Text('編集'),
                ),
                Switch(
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
                const SizedBox(width: AppSpacing.s),
              ],
            ),
          ),
        ),
    ];
  }
}

String _purposeLabel(String value) => switch (value) {
  'discard' => '何切る',
  'call_advice' => '鳴き判断',
  _ => '共通',
};
