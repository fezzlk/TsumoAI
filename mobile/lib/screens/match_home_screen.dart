import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

import '../models/match_state.dart';
import '../models/scan_purpose.dart';
import '../models/score_request.dart';
import '../services/tile_assets.dart';
import '../widgets/screen_header.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/tile_image_picker.dart';
import 'scan_screen.dart';

class MatchHomeScreen extends StatefulWidget {
  const MatchHomeScreen({
    super.key,
    required this.cameras,
    required this.autoClassify,
    required this.showTrainingDataActions,
    this.ruleSettings = const MahjongRuleSettings(),
    this.matchState,
    this.onMatchEnded,
  });

  final List<CameraDescription> cameras;
  final bool autoClassify;
  final bool showTrainingDataActions;
  final MahjongRuleSettings ruleSettings;
  final MatchState? matchState;
  final VoidCallback? onMatchEnded;

  @override
  State<MatchHomeScreen> createState() => _MatchHomeScreenState();
}

class _MatchHomeScreenState extends State<MatchHomeScreen> {
  late final MatchState _match = widget.matchState ?? MatchState();
  bool _showDoraTiles = false;

  Future<void> _openScore(TableSeat winner) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          cameras: widget.cameras,
          autoClassify: true,
          purpose: ScanPurpose.score,
          initialContext: _match.current.contextFor(winner),
          winnerOptions: TableSeat.values
              .map(
                (seat) => ScoreWinnerOption(
                  label: _seatLabel(seat),
                  context: _match.current.contextFor(seat),
                ),
              )
              .toList(growable: false),
          initialWinnerIndex: winner.index,
          historyRoundLabel: _match.current.roundLabel,
          showTrainingDataActions: widget.showTrainingDataActions,
          ruleSettings: widget.ruleSettings,
          onScoreConfirmed: (winnerIndex) =>
              setState(() => _match.recordWin(TableSeat.values[winnerIndex])),
        ),
      ),
    );
  }

  Future<void> _openQuickCheck(ScanPurpose purpose) async {
    final referenceSeat = _match.current.dealerSeat;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          cameras: widget.cameras,
          autoClassify: widget.autoClassify,
          purpose: purpose,
          initialContext: _match.current.contextFor(referenceSeat),
          historyRoundLabel: _match.current.roundLabel,
          showTrainingDataActions: widget.showTrainingDataActions,
          ruleSettings: widget.ruleSettings,
        ),
      ),
    );
  }

  Future<void> _recordDraw() async {
    final continues = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Expanded(child: Text('親は継続しますか？')),
            CloseButton(),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('親継続'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('親交代'),
            ),
          ],
        ),
      ),
    );
    if (continues != null) {
      setState(() => _match.recordDraw(dealerContinues: continues));
    }
  }

  Future<void> _confirmEndMatch() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _EndMatchDialog(
        roundLabel: _roundLabel(_match.current),
        completedHands: _match.completedHands,
      ),
    );
    if (shouldEnd != true || !mounted) return;
    widget.onMatchEnded?.call();
    Navigator.pop(context);
  }

  Future<void> _addDora() async {
    if (_match.current.doraIndicators.length >= 4) return;
    final selected = await TileImagePicker.show(
      context,
      title: _showDoraTiles ? 'ドラ牌を選択' : 'ドラ表示牌を選択',
    );
    if (selected == null) return;
    final indicator = _showDoraTiles
        ? doraIndicatorFromTile(selected)
        : selected;
    setState(() {
      _match.setDoraIndicators([..._match.current.doraIndicators, indicator]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _match.current;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: '対局', backLabel: 'ホーム'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.l,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tableCard(state),
                    const SizedBox(height: AppSpacing.l),
                    _sectionHeading(
                      Text('局情報とドラを引き継いで確認', style: text.titleSmall),
                      _carriedSummary(state, muted),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    _quickActions(),
                    const SizedBox(height: AppSpacing.m),
                    SizedBox(
                      height: AppSizes.primaryButton,
                      child: OutlinedButton(
                        key: const ValueKey('end-match-button'),
                        style: destructiveOutlinedButtonStyle(context),
                        onPressed: _confirmEndMatch,
                        child: const Text('対局を終了'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(Widget title, Widget trailing) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpacing.s,
    runSpacing: AppSpacing.xs,
    children: [title, trailing],
  );

  Widget _carriedSummary(MatchSnapshot state, TextStyle? style) {
    final dealer = '親：${_seatCaption(state.dealerSeat)}';
    final label = '${_windLabel(state.roundWind)}${state.handNumber}局・$dealer';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(state.doraIndicators.isEmpty ? label : '$label・表示牌', style: style),
        for (final tile in state.doraIndicators) ...[
          const SizedBox(width: 3),
          SizedBox(width: 16, height: 22, child: TileGlyph(tileCode: tile)),
        ],
      ],
    );
  }

  /// The table: round badge and dora panel in the top corners, the four
  /// seats around a deep-green round plate, and 1局戻す / 流局 below.
  Widget _tableCard(MatchSnapshot state) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.modal),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final plate = width * 0.38;
              final seatWidth = width * 0.27;
              final seatHeight = seatWidth * 0.95;
              // The north seat starts just below the dora panel's top edge;
              // the south seat overhangs the plate by the same amount.
              final plateTop = 56 + seatHeight * 0.6;
              final height = plateTop + plate + seatHeight * 0.6 + 4;
              final centerX = (width - seatWidth) / 2;
              final sideTop = plateTop + plate / 2 - seatHeight / 2;
              return SizedBox(
                height: height,
                child: Stack(
                  children: [
                    // The instruction takes the corner the round badge used
                    // to hold (the separate heading above the card is gone).
                    Positioned(
                      left: 0,
                      top: 0,
                      width: width * 0.58,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              '和了した人の座席をタップ',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      width: width * 0.36,
                      child: _doraPanel(state),
                    ),
                    Positioned(
                      left: (width - plate) / 2,
                      top: plateTop,
                      width: plate,
                      height: plate,
                      child: _roundPlate(state),
                    ),
                    for (final (seat, left, top) in [
                      (
                        TableSeat.opposite,
                        centerX,
                        plateTop - seatHeight * 0.6,
                      ),
                      (TableSeat.left, 0.0, sideTop),
                      (TableSeat.right, width - seatWidth, sideTop),
                      (
                        TableSeat.starting,
                        centerX,
                        plateTop + plate - seatHeight * 0.4,
                      ),
                    ])
                      Positioned(
                        left: left,
                        top: top,
                        width: seatWidth,
                        height: seatHeight,
                        child: _seatButton(seat),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              _tableAction(
                icon: Icons.undo,
                label: '1局戻す',
                onPressed: _match.canUndo ? () => setState(_match.undo) : null,
              ),
              const Spacer(),
              _tableAction(
                icon: Icons.remove,
                label: '流局',
                onPressed: _recordDraw,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurfaceVariant,
        minimumSize: const Size(0, AppSizes.tapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _roundPlate(MatchSnapshot state) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.sessionGradient,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xLarge),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            spreadRadius: 10,
          ),
        ],
      ),
      // The round lives only here (the corner badge was dropped as a
      // duplicate), so it also carries 本場.
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_windLabel(state.roundWind)}${_kanjiNumber(state.handNumber)}局',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: colors.onDark),
              ),
              Text(
                '${state.honba}本場',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onDarkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doraPanel(MatchSnapshot state) {
    final colors = context.appColors;
    final tint = colors.conditional;
    final shownTiles = state.doraIndicators
        .map((tile) => _showDoraTiles ? doraTileFromIndicator(tile) : tile)
        .toList(growable: false);
    Widget segment(String label, bool selected) => Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showDoraTiles = label == 'ドラ牌'),
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.discard.accent : null,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? colors.onDark : tint.onContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: tint.container,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: tint.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              segment('表示牌', !_showDoraTiles),
              segment('ドラ牌', _showDoraTiles),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 3,
            children: [
              for (var index = 0; index < shownTiles.length; index++)
                Tooltip(
                  message: 'ドラを外す',
                  child: GestureDetector(
                    onTap: () => setState(() {
                      final next = [...state.doraIndicators]..removeAt(index);
                      _match.setDoraIndicators(next);
                    }),
                    child: SizedBox(
                      width: 22,
                      height: 30,
                      child: TileGlyph(tileCode: shownTiles[index]),
                    ),
                  ),
                ),
              if (shownTiles.length < 4)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'ドラを追加',
                    onPressed: _addDora,
                    style: IconButton.styleFrom(
                      side: BorderSide(color: colors.discard.accent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                    ),
                    color: colors.discard.accent,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    final colors = context.appColors;
    final items = [
      (ScanPurpose.score, '点', colors.score),
      (ScanPurpose.wait, '待', colors.wait),
      (ScanPurpose.discard, '切', colors.discard),
      (ScanPurpose.callAdvice, '鳴', colors.call),
    ];
    Widget row(int start) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = start; i < start + 2; i++) ...[
            if (i > start) const SizedBox(width: AppSpacing.s),
            Expanded(
              child: _QuickActionTile(
                mark: items[i].$2,
                label: items[i].$1.label,
                colors: items[i].$3,
                onTap: () => _openQuickCheck(items[i].$1),
              ),
            ),
          ],
        ],
      ),
    );
    return Column(
      children: [
        row(0),
        const SizedBox(height: AppSpacing.s),
        row(2),
      ],
    );
  }

  Widget _seatButton(TableSeat seat) {
    final state = _match.current;
    final isDealer = seat == state.dealerSeat;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final caption = _seatCaption(seat);
    return Semantics(
      button: true,
      label: '${_seatLabel(seat)}（$caption${isDealer ? '・親' : ''}）',
      excludeSemantics: true,
      child: Material(
        color: isDealer ? colors.recommended.container : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.feature),
          side: BorderSide(
            color: isDealer ? colors.recommended.border : scheme.outlineVariant,
          ),
        ),
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.2),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.feature),
          ),
          onTap: () => _openScore(seat),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (seat == TableSeat.starting || isDealer)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (seat == TableSeat.starting)
                          _SeatBadge(
                            '起家',
                            background: scheme.primary,
                            foreground: scheme.onPrimary,
                          ),
                        if (seat == TableSeat.starting && isDealer)
                          const SizedBox(width: 3),
                        if (isDealer)
                          _SeatBadge(
                            '親',
                            background: colors.warning.container,
                            foreground: colors.warning.onContainer,
                          ),
                      ],
                    ),
                  Text(
                    _seatLabel(seat),
                    style: text.headlineMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    caption,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _roundLabel(MatchSnapshot state) =>
      '${_windLabel(state.roundWind)}${state.handNumber}局・${state.honba}本場';

  /// The seat's wind this hand: the dealer is 東 and the winds run
  /// counter-clockwise from there, so they rotate as the dealer moves while
  /// 起家 stays put (東1局: 下東・右南・上西・左北).
  String _seatLabel(TableSeat seat) =>
      _windLabel(_match.current.seatWind(seat));

  String _seatCaption(TableSeat seat) => switch (seat) {
    TableSeat.starting => '起家',
    TableSeat.right => '起家の右隣',
    TableSeat.opposite => '起家の対面',
    TableSeat.left => '起家の左隣',
  };

  String _windLabel(String wind) => switch (wind) {
    'E' => '東',
    'S' => '南',
    'W' => '西',
    'N' => '北',
    _ => wind,
  };

  String _kanjiNumber(int number) => switch (number) {
    1 => '一',
    2 => '二',
    3 => '三',
    4 => '四',
    _ => '$number',
  };
}

class _SeatBadge extends StatelessWidget {
  const _SeatBadge(
    this.label, {
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.medium),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// One of the four checks as a row: kanji mark tile, label and a chevron.
class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.mark,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final String mark;
  final String label;
  final FeatureColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.s,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.container,
                    borderRadius: BorderRadius.circular(AppRadius.large),
                  ),
                  child: Text(
                    mark,
                    style: text.titleMedium?.copyWith(color: colors.accent),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(label, maxLines: 1, style: text.titleSmall),
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// End-of-match confirmation: current round, hands finished, a note that
/// results stay in the history, then 続ける / 終了.
class _EndMatchDialog extends StatelessWidget {
  const _EndMatchDialog({
    required this.roundLabel,
    required this.completedHands,
  });

  final String roundLabel;
  final int completedHands;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(label, style: muted),
          Text(value, style: text.titleSmall),
        ],
      ),
    );
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.s,
          AppSpacing.s,
          AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CloseButton(
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.error.container,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: Text(
                          '終',
                          style: text.headlineSmall?.copyWith(
                            color: colors.error.color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      '対局を終了しますか？',
                      textAlign: TextAlign.center,
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '現在の対局状態を終了して、ホームへ戻ります。局の進行状況はリセットされます。',
                      textAlign: TextAlign.center,
                      style: muted,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            stat('現在の局', roundLabel),
                            VerticalDivider(color: scheme.outline, width: 1),
                            stat('計算済み', '$completedHands局'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: colors.soft,
                            child: Icon(
                              Icons.check,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('計算結果は利用履歴に残ります', style: text.titleSmall),
                                Text('終了後も設定の「利用履歴」から確認できます', style: muted),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('対局を続ける'),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    OutlinedButton(
                      style: destructiveOutlinedButtonStyle(context),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('対局を終了'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
