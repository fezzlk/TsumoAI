import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/match_state.dart';
import '../models/scan_purpose.dart';
import 'scan_screen.dart';

class MatchHomeScreen extends StatefulWidget {
  const MatchHomeScreen({
    super.key,
    required this.cameras,
    required this.autoClassify,
    required this.showTrainingDataActions,
  });

  final List<CameraDescription> cameras;
  final bool autoClassify;
  final bool showTrainingDataActions;

  @override
  State<MatchHomeScreen> createState() => _MatchHomeScreenState();
}

class _MatchHomeScreenState extends State<MatchHomeScreen> {
  final MatchState _match = MatchState();

  Future<void> _openScore(TableSeat winner) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          cameras: widget.cameras,
          autoClassify: widget.autoClassify,
          purpose: ScanPurpose.score,
          initialContext: _match.current.contextFor(winner),
          historyRoundLabel: _match.current.roundLabel,
          showTrainingDataActions: widget.showTrainingDataActions,
          onScoreConfirmed: (_) => setState(() => _match.recordWin(winner)),
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
        ),
      ),
    );
  }

  Future<void> _recordDraw() async {
    final continues = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '流局後の親',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('親が継続'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('親が交代'),
              ),
            ],
          ),
        ),
      ),
    );
    if (continues != null) {
      setState(() => _match.recordDraw(dealerContinues: continues));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _match.current;
    return Scaffold(
      appBar: AppBar(title: const Text('対局')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.roundLabel,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('親: ${state.dealerLabel}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '和了者を選択',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _seatButton(TableSeat.opposite),
            Row(
              children: [
                Expanded(child: _seatButton(TableSeat.left)),
                const SizedBox(width: 72, height: 72),
                Expanded(child: _seatButton(TableSeat.right)),
              ],
            ),
            _seatButton(TableSeat.starting),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(onPressed: _recordDraw, child: const Text('流局')),
                OutlinedButton(
                  onPressed: _match.canUndo
                      ? () => setState(_match.undo)
                      : null,
                  child: const Text('1局戻す'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('対局終了'),
                ),
              ],
            ),
            const Divider(height: 40),
            const Text(
              'すぐ確認',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _openQuickCheck(ScanPurpose.score),
                  child: const Text('点数計算'),
                ),
                OutlinedButton(
                  onPressed: () => _openQuickCheck(ScanPurpose.wait),
                  child: const Text('待ち確認'),
                ),
                OutlinedButton(
                  onPressed: () => _openQuickCheck(ScanPurpose.discard),
                  child: const Text('AI相談'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seatButton(TableSeat seat) {
    final state = _match.current;
    final isDealer = seat == state.dealerSeat;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 64,
        child: FilledButton.tonal(
          onPressed: () => _openScore(seat),
          child: Text(
            '${MatchSnapshot.seatLabel(seat)}\n${isDealer ? '親・東家' : '${_windLabel(state.seatWind(seat))}家'}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  String _windLabel(String wind) => switch (wind) {
    'E' => '東',
    'S' => '南',
    'W' => '西',
    'N' => '北',
    _ => wind,
  };
}
