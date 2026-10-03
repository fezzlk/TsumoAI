import 'package:flutter/material.dart';

import '../models/score_request.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/section_list.dart';
import '../widgets/status_banner.dart';

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

  void _updateRules(RuleSet rules) => _update(_settings.copyWith(rules: rules));

  @override
  Widget build(BuildContext context) {
    final rules = _settings.rules;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: '麻雀ルール'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.xl,
                ),
                children: [
                  Text('ここで選んだルールを、点数計算と対局に使用します。', style: text.bodySmall),
                  const SectionLabel('計算ルール'),
                  SectionGroup(
                    children: [
                      _choiceRow<bool>(
                        '赤牌',
                        rules.akaAri,
                        const [(true, 'あり'), (false, 'なし')],
                        (value) => _updateRules(rules.copyWith(akaAri: value)),
                      ),
                      _choiceRow<bool>(
                        '喰いタン',
                        rules.kuitanAri,
                        const [(true, 'あり'), (false, 'なし')],
                        (value) =>
                            _updateRules(rules.copyWith(kuitanAri: value)),
                      ),
                      _choiceRow<bool>(
                        'ダブル役満',
                        rules.doubleYakumanAri,
                        const [(true, 'あり'), (false, 'なし')],
                        (value) => _updateRules(
                          rules.copyWith(doubleYakumanAri: value),
                        ),
                      ),
                      _choiceRow<bool>(
                        '数え役満',
                        rules.kazoeYakumanAri,
                        const [(true, 'あり'), (false, 'なし')],
                        (value) => _updateRules(
                          rules.copyWith(kazoeYakumanAri: value),
                        ),
                      ),
                      _choiceRow<int>(
                        '連風牌の雀頭',
                        rules.renpuFu,
                        const [(4, '4符'), (2, '2符')],
                        (value) => _updateRules(rules.copyWith(renpuFu: value)),
                      ),
                    ],
                  ),
                  const SectionLabel('対局・精算'),
                  SectionGroup(
                    children: [
                      _switchRow(
                        'トビ終了',
                        '持ち点がマイナスで終了。0点は続行',
                        _settings.tobiEnd,
                        (value) => _update(_settings.copyWith(tobiEnd: value)),
                      ),
                      _switchRow(
                        'チップ',
                        '点棒とは別にチップ点を計算',
                        _settings.chipsEnabled,
                        (value) =>
                            _update(_settings.copyWith(chipsEnabled: value)),
                      ),
                      if (_settings.chipsEnabled) ...[
                        _switchRow(
                          '副露ありでも有効',
                          '副露した和了も赤牌・オールスターを加算',
                          _settings.openHandChipsEnabled,
                          (value) => _update(
                            _settings.copyWith(openHandChipsEnabled: value),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.l,
                            AppSpacing.s,
                            AppSpacing.l,
                            AppSpacing.l,
                          ),
                          child: Text(
                            '赤牌・裏ドラは1枚につき1、一発は1、赤牌3枚のオールスターは追加2。'
                            '1チップ点は素点1,000点相当です。',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.l),
                  const StatusBanner(
                    kind: StatusKind.success,
                    message: '変更は自動で保存されます。ログイン中はアカウントにも同期します',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow<T>(
    String title,
    T value,
    List<(T, String)> options,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.l,
      vertical: AppSpacing.m,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        _Segmented<T>(value: value, options: options, onChanged: onChanged),
      ],
    ),
  );

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
}

/// Two-choice control from the rules design: soft track, filled selection.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (option, label) in options)
            Semantics(
              button: true,
              selected: option == value,
              child: Material(
                color: option == value ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.iconTile),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.iconTile),
                  onTap: () => onChanged(option),
                  child: SizedBox(
                    width: 64,
                    height: 44,
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: option == value
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
