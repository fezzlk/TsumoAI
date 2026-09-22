import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/screens/history_screen.dart';
import 'package:tsumoai_mobile/screens/match_home_screen.dart';
import 'package:tsumoai_mobile/services/history_service.dart';
import 'package:tsumoai_mobile/models/history_entry.dart';
import 'package:tsumoai_mobile/widgets/tile_count_selector.dart';

import 'test_utils/landscape_surface.dart';

class _EmptyHistoryService extends HistoryService {
  @override
  Future<List<HistoryEntry>> loadLocal() async => [];
}

const _narrowPortrait = Size(320, 568);
const _narrowPadding = EdgeInsets.only(bottom: 20);

void main() {
  testWidgets('tile count choices stay visible on a narrow portrait screen', (
    tester,
  ) async {
    int? selected = 14;
    await pumpAtDeviceSize(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: TileCountSelector(
            selectedCount: selected,
            counts: const [13, 14, 15, 16, 17, 18],
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    final labels = ['自動', '13', '14', '15', '16', '17', '18'];
    final verticalCenters = <double>[];
    for (final label in labels) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      expect(
        tester.getRect(finder).right,
        lessThanOrEqualTo(_narrowPortrait.width),
      );
      verticalCenters.add(tester.getCenter(finder).dy);
    }
    expect(verticalCenters.toSet(), hasLength(1));
    expectNoOverflow(tester);

    await tester.tap(find.text('18'));
    await tester.pump();
    expect(selected, 18);
    expectNoOverflow(tester);
  });

  testWidgets('history filters wrap without horizontal clipping', (
    tester,
  ) async {
    await pumpAtDeviceSize(
      tester,
      HistoryScreen(service: _EmptyHistoryService()),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    for (final label in ['すべて', '点数', '待ち', 'AI相談']) {
      expect(find.text(label), findsOneWidget);
    }
    expectNoOverflow(tester);
  });

  testWidgets('match home fits a narrow portrait screen', (tester) async {
    await pumpAtDeviceSize(
      tester,
      const MatchHomeScreen(
        cameras: [],
        autoClassify: false,
        showTrainingDataActions: false,
      ),
      size: _narrowPortrait,
      padding: _narrowPadding,
    );
    await tester.pumpAndSettle();

    expect(find.text('和了者を選択'), findsOneWidget);
    expectNoOverflow(tester);
  });
}
