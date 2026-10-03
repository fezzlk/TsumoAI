import 'package:flutter/material.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_usage_status.dart';
import '../models/question_template.dart';
import '../models/official_ai_chat_template.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/question_template_service.dart';
import '../services/official_ai_chat_template_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'status_banner.dart';
import 'toggle_chip.dart';

typedef AIChatSender =
    Future<String> Function({
      required String message,
      required List<AIChatMessage> conversation,
      required List<String> situationTags,
    });
typedef AIUsageLoader = Future<AIUsageStatus> Function();
typedef AISignIn = Future<void> Function();

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
    this.officialTemplateService,
    this.usageLoader,
    this.isSignedIn,
    this.signIn,
    this.initialSituationTags = const [],
    this.initialDraft,
  });

  final String purpose;
  final List<String> tiles;
  final Map<String, dynamic> roundContext;
  final Map<String, dynamic> analysis;
  final List<AIChatMessage> initialMessages;
  final ValueChanged<List<AIChatMessage>>? onMessagesChanged;
  final AIChatSender? sender;
  final QuestionTemplateService? templateService;
  final OfficialAIChatTemplateService? officialTemplateService;
  final AIUsageLoader? usageLoader;

  /// Defaults to the Firebase session; AI chat is login-only.
  final bool Function()? isSignedIn;
  final AISignIn? signIn;
  final List<String> initialSituationTags;
  final String? initialDraft;

  static Future<void> show(
    BuildContext context, {
    required String purpose,
    required List<String> tiles,
    required Map<String, dynamic> roundContext,
    required Map<String, dynamic> analysis,
    List<AIChatMessage> initialMessages = const [],
    ValueChanged<List<AIChatMessage>>? onMessagesChanged,
    List<String> initialSituationTags = const [],
    String? initialDraft,
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
        initialSituationTags: initialSituationTags,
        initialDraft: initialDraft,
      ),
    ),
  );

  @override
  State<AIChatSheet> createState() => _AIChatSheetState();
}

class _AIChatSheetState extends State<AIChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _conversationEndKey = GlobalKey();

  /// Shown as the retry card (ai-error mockup) rather than a banner.
  static const _sendFailedMessage = '回答を取得できませんでした。通信状態を確認して再送してください。';
  late final QuestionTemplateService _templateService;
  late final OfficialAIChatTemplateService _officialTemplateService;
  late List<AIChatMessage> _messages;
  List<QuestionTemplate> _templates = [];
  List<OfficialAIChatTemplate> _officialTemplates =
      OfficialAIChatTemplateService.defaults().items;
  final Set<String> _situationTags = {};
  bool _sending = false;
  bool _syncingTemplates = false;
  bool _templateLoadFailed = false;
  String? _error;
  AIUsageStatus? _usage;
  bool _loadingUsage = false;
  bool _signedIn = false;
  bool _signingIn = false;

  bool get _quotaExhausted => _usage?.exhausted ?? false;
  bool get _canSend => _signedIn && !_quotaExhausted;

  List<OfficialAIChatTemplate> get _situationOptions =>
      _officialTemplates
          .where((item) => item.enabled && item.kind == 'situation')
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<OfficialAIChatTemplate> get _starterQuestions =>
      _officialTemplates
          .where(
            (item) =>
                item.enabled &&
                item.kind == 'question' &&
                (item.purpose == 'all' || item.purpose == widget.purpose),
          )
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  void initState() {
    super.initState();
    _templateService = widget.templateService ?? QuestionTemplateService();
    _officialTemplateService =
        widget.officialTemplateService ?? OfficialAIChatTemplateService();
    _messages = [...widget.initialMessages];
    _situationTags.addAll(widget.initialSituationTags);
    _controller.text = widget.initialDraft ?? '';
    _signedIn = widget.isSignedIn?.call() ?? AuthService.currentUser != null;
    _loadTemplates();
    _loadOfficialTemplates();
    _loadUsage();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final templates = await _templateService.loadLocal();
    if (mounted) {
      setState(() {
        _templates = templates;
        _templateLoadFailed = _templateService.lastLoadFailed;
      });
    }
  }

  Future<void> _retryTemplateSync() async {
    if (_syncingTemplates) return;
    setState(() => _syncingTemplates = true);
    try {
      final templates = await _templateService.synchronize();
      if (mounted) setState(() => _templates = templates);
    } catch (_) {
      _showTemplateMessage('同期できませんでした。端末のテンプレートはそのまま利用できます。');
    } finally {
      if (mounted) setState(() => _syncingTemplates = false);
    }
  }

  Future<void> _loadOfficialTemplates() async {
    final config = await _officialTemplateService.load(refresh: false);
    if (mounted) setState(() => _officialTemplates = config.items);
  }

  Future<void> _loadUsage() async {
    if (!_signedIn) return;
    if (widget.sender != null && widget.usageLoader == null) return;
    if (mounted) setState(() => _loadingUsage = true);
    try {
      final usage =
          await (widget.usageLoader?.call() ?? ApiClient().fetchAiUsage());
      if (mounted) setState(() => _usage = usage);
    } on AILoginRequiredException {
      if (mounted) setState(() => _signedIn = false);
    } catch (_) {
      // The send endpoint still enforces the limit. A temporary status failure
      // must not hide existing conversations or deterministic analysis.
    } finally {
      if (mounted) setState(() => _loadingUsage = false);
    }
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await (widget.signIn?.call() ?? AuthService.ensureSignedIn());
      if (!mounted) return;
      setState(() => _signedIn = true);
      await _loadUsage();
    } catch (_) {
      if (mounted) setState(() => _error = 'ログインできませんでした。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _applyQuestion(OfficialAIChatTemplate question) {
    final situations = _situationTags.toList();
    _controller.text = situations.isEmpty
        ? question.body
        : '${situations.join('、')}の状況です。${question.body}';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
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
    if (text.isEmpty || _sending || !_canSend) return;
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
      await _loadUsage();
    } on AIQuotaExceededException catch (error) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.role == 'user' &&
            _messages.last.content == text) {
          _messages.removeLast();
        }
        _sending = false;
        _usage = error.usage;
        _error = '今月のAI相談枠を使い切りました。基本の計算結果は引き続き利用できます。';
        _controller.text = text;
      });
      _notifyChanged();
    } on AILoginRequiredException {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.role == 'user' &&
            _messages.last.content == text) {
          _messages.removeLast();
        }
        _sending = false;
        _signedIn = false;
        _controller.text = text;
      });
      _notifyChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.role == 'user' &&
            _messages.last.content == text) {
          _messages.removeLast();
        }
        _sending = false;
        _error = _sendFailedMessage;
        _controller.text = text;
      });
      _notifyChanged();
    }
  }

  void _notifyChanged() => widget.onMessagesChanged?.call(
    List<AIChatMessage>.unmodifiable(_messages),
  );

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final end = _conversationEndKey.currentContext;
    if (end == null || !end.mounted) return;
    Scrollable.ensureVisible(
      end,
      alignment: 1,
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
    } on QuestionTemplateTooLongException {
      _showTemplateMessage(
        'テンプレートの質問文は${QuestionTemplate.maxBodyLength}文字までです。',
      );
    } on StateError {
      _showTemplateMessage('テンプレートは20件まで保存できます。既存項目を削除してください。');
    } catch (_) {
      _showTemplateMessage('保存できませんでした。質問文は会話に残っています。');
    }
  }

  void _showTemplateMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              maxLength: QuestionTemplate.maxNameLength,
              decoration: const InputDecoration(labelText: '名前'),
            ),
            TextField(
              controller: body,
              maxLength: QuestionTemplate.maxBodyLength,
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
      try {
        final saved = await _templateService.saveSentMessage(body.text);
        if (name.text.trim().isNotEmpty) {
          await _templateService.update(
            id: saved.id,
            name: name.text,
            body: saved.body,
          );
        }
        await _loadTemplates();
      } on QuestionTemplateTooLongException {
        _controller.text = body.text;
        _showTemplateMessage(
          '名前は${QuestionTemplate.maxNameLength}文字、質問文は${QuestionTemplate.maxBodyLength}文字までです。質問文を入力欄へ戻しました。',
        );
      } on StateError {
        _controller.text = body.text;
        _showTemplateMessage('テンプレートは20件までです。質問文を入力欄へ戻しました。');
      } catch (_) {
        _controller.text = body.text;
        _showTemplateMessage('保存できませんでした。質問文を入力欄へ戻しました。');
      }
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
              maxLength: QuestionTemplate.maxNameLength,
              decoration: const InputDecoration(labelText: '名前'),
            ),
            TextField(
              controller: body,
              maxLength: QuestionTemplate.maxBodyLength,
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
      try {
        await _templateService.update(
          id: template.id,
          name: name.text,
          body: body.text,
        );
        await _loadTemplates();
      } on QuestionTemplateTooLongException {
        _controller.text = body.text;
        _showTemplateMessage(
          '名前は${QuestionTemplate.maxNameLength}文字、質問文は${QuestionTemplate.maxBodyLength}文字までです。質問文を入力欄へ戻しました。',
        );
      } catch (_) {
        _controller.text = body.text;
        _showTemplateMessage('変更を保存できませんでした。質問文を入力欄へ戻しました。');
      }
    }
    name.dispose();
    body.dispose();
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );

  /// One of "自分用テンプレート": tap to fill the input, ••• to edit/delete.
  Widget _templateRow(QuestionTemplate template) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          onTap: () => _controller.text = template.body,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.l),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'テンプレートの操作',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await _editTemplate(template);
                      return;
                    }
                    try {
                      await _templateService.delete(template.id);
                      await _loadTemplates();
                    } catch (_) {
                      _showTemplateMessage('テンプレートを削除できませんでした。');
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('編集')),
                    PopupMenuItem(value: 'delete', child: Text('削除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.m,
            AppSpacing.s,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(child: Text('この手牌について質問', style: text.titleLarge)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: '閉じる',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.xs,
              AppSpacing.l,
              AppSpacing.m,
            ),
            children: [
              if (!_signedIn) ...[
                _LoginRequiredNotice(signingIn: _signingIn, onSignIn: _signIn),
                const SizedBox(height: AppSpacing.m),
              ],
              if (_loadingUsage) const LinearProgressIndicator(),
              if (_usage case final usage?) ...[
                StatusBanner(
                  kind: usage.exhausted ? StatusKind.warning : StatusKind.info,
                  message: usage.exhausted
                      ? '今月のAI相談枠を使い切りました。${usage.resetsAt.month}月1日に更新されます。'
                      : 'AI相談は今月あと${usage.remaining}回利用できます',
                ),
                const SizedBox(height: AppSpacing.m),
              ],
              // The conversation comes first (user-question-template
              // mockup); the chips below compose the next question.
              if (_messages.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
                  child: Center(
                    child: Text(
                      '質問を選ぶか、自由に入力してください',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
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
                    padding: EdgeInsets.all(AppSpacing.m),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (_error == _sendFailedMessage)
                _SendFailedCard(
                  onRetry: _sending || !_canSend ? null : _send,
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s),
                  child: StatusBanner(kind: StatusKind.error, message: _error!),
                ),
              SizedBox(key: _conversationEndKey, height: AppSpacing.l),
              _sectionLabel('状況を追加'),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  for (final selected in _situationTags.where(
                    (selected) => !_situationOptions.any(
                      (option) => option.body == selected,
                    ),
                  ))
                    ToggleChip(
                      label: selected,
                      selected: true,
                      onTap: () =>
                          setState(() => _situationTags.remove(selected)),
                    ),
                  for (final tag in _situationOptions)
                    ToggleChip(
                      label: tag.label,
                      selected: _situationTags.contains(tag.body),
                      onTap: () => setState(() {
                        _situationTags.contains(tag.body)
                            ? _situationTags.remove(tag.body)
                            : _situationTags.add(tag.body);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.l),
              _sectionLabel('質問テンプレート'),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  for (final question in _starterQuestions)
                    ToggleChip(
                      label: question.label,
                      selected: false,
                      onTap: () => _applyQuestion(question),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.l),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('自分用テンプレート', style: text.titleSmall),
                        Text(
                          '端末とアカウントに保存',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addTemplate,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('追加'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              for (final template in _templates) _templateRow(template),
              if (_templates.any((item) => item.pendingSync)) ...[
                const SizedBox(height: AppSpacing.s),
                StatusBanner(
                  kind: StatusKind.warning,
                  message: '未同期のテンプレートがあります',
                  action: TextButton(
                    onPressed: _syncingTemplates ? null : _retryTemplateSync,
                    child: Text(_syncingTemplates ? '同期中' : '再試行'),
                  ),
                ),
              ],
              if (_templateLoadFailed) ...[
                const SizedBox(height: AppSpacing.s),
                StatusBanner(
                  kind: StatusKind.warning,
                  message: '個人テンプレートを読み込めませんでした。自由入力は利用できます。',
                  action: TextButton(
                    onPressed: _loadTemplates,
                    child: const Text('再試行'),
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.s,
              AppSpacing.l,
              AppSpacing.s + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: _canSend,
                    maxLength: ApiClient.aiMessageMaxLength,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '聞きたいことを入力',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Tooltip(
                  message: '送信',
                  child: SizedBox(
                    height: AppSizes.primaryButton,
                    child: FilledButton(
                      key: const ValueKey('ai-chat-send'),
                      onPressed: _sending || !_canSend ? null : _send,
                      child: const Text('送信'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A failed answer: what happened, a retry (the question is still in the
/// input), and a reminder that the calculated result is unaffected.
class _SendFailedCard extends StatelessWidget {
  const _SendFailedCard({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: colors.error.container,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.error.color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.surface,
                    child: Text(
                      '!',
                      style: text.titleMedium?.copyWith(
                        color: colors.error.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AIの回答を取得できませんでした',
                          style: text.titleSmall?.copyWith(
                            color: colors.error.onContainer,
                          ),
                        ),
                        Text('質問内容は保持されています。通信状態を確認してください。', style: muted),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              FilledButton(
                onPressed: onRetry,
                child: const Text('もう一度試す'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: colors.soft,
                child: Icon(Icons.check, size: 15, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('計算結果は利用できます', style: text.titleSmall),
                    Text('閉じると結果の画面へ戻ります', style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginRequiredNotice extends StatelessWidget {
  const _LoginRequiredNotice({required this.signingIn, required this.onSignIn});

  final bool signingIn;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const StatusBanner(
        kind: StatusKind.info,
        message: 'AI相談はログインすると利用できます。基本の計算結果はログインなしで利用できます。',
      ),
      const SizedBox(height: AppSpacing.s),
      FilledButton.icon(
        onPressed: signingIn ? null : onSignIn,
        icon: const Icon(Icons.login),
        label: Text(signingIn ? 'ログイン中' : 'Googleでログイン'),
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
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.l,
        vertical: AppSpacing.m,
      ),
      decoration: BoxDecoration(
        color: isUser ? scheme.primary : colors.soft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: isUser ? null : Border.all(color: colors.recommended.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Text(
              'AI',
              style: text.labelMedium?.copyWith(color: scheme.primary),
            ),
          Text(
            message.content,
            style: text.bodyMedium?.copyWith(
              color: isUser ? scheme.onPrimary : scheme.onSurface,
              fontWeight: isUser ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          if (isUser)
            TextButton.icon(
              onPressed: saved ? null : onSave,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: Icon(saved ? Icons.check : Icons.add, size: 16),
              label: Text(saved ? '保存済み' : 'テンプレートとして保存'),
            ),
        ],
      ),
    );
  }
}
