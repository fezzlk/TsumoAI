import 'package:flutter/material.dart';

import '../models/ai_chat_message.dart';
import '../models/question_template.dart';
import '../services/api_client.dart';
import '../services/question_template_service.dart';

typedef AIChatSender =
    Future<String> Function({
      required String message,
      required List<AIChatMessage> conversation,
      required List<String> situationTags,
    });

class AIChatSheet extends StatefulWidget {
  const AIChatSheet({
    super.key,
    required this.purpose,
    required this.tiles,
    required this.roundContext,
    required this.analysis,
    this.initialMessages = const [],
    this.onMessagesChanged,
    this.sender,
    this.templateService,
  });

  final String purpose;
  final List<String> tiles;
  final Map<String, dynamic> roundContext;
  final Map<String, dynamic> analysis;
  final List<AIChatMessage> initialMessages;
  final ValueChanged<List<AIChatMessage>>? onMessagesChanged;
  final AIChatSender? sender;
  final QuestionTemplateService? templateService;

  static Future<void> show(
    BuildContext context, {
    required String purpose,
    required List<String> tiles,
    required Map<String, dynamic> roundContext,
    required Map<String, dynamic> analysis,
    List<AIChatMessage> initialMessages = const [],
    ValueChanged<List<AIChatMessage>>? onMessagesChanged,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: AIChatSheet(
        purpose: purpose,
        tiles: tiles,
        roundContext: roundContext,
        analysis: analysis,
        initialMessages: initialMessages,
        onMessagesChanged: onMessagesChanged,
      ),
    ),
  );

  @override
  State<AIChatSheet> createState() => _AIChatSheetState();
}

class _AIChatSheetState extends State<AIChatSheet> {
  static const _situationOptions = [
    '親リーチ',
    'オーラス',
    'トップ目',
    'ラス目',
    '守備優先',
    '打点優先',
    '着順UP',
  ];

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final QuestionTemplateService _templateService;
  late List<AIChatMessage> _messages;
  List<QuestionTemplate> _templates = [];
  final Set<String> _situationTags = {};
  bool _sending = false;
  String? _error;

  List<String> get _starterQuestions => widget.purpose == 'call_advice'
      ? const ['鳴くべき？', '見送るべき？', '判断が変わる条件は？']
      : const ['何を切る？', '押す？降りる？', '理由を詳しく教えて'];

  @override
  void initState() {
    super.initState();
    _templateService = widget.templateService ?? QuestionTemplateService();
    _messages = [...widget.initialMessages];
    _loadTemplates();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final templates = await _templateService.loadLocal();
    if (mounted) setState(() => _templates = templates);
  }

  Future<String> _sendToApi(String message, List<AIChatMessage> conversation) {
    if (widget.sender case final sender?) {
      return sender(
        message: message,
        conversation: conversation,
        situationTags: _situationTags.toList(),
      );
    }
    return ApiClient().askAi(
      message: message,
      conversation: conversation,
      purpose: widget.purpose,
      tiles: widget.tiles,
      roundContext: widget.roundContext,
      analysis: widget.analysis,
      situationTags: _situationTags.toList(),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final previous = [..._messages];
    setState(() {
      _messages.add(AIChatMessage(role: 'user', content: text));
      _controller.clear();
      _sending = true;
      _error = null;
    });
    _notifyChanged();
    _scrollToEnd();
    try {
      final answer = await _sendToApi(text, previous);
      if (!mounted) return;
      setState(() {
        _messages.add(AIChatMessage(role: 'assistant', content: answer));
        _sending = false;
      });
      _notifyChanged();
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.role == 'user' &&
            _messages.last.content == text) {
          _messages.removeLast();
        }
        _sending = false;
        _error = '回答を取得できませんでした。通信状態を確認して再送してください。';
        _controller.text = text;
      });
      _notifyChanged();
    }
  }

  void _notifyChanged() => widget.onMessagesChanged?.call(
    List<AIChatMessage>.unmodifiable(_messages),
  );

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  });

  bool _isSaved(String body) =>
      _templates.any((item) => !item.deleted && item.body == body.trim());

  Future<void> _saveSentMessage(String body) async {
    if (_isSaved(body)) return;
    try {
      await _templateService.saveSentMessage(body);
      await _loadTemplates();
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('テンプレートは20件まで保存できます')));
      }
    }
  }

  Future<void> _addTemplate() async {
    final name = TextEditingController();
    final body = TextEditingController(text: _controller.text);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('質問テンプレートを追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名前'),
            ),
            TextField(
              controller: body,
              decoration: const InputDecoration(labelText: '質問文'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('追加'),
          ),
        ],
      ),
    );
    if (accepted == true && body.text.trim().isNotEmpty) {
      final saved = await _templateService.saveSentMessage(body.text);
      if (name.text.trim().isNotEmpty) {
        await _templateService.update(
          id: saved.id,
          name: name.text,
          body: saved.body,
        );
      }
      await _loadTemplates();
    }
    name.dispose();
    body.dispose();
  }

  Future<void> _editTemplate(QuestionTemplate template) async {
    final name = TextEditingController(text: template.name);
    final body = TextEditingController(text: template.body);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('テンプレートを編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名前'),
            ),
            TextField(
              controller: body,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '質問文'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _templateService.update(
        id: template.id,
        name: name.text,
        body: body.text,
      );
      await _loadTemplates();
    }
    name.dispose();
    body.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'AIに質問',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          children: [
            const Text('状況', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final tag in _situationOptions)
                  FilterChip(
                    label: Text(tag),
                    selected: _situationTags.contains(tag),
                    onSelected: (selected) => setState(() {
                      selected
                          ? _situationTags.add(tag)
                          : _situationTags.remove(tag);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final question in _starterQuestions)
                  ActionChip(
                    label: Text(question),
                    onPressed: () => _controller.text = question,
                  ),
                for (final template in _templates)
                  InputChip(
                    avatar: Tooltip(
                      message: '編集',
                      child: InkWell(
                        onTap: () => _editTemplate(template),
                        child: const Icon(Icons.edit_outlined, size: 17),
                      ),
                    ),
                    label: Text(template.name),
                    onPressed: () => _controller.text = template.body,
                    onDeleted: () async {
                      await _templateService.delete(template.id);
                      await _loadTemplates();
                    },
                    deleteIcon: const Icon(Icons.close, size: 17),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('自分用を追加'),
                  onPressed: _addTemplate,
                ),
              ],
            ),
            const Divider(height: 24),
            if (_messages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('質問を選ぶか、自由に入力してください')),
              ),
            for (final message in _messages)
              _MessageBubble(
                message: message,
                saved: message.role == 'user' && _isSaved(message.content),
                onSave: message.role == 'user'
                    ? () => _saveSentMessage(message.content)
                    : null,
              ),
            if (_sending)
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: '状況や聞きたいことを入力'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                tooltip: '送信',
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.saved,
    this.onSave,
  });

  final AIChatMessage message;
  final bool saved;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.content),
            if (isUser) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: saved ? null : onSave,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  saved ? Icons.check : Icons.bookmark_add_outlined,
                  size: 16,
                ),
                label: Text(saved ? '保存済み' : 'テンプレートとして保存'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
