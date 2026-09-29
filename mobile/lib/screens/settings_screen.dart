import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/score_request.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import 'history_screen.dart';
import 'mahjong_rules_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.autoClassify,
    required this.onAutoClassifyChanged,
    required this.showTrainingDataActions,
    required this.onShowTrainingDataActionsChanged,
    required this.ruleSettings,
    required this.onRuleSettingsChanged,
  });

  final bool autoClassify;
  final ValueChanged<bool> onAutoClassifyChanged;
  final bool showTrainingDataActions;
  final ValueChanged<bool> onShowTrainingDataActionsChanged;
  final MahjongRuleSettings ruleSettings;
  final ValueChanged<MahjongRuleSettings> onRuleSettingsChanged;

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
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            SwitchListTile(
              title: const Text('撮影後に自動識別'),
              subtitle: const Text('位置検出後、そのまま牌の種類を識別します'),
              value: _autoClassify,
              onChanged: (value) {
                setState(() => _autoClassify = value);
                widget.onAutoClassifyChanged(value);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.grid_view_outlined),
              title: const Text('麻雀ルール'),
              subtitle: const Text('計算・対局・チップのルール'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MahjongRulesScreen(
                    settings: widget.ruleSettings,
                    onChanged: widget.onRuleSettingsChanged,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('利用履歴'),
              subtitle: const Text('結果とAIとの会話'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('利用履歴を削除'),
              subtitle: Text(
                AuthService.currentUser == null
                    ? 'この端末の結果履歴とAI会話を削除'
                    : 'このアカウントに紐づく全端末の結果履歴とAI会話を削除',
              ),
              onTap: _confirmDeleteHistory,
            ),
            const ListTile(
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('AI利用状況・残り枠'),
              subtitle: Text('利用状況画面は後続バッチで接続します'),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('使い方・ヘルプ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showHelp(context),
            ),
            const ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('利用規約'),
              trailing: Icon(Icons.chevron_right),
            ),
            const ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('プライバシーポリシー'),
              trailing: Icon(Icons.chevron_right),
            ),
            const ListTile(
              leading: Icon(Icons.mail_outline),
              title: Text('問い合わせ'),
              trailing: Icon(Icons.chevron_right),
            ),
            if (_checkingAdmin)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              )
            else if (_isAdmin) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('開発者設定'),
                subtitle: const Text('学習データ作成・管理機能'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeveloperSettingsScreen(
                      showTrainingDataActions: _showTrainingDataActions,
                      onShowTrainingDataActionsChanged: (value) {
                        setState(() => _showTrainingDataActions = value);
                        widget.onShowTrainingDataActionsChanged(value);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showHelp(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const AlertDialog(
      title: Text('使い方'),
      content: Text(
        'ホームで目的を選び、牌をカメラに収めます。認識結果では牌・枚数・条件を訂正でき、結果へすぐ反映されます。\n\n'
        '「実際の対局進行に合わせて点数計算を行う」では、1台の端末で局・親・本場を管理できます。',
      ),
    ),
  );

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
  late final Future<bool> _authorization = AuthService.isAdmin(
    forceRefresh: true,
  );

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
              SwitchListTile(
                title: const Text('学習データ作成ボタンを表示'),
                subtitle: const Text('ホームの1枚撮影と、認識結果の訂正データ送信を表示します'),
                value: _showTrainingDataActions,
                onChanged: (value) {
                  setState(() => _showTrainingDataActions = value);
                  widget.onShowTrainingDataActionsChanged(value);
                },
              ),
              const ListTile(
                leading: Icon(Icons.chat_outlined),
                title: Text('AIチャットテンプレート管理'),
                subtitle: Text('管理画面は後続実装で接続します'),
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
