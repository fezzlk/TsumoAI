import 'package:flutter/material.dart';

import '../models/score_request.dart';

class MahjongRulesScreen extends StatefulWidget {
  const MahjongRulesScreen({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final MahjongRuleSettings settings;
  final ValueChanged<MahjongRuleSettings> onChanged;

  @override
  State<MahjongRulesScreen> createState() => _MahjongRulesScreenState();
}

class _MahjongRulesScreenState extends State<MahjongRulesScreen> {
  late MahjongRuleSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(MahjongRuleSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  void _updateRules(RuleSet rules) =>
      _update(_settings.copyWith(rules: rules));

  @override
  Widget build(BuildContext context) {
    final rules = _settings.rules;
    return Scaffold(
      appBar: AppBar(title: const Text('麻雀ルール')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text('ここで選んだルールを、点数計算と対局に使用します。'),
            ),
            _sectionLabel('計算ルール'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('赤牌'),
                    value: rules.akaAri,
                    onChanged: (value) =>
                        _updateRules(rules.copyWith(akaAri: value)),
                  ),
                  SwitchListTile(
                    title: const Text('喰いタン'),
                    value: rules.kuitanAri,
                    onChanged: (value) =>
                        _updateRules(rules.copyWith(kuitanAri: value)),
                  ),
                  SwitchListTile(
                    title: const Text('ダブル役満'),
                    value: rules.doubleYakumanAri,
                    onChanged: (value) => _updateRules(
                      rules.copyWith(doubleYakumanAri: value),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('数え役満'),
                    value: rules.kazoeYakumanAri,
                    onChanged: (value) => _updateRules(
                      rules.copyWith(kazoeYakumanAri: value),
                    ),
                  ),
                  ListTile(
                    title: const Text('連風牌の雀頭'),
                    trailing: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 4, label: Text('4符')),
                        ButtonSegment(value: 2, label: Text('2符')),
                      ],
                      selected: {rules.renpuFu},
                      onSelectionChanged: (values) => _updateRules(
                        rules.copyWith(renpuFu: values.first),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel('対局・精算'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('トビ終了'),
                    subtitle: const Text('持ち点がマイナスで終了。0点は続行します'),
                    value: _settings.tobiEnd,
                    onChanged: (value) =>
                        _update(_settings.copyWith(tobiEnd: value)),
                  ),
                  SwitchListTile(
                    title: const Text('チップ'),
                    subtitle: const Text('点棒とは別にチップ点を計算します'),
                    value: _settings.chipsEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(chipsEnabled: value)),
                  ),
                  if (_settings.chipsEnabled) ...[
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      title: const Text('副露ありでも有効'),
                      subtitle: const Text('副露した和了も赤牌・オールスターを加算'),
                      value: _settings.openHandChipsEnabled,
                      onChanged: (value) => _update(
                        _settings.copyWith(openHandChipsEnabled: value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                      child: Text(
                        '赤牌・裏ドラは1枚につき1、一発は1、赤牌3枚のオールスターは追加2。'
                        '1チップ点は素点1,000点相当です。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const ListTile(
              leading: Icon(Icons.cloud_done_outlined),
              title: Text('自動保存'),
              subtitle: Text('ログイン中はアカウントにも同期します'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      );
}
