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
  testWidgets(
    'TileBoxEditorScreen: correction does not expose box deletion',
    (tester) async {
      final result = await openEditor(tester);

      expect(find.byTooltip('この枠を削除'), findsNothing);
      expect(find.text('確定'), findsOneWidget);
      expect(result(), isNull);
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
