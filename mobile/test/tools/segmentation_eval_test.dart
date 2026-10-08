// Runs the app's tile segmenter on an evaluation set and writes the boxes it
// finds (FEZ-245). Not a regression test: skipped unless a set is given.
//
//   flutter test test/tools/segmentation_eval_test.dart \
//     --dart-define=SEG_EVAL_DIR=/abs/path/to/data/segmentation_eval_v1 \
//     --dart-define=SEG_EVAL_LABEL=baseline
//
// Reads SEG_EVAL_DIR/manifest.json (see scripts/generate_segmentation_eval_set.py)
// and writes SEG_EVAL_DIR/results_<label>.json; score it with
// scripts/score_segmentation_eval.py.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/tile_segmenter.dart';

const _dir = String.fromEnvironment('SEG_EVAL_DIR');
const _label = String.fromEnvironment('SEG_EVAL_LABEL', defaultValue: 'run');

void main() {
  test('segment the evaluation set', skip: _dir.isEmpty, () {
    final manifest =
        jsonDecode(File('$_dir/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final results = <Map<String, dynamic>>[];
    for (final item in (manifest['cases'] as List).cast<Map<String, dynamic>>()) {
      final bytes = File('$_dir/${item['image']}').readAsBytesSync();
      final watch = Stopwatch()..start();
      // Exactly what the app does after capture: the selected tile count.
      final found = segmentTilesWithHintsForExpectedCount((
        bytes: bytes,
        expectedTileCount: item['tile_count'] as int,
        allowExtendedAuto: false,
      ));
      results.add({
        'case_id': item['case_id'],
        'millis': watch.elapsedMilliseconds,
        'boxes': [
          for (final box in found.boxes)
            [box.left, box.top, box.width, box.height],
        ],
      });
    }
    File('$_dir/results_$_label.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'label': _label,
        'results': results,
      }),
    );
  });
}
