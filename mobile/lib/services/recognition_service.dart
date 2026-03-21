import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'on_device_recognizer.dart';
import '../models/recognize_result.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';

enum ServiceState { idle, recognizing, scoring, done, error }

class RecognitionService extends ChangeNotifier {
  final ApiClient _api = ApiClient();
  final OnDeviceRecognizer _onDevice = OnDeviceRecognizer();

  ServiceState _state = ServiceState.idle;
  RecognizeResponse? _recognition;
  ScoreResponse? _score;
  String? _errorMessage;
  bool _isNotWinning = false;
  /// Whether on-device recognition was used (for debug display).
  bool _usedOnDevice = false;

  ServiceState get state => _state;
  RecognizeResponse? get recognition => _recognition;
  ScoreResponse? get score => _score;
  String? get errorMessage => _errorMessage;
  bool get isNotWinning => _isNotWinning;
  bool get usedOnDevice => _usedOnDevice;

  /// Initialize on-device model. Call once at startup.
  Future<void> initOnDevice() async {
    try {
      await _onDevice.init();
    } catch (e) {
      debugPrint('On-device model init failed: $e');
    }
  }

  /// Full pipeline: on-device recognize → (fallback: server) → score
  Future<void> processImage(File imageFile, ContextInput context) async {
    try {
      _state = ServiceState.recognizing;
      _recognition = null;
      _score = null;
      _errorMessage = null;
      _isNotWinning = false;
      _usedOnDevice = false;
      notifyListeners();

      // 1. Try on-device recognition first (fast, < 1 second)
      List<String>? tiles;
      final onDeviceResult = await _onDevice.recognize(imageFile);

      if (onDeviceResult != null && onDeviceResult.tileCodes.length >= 13) {
        _usedOnDevice = true;
        tiles = onDeviceResult.tileCodes;

        // Build a synthetic RecognizeResponse for display
        final slots = <HandSlot>[];
        for (int i = 0; i < tiles.length; i++) {
          slots.add(HandSlot(
            index: i,
            top: tiles[i],
            candidates: [
              TileCandidate(
                tile: tiles[i],
                confidence: onDeviceResult.confidences[i],
              ),
            ],
            ambiguous: onDeviceResult.confidences[i] < 0.7,
          ));
        }
        _recognition = RecognizeResponse(
          recognitionId: 'on-device',
          handEstimate: HandEstimate(
            tilesCount: tiles.length,
            slots: slots,
          ),
          warnings: [],
          rawJson: {
            'recognition_id': 'on-device',
            'hand_estimate': {
              'tiles_count': tiles.length,
              'slots': slots.map((s) => {
                'index': s.index,
                'top': s.top,
                'candidates': s.candidates.map((c) => {
                  'tile': c.tile,
                  'confidence': c.confidence,
                }).toList(),
                'ambiguous': s.ambiguous,
              }).toList(),
            },
            'warnings': <String>[],
          },
        );
        notifyListeners();
      }

      // 2. Fallback: server-side recognition
      if (tiles == null) {
        _recognition = await _api.recognize(imageFile);
        tiles = _recognition!.handEstimate.topTiles;
        notifyListeners();
      }

      if (tiles.isEmpty) {
        _state = ServiceState.error;
        _errorMessage = '牌が認識できませんでした';
        notifyListeners();
        return;
      }

      // 3. Score
      _state = ServiceState.scoring;
      notifyListeners();

      final hand = HandInput(
        closedTiles: tiles,
        melds: [],
        winTile: tiles.last,
      );

      final request = ScoreRequest(
        hand: hand,
        context: context,
        rules: RuleSet(),
      );

      _score = await _api.calculateScore(request);

      if (_score == null) {
        _isNotWinning = true;
      }

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
    _isNotWinning = false;
    _usedOnDevice = false;
    notifyListeners();
  }
}
