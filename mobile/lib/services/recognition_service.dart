import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import '../models/recognize_result.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';

enum ServiceState { idle, recognizing, scoring, done, error }

class RecognitionService extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  ServiceState _state = ServiceState.idle;
  RecognizeResponse? _recognition;
  ScoreResponse? _score;
  String? _errorMessage;

  ServiceState get state => _state;
  RecognizeResponse? get recognition => _recognition;
  ScoreResponse? get score => _score;
  String? get errorMessage => _errorMessage;

  /// Full pipeline: upload image → recognize → score
  Future<void> processImage(File imageFile, ContextInput context) async {
    try {
      _state = ServiceState.recognizing;
      _recognition = null;
      _score = null;
      _errorMessage = null;
      notifyListeners();

      // 1. Start recognition job
      final jobId = await _api.startRecognitionJob(imageFile);

      // 2. Wait for recognition result
      _recognition = await _api.waitForRecognition(jobId);
      notifyListeners();

      // 3. Build score request from recognized tiles
      _state = ServiceState.scoring;
      notifyListeners();

      final hand = HandInput(
        closedTiles: _recognition!.handEstimate.topTiles,
        melds: [],
        winTile: _recognition!.handEstimate.topTiles.last,
      );

      final request = ScoreRequest(
        hand: hand,
        context: context,
        rules: RuleSet(),
      );

      _score = await _api.calculateScore(request);
      _state = ServiceState.done;
      notifyListeners();
    } catch (e) {
      _state = ServiceState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void reset() {
    _state = ServiceState.idle;
    _recognition = null;
    _score = null;
    _errorMessage = null;
    notifyListeners();
  }
}
