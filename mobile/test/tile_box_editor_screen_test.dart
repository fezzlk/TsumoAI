import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/models/tile_quad.dart';
import 'package:tsumoai_mobile/screens/tile_box_editor_screen.dart';

import 'test_utils/landscape_surface.dart';

final _rawImageBytes = img.encodePng(
  img.Image(width: 400, height: 300)..clear(img.ColorRgb8(200, 200, 200)),
);

const _initialQuad = TileQuad(
  topLeft: Offset(10, 10),
  topRight: Offset(50, 10),
  bottomLeft: Offset(10, 60),
  bottomRight: Offset(50, 60),
);

/// Pumps a screen with a button that pushes [TileBoxEditorScreen], taps it,
/// and returns a getter for whatever the route eventually pops.
Future<TileBoxEditorResult? Function()> openEditor(WidgetTester tester) async {
  TileBoxEditorResult? result;
  await pumpAtDeviceLandscapeSize(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<TileBoxEditorResult>(
                MaterialPageRoute(
                  builder: (_) => TileBoxEditorScreen(
                    rawImageBytes: _rawImageBytes,
                    rawWidth: 400,
                    rawHeight: 300,
                    initialQuad: _initialQuad,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  // Regression test for FEZ-193: previously there was no way to remove a
  // wrongly-added tile box other than retaking the whole photo. The
  // editor's delete action must ask for confirmation (destructive), and on
  // confirming must pop a `TileBoxEditorDeleted`, not a quad.
  testWidgets(
    'TileBoxEditorScreen: delete asks for confirmation and returns TileBoxEditorDeleted',
    (tester) async {
      final result = await openEditor(tester);

      await tester.tap(find.byTooltip('この枠を削除'));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear rather than deleting immediately.
      expect(find.text('この枠を削除しますか？'), findsOneWidget);
      expect(result(), isNull);

      // Cancelling the dialog must leave the editor open with no result.
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.text('確定'), findsOneWidget);
      expect(result(), isNull);

      // Deleting for real closes the editor with a delete result.
      await tester.tap(find.byTooltip('この枠を削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();

      expect(result(), isA<TileBoxEditorDeleted>());
    },
  );

  testWidgets(
    'TileBoxEditorScreen: confirm returns TileBoxEditorConfirmed with the quad',
    (tester) async {
      final result = await openEditor(tester);

      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      expect(result(), isA<TileBoxEditorConfirmed>());
      expect(
        (result() as TileBoxEditorConfirmed).quad.topLeft,
        const Offset(10, 10),
      );
    },
  );
}
