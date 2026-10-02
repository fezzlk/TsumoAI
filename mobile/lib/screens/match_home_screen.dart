import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/match_state.dart';
import '../models/scan_purpose.dart';
import '../models/score_request.dart';
import '../services/tile_assets.dart';
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
                  label: _physicalSeatLabel(seat),
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
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('対局を終了しますか？')),
            CloseButton(onPressed: () => Navigator.pop(dialogContext, false)),
          ],
        ),
        content: Text('${_match.current.roundLabel}で対局を終了します。局の進行状況はリセットされます。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('対局を終了'),
          ),
        ],
      ),
    );
    if (shouldEnd != true || !mounted) return;
    widget.onMatchEnded?.call();
    Navigator.pop(context);
  }

  Future<void> _addDora() async {
    if (_match.current.doraIndicators.length >= 4) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.grey[900],
        child: SizedBox(
          width: 520,
          height: 330,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: TileImagePicker(
                  onTileSelected: (tile) => Navigator.pop(dialogContext, tile),
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('対局')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
          children: [
            const Text(
              '和了者を選択',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _tableLayout(state),
            const SizedBox(height: 16),
            _quickActions(),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _confirmEndMatch,
                child: const Text('対局終了'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableLayout(MatchSnapshot state) => Column(
    children: [
      SizedBox(
        height: 82,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _roundInfo(state)),
            const SizedBox(width: 6),
            Expanded(child: _seatButton(TableSeat.opposite)),
            const SizedBox(width: 6),
            Expanded(child: _doraPanel(state)),
          ],
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 82,
        child: Row(
          children: [
            Expanded(child: _seatButton(TableSeat.left)),
            const Expanded(child: SizedBox()),
            Expanded(child: _seatButton(TableSeat.right)),
          ],
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 82,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _match.canUndo ? () => setState(_match.undo) : null,
                child: const Text('1局戻す'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: _seatButton(TableSeat.starting)),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: _recordDraw,
                child: const Text('流局'),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _roundInfo(MatchSnapshot state) => Card(
    margin: EdgeInsets.zero,
    child: Center(
      child: Text(
        '${_windLabel(state.roundWind)}${state.handNumber}局\n${state.honba}本場',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _doraPanel(MatchSnapshot state) {
    final shownTiles = state.doraIndicators
        .map((tile) => _showDoraTiles ? doraTileFromIndicator(tile) : tile)
        .toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _showDoraTiles = !_showDoraTiles),
              child: Text(
                _showDoraTiles ? '表ドラ牌' : '表ドラ表示牌',
                style: const TextStyle(fontSize: 10),
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < shownTiles.length; index++)
                    GestureDetector(
                      onTap: () => setState(() {
                        final next = [...state.doraIndicators]..removeAt(index);
                        _match.setDoraIndicators(next);
                      }),
                      child: SizedBox(
                        width: 17,
                        height: 27,
                        child: TileGlyph(tileCode: shownTiles[index]),
                      ),
                    ),
                  if (shownTiles.length < 4)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28),
                      onPressed: _addDora,
                      icon: const Icon(Icons.add, size: 19),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() => Row(
    children: [
      for (final purpose in ScanPurpose.values) ...[
        if (purpose != ScanPurpose.values.first) const SizedBox(width: 5),
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => _openQuickCheck(purpose),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 2),
              ),
              child: Text(
                purpose.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _seatButton(TableSeat seat) {
    final state = _match.current;
    final isDealer = seat == state.dealerSeat;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FilledButton.tonal(
            onPressed: () => _openScore(seat),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Text(
              _physicalSeatLabel(seat),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (seat == TableSeat.starting)
          const Positioned(left: 3, top: 3, child: _SeatBadge('起家')),
        if (isDealer)
          const Positioned(right: 3, top: 3, child: _SeatBadge('親')),
      ],
    );
  }

  String _physicalSeatLabel(TableSeat seat) => switch (seat) {
    TableSeat.starting => '南',
    TableSeat.right => '東',
    TableSeat.opposite => '北',
    TableSeat.left => '西',
  };

  String _windLabel(String wind) => switch (wind) {
    'E' => '東',
    'S' => '南',
    'W' => '西',
    'N' => '北',
    _ => wind,
  };
}

class _SeatBadge extends StatelessWidget {
  const _SeatBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onPrimary,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
