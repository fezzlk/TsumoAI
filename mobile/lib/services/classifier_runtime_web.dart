import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/services.dart';

@JS('createTsumoClassifier')
external _WorkerClassifier _createClassifier();

extension type _WorkerClassifier(JSObject _) implements JSObject {
  external JSPromise<JSAny?> load(JSString modelUrl);
  external JSPromise<JSFloat32Array> predict(JSFloat32Array input);
  external void dispose();
}

class ClassifierRuntime {
  _WorkerClassifier? _worker;
  List<String> labels = [];
  String get modelSource => 'bundled-web';
  String get modelVersion => 'bundled-ed2678e9c4f0';
  Future<void> init() async {
    final worker = _createClassifier();
    _worker = worker;
    try {
      labels = (await rootBundle.loadString(
        'assets/ml/labels.txt',
      )).split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      await worker.load('assets/assets/ml/tile_classifier.tflite'.toJS).toDart;
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  Future<List<double>> run(Float32List input, int labelCount) async {
    final worker = _worker;
    if (worker == null) throw StateError('牌識別モデルが読み込まれていません');
    final result = (await worker.predict(input.toJS).toDart).toDart;
    if (result.length != labelCount) throw StateError('牌識別モデルのラベル数が一致しません');
    return result.toList();
  }

  void dispose() {
    _worker?.dispose();
    _worker = null;
  }
}
