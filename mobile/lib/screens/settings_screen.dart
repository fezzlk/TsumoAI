import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.autoClassify,
    required this.onAutoClassifyChanged,
    required this.showTrainingDataActions,
    required this.onShowTrainingDataActionsChanged,
  });

  final bool autoClassify;
  final ValueChanged<bool> onAutoClassifyChanged;
  final bool showTrainingDataActions;
  final ValueChanged<bool> onShowTrainingDataActionsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _autoClassify;
  late bool _showTrainingDataActions;

  @override
  void initState() {
    super.initState();
    _autoClassify = widget.autoClassify;
    _showTrainingDataActions = widget.showTrainingDataActions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定・規約')),
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
            SwitchListTile(
              title: const Text('学習データ作成ボタンを表示'),
              subtitle: const Text('ホームの1枚撮影と、認識結果の訂正データ送信を表示します'),
              value: _showTrainingDataActions,
              onChanged: (value) {
                setState(() => _showTrainingDataActions = value);
                widget.onShowTrainingDataActionsChanged(value);
              },
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('AI利用状況・残り枠'),
              subtitle: Text('利用状況画面は後続バッチで接続します'),
            ),
            const ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('利用規約・プライバシー'),
            ),
            const ListTile(
              leading: Icon(Icons.help_outline),
              title: Text('問い合わせ'),
            ),
          ],
        ),
      ),
    );
  }
}
