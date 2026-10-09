import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/score_request.dart';
import '../services/auth_service.dart';
import '../services/app_preferences.dart';
import '../services/diagnostic_log.dart';
import '../services/scan_diagnostics_client.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/section_list.dart';
import 'help_screen.dart';
import 'mahjong_rules_screen.dart';
import 'ai_chat_template_admin_screen.dart';
import 'ai_usage_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.autoClassify,
    required this.onAutoClassifyChanged,
    required this.showTrainingDataActions,
    required this.onShowTrainingDataActionsChanged,
    required this.ruleSettings,
    required this.onRuleSettingsChanged,
    this.onAuthenticationChanged,
  });

  final bool autoClassify;
  final ValueChanged<bool> onAutoClassifyChanged;
  final bool showTrainingDataActions;
  final ValueChanged<bool> onShowTrainingDataActionsChanged;
  final MahjongRuleSettings ruleSettings;
  final ValueChanged<MahjongRuleSettings> onRuleSettingsChanged;

  /// Re-synchronizes account-bound settings after signing in or out.
  final Future<void> Function()? onAuthenticationChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _autoClassify;
  late bool _showTrainingDataActions;
  bool _checkingAdmin = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _autoClassify = widget.autoClassify;
    _showTrainingDataActions = widget.showTrainingDataActions;
    _loadAdminClaim();
  }

  Future<void> _loadAdminClaim() async {
    final isAdmin = await AuthService.isAdmin(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _checkingAdmin = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: '設定'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.xl,
                ),
                children: [
                  _buildAccountCard(context),
                  const SectionLabel('利用データ'),
                  SectionGroup(
                    children: [
                      SectionTile(
                        mark: 'AI',
                        title: 'AI利用状況・残り枠',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AIUsageScreen(),
                          ),
                        ),
                      ),
                      SectionTile(
                        mark: '消',
                        title: '利用履歴を削除',
                        subtitle: AuthService.currentUser == null
                            ? 'この端末の結果履歴とAI会話を削除'
                            : 'このアカウントに紐づく全端末の結果履歴とAI会話を削除',
                        destructive: true,
                        trailing: const SizedBox.shrink(),
                        onTap: _confirmDeleteHistory,
                      ),
                    ],
                  ),
                  const SectionLabel('アプリ設定'),
                  SectionGroup(
                    children: [
                      SectionTile(
                        mark: '識',
                        title: '撮影後に自動識別',
                        subtitle: '位置検出後、そのまま牌の種類を識別します',
                        trailing: Switch(
                          value: _autoClassify,
                          onChanged: _setAutoClassify,
                        ),
                        onTap: () => _setAutoClassify(!_autoClassify),
                      ),
                      SectionTile(
                        mark: '牌',
                        title: '麻雀ルール',
                        subtitle: '計算・対局・チップのルール',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MahjongRulesScreen(
                              settings: widget.ruleSettings,
                              onChanged: widget.onRuleSettingsChanged,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SectionLabel('サポート'),
                  SectionGroup(
                    children: [
                      SectionTile(
                        mark: '?',
                        title: '使い方・ヘルプ',
                        subtitle: '撮影方法と各機能の使い方',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => HelpScreen(
                              onContact: () => _openExternalPage('/contact'),
                            ),
                          ),
                        ),
                      ),
                      SectionTile(
                        mark: '問',
                        title: '問い合わせ',
                        onTap: () => _openExternalPage('/contact'),
                      ),
                      SectionTile(
                        mark: '規',
                        title: '利用規約',
                        onTap: () => _openExternalPage('/terms'),
                      ),
                      SectionTile(
                        mark: '個',
                        title: 'プライバシーポリシー',
                        onTap: () => _openExternalPage('/privacy'),
                      ),
                    ],
                  ),
                  if (_checkingAdmin)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.l),
                      child: LinearProgressIndicator(),
                    )
                  else if (_isAdmin) ...[
                    const SectionLabel('開発者'),
                    SectionGroup(
                      children: [
                        SectionTile(
                          mark: '開',
                          title: '開発者設定',
                          subtitle: '許可されたアカウントにのみ表示',
                          developer: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DeveloperSettingsScreen(
                                showTrainingDataActions:
                                    _showTrainingDataActions,
                                onShowTrainingDataActionsChanged: (value) {
                                  setState(
                                    () => _showTrainingDataActions = value,
                                  );
                                  widget.onShowTrainingDataActionsChanged(
                                    value,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (AuthService.currentUser != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    OutlinedButton(
                      style: destructiveOutlinedButtonStyle(context),
                      onPressed: _signOut,
                      child: const Text('ログアウト'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setAutoClassify(bool value) {
    setState(() => _autoClassify = value);
    widget.onAutoClassifyChanged(value);
  }

  Widget _buildAccountCard(BuildContext context) {
    final user = AuthService.currentUser;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.feature),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: user == null
                ? const Icon(Icons.person_outline)
                : Text(
                    (user.email ?? 'U').characters.first.toUpperCase(),
                    style: text.titleMedium?.copyWith(color: scheme.onPrimary),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user == null ? 'ログインしていません' : 'ログイン中',
                  style: text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? 'ログインすると利用履歴をアカウントに保存し、AI相談を使えます',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          if (user == null) ...[
            const SizedBox(width: AppSpacing.s),
            OutlinedButton(onPressed: _signIn, child: const Text('ログイン')),
          ],
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    try {
      await AuthService.ensureSignedIn();
      await widget.onAuthenticationChanged?.call();
      if (!mounted) return;
      setState(() {});
      await _loadAdminClaim();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログインに失敗しました: $error')));
    }
  }

  Future<void> _signOut() async {
    try {
      await AuthService.signOut();
      await widget.onAuthenticationChanged?.call();
      if (!mounted) return;
      setState(() => _isAdmin = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ログアウトしました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログアウトに失敗しました: $error')));
    }
  }

  Future<void> _openExternalPage(String path) async {
    final opened = await launchUrl(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ページを開けませんでした。通信状態を確認してください。')),
    );
  }

  Future<void> _confirmDeleteHistory() async {
    final signedIn = AuthService.currentUser != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('利用履歴を削除しますか？'),
        content: Text(
          signedIn
              ? 'このアカウントに紐づく全端末の結果履歴とAI会話を削除します。アカウントや送信済み学習データは削除しません。'
              : 'この端末に保存された結果履歴とAI会話を削除します。アカウントや送信済み学習データは削除しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await HistoryService().deleteAll();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('利用履歴を削除しました')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            signedIn
                ? '同期済みの利用履歴を削除できませんでした。通信状態を確認してください。'
                : '利用履歴を削除できませんでした。',
          ),
        ),
      );
    }
  }
}

class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({
    super.key,
    required this.showTrainingDataActions,
    required this.onShowTrainingDataActionsChanged,
  });

  final bool showTrainingDataActions;
  final ValueChanged<bool> onShowTrainingDataActionsChanged;

  @override
  State<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  late bool _showTrainingDataActions = widget.showTrainingDataActions;
  bool _scanDiagnosticsEnabled = false;
  Duration _logPeriod = const Duration(hours: 24);
  bool _sendingLogs = false;
  late final Future<bool> _authorization = AuthService.isAdmin(
    forceRefresh: true,
  );

  @override
  void initState() {
    super.initState();
    AppPreferences.scanDiagnosticsEnabled().then((enabled) {
      if (mounted) setState(() => _scanDiagnosticsEnabled = enabled);
    });
  }

  Future<void> _sendLogs() async {
    if (_sendingLogs) return;
    final end = DateTime.now().toUtc();
    final start = end.subtract(_logPeriod);
    setState(() => _sendingLogs = true);
    try {
      await DiagnosticLog.instance.record(DiagnosticEvent.logsUploadRequested);
      final entries = await DiagnosticLog.instance.entriesBetween(start, end);
      if (entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('選択した期間のログはありません')));
        }
        return;
      }
      final logId = await ScanDiagnosticsClient().uploadLogs(
        periodStart: start,
        periodEnd: end,
        entries: entries,
      );
      unawaited(
        DiagnosticLog.instance.record(
          DiagnosticEvent.logsUploadSucceeded,
          count: entries.length,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${entries.length}件を送信しました（ID: ${logId.substring(0, 8)}）',
            ),
          ),
        );
      }
    } catch (error) {
      unawaited(
        DiagnosticLog.instance.record(
          DiagnosticEvent.logsUploadFailed,
          error: error,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログを送信できませんでした。通信状態と権限を確認してください。')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingLogs = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('開発者設定')),
    body: SafeArea(
      child: FutureBuilder<bool>(
        future: _authorization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data != true) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    const Text('開発者権限を確認できませんでした'),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('設定に戻る'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            children: [
              const ListTile(
                title: Text('操作・エラーログ'),
                subtitle: Text(
                  '端末内に直近7日・最大2000件を保存します。画面操作、認識の処理段階、エラーの種類を記録します。画像・会話・入力内容は含めません。クラウドには「ログを送信」を押した時だけ送信します。',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<Duration>(
                  initialValue: _logPeriod,
                  decoration: const InputDecoration(labelText: '送信する期間'),
                  items: const [
                    DropdownMenuItem(
                      value: Duration(hours: 1),
                      child: Text('直近1時間'),
                    ),
                    DropdownMenuItem(
                      value: Duration(hours: 24),
                      child: Text('直近24時間'),
                    ),
                    DropdownMenuItem(
                      value: Duration(days: 7),
                      child: Text('直近7日'),
                    ),
                  ],
                  onChanged: _sendingLogs
                      ? null
                      : (value) {
                          if (value != null) setState(() => _logPeriod = value);
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _sendingLogs ? null : _sendLogs,
                  icon: _sendingLogs
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: Text(_sendingLogs ? '送信中…' : 'ログを送信'),
                ),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('撮影の診断記録を保存'),
                subtitle: const Text(
                  'この端末で撮影した元画像・枠画像・検出ログをクラウドへ保存します。オフでは送信しません。',
                ),
                value: _scanDiagnosticsEnabled,
                onChanged: (value) async {
                  await AppPreferences.setScanDiagnosticsEnabled(value);
                  if (mounted) setState(() => _scanDiagnosticsEnabled = value);
                },
              ),
              SwitchListTile(
                title: const Text('学習データ作成ボタンを表示'),
                subtitle: const Text('ホームの1枚撮影と、認識結果の訂正データ送信を表示します'),
                value: _showTrainingDataActions,
                onChanged: (value) {
                  setState(() => _showTrainingDataActions = value);
                  widget.onShowTrainingDataActionsChanged(value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('AIチャットテンプレート管理'),
                subtitle: const Text('状況と質問の型を公開'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AIChatTemplateAdminScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('Web管理ダッシュボードを開く'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(
                  Uri.parse(AppConfig.apiBaseUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
