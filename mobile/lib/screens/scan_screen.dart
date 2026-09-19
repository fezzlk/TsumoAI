import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../services/tile_classifier.dart';
import '../services/api_client.dart';
import '../services/tile_detector.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';
import '../models/interpretation_request.dart';
import '../models/interpretation_result.dart';
import '../models/tile_observation.dart';
import '../widgets/tile_image_picker.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/context_input_panel.dart';
import '../widgets/game_state_panel.dart';
import '../widgets/score_result_panel.dart';
import '../widgets/tile_marker_overlay.dart';
import '../services/training_data_client.dart';
import '../services/tile_segmenter.dart';
import '../services/tile_assets.dart';
import '../services/meld_detector.dart';
import '../models/tile_quad.dart';
import '../services/scan_observation_builder.dart';
import '../services/request_epoch.dart';
import 'tile_box_editor_screen.dart';

class ScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ScanScreen({super.key, required this.cameras});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanPhase { camera, detecting, results }

class _ScanScreenState extends State<ScanScreen> {
  static const int _maxPhysicalTiles = 18;
  CameraController? _controller;
  final TileClassifier _classifier = TileClassifier();
  final ApiClient _api = ApiClient();
  final TrainingDataClient _trainingClient = TrainingDataClient();

  _ScanPhase _phase = _ScanPhase.camera;

  // The capture, straight from the camera plugin — `lockCaptureOrientation`
  // (see `_initCamera`) makes this already correctly oriented, so there's
  // no separate raw/corrected buffer or coordinate space to keep in sync.
  Uint8List? _capturedBytes;
  img.Image? _capturedImage;

  // Tile results
  final List<String?> _tiles = List.filled(_maxPhysicalTiles, null);
  // Latest on-device predictions, kept unchanged when the user corrects
  // `_tiles`, so training uploads can measure real-world recognition accuracy.
  final List<String?> _predictedTiles = List.filled(_maxPhysicalTiles, null);
  final List<List<TileCandidate>> _candidates = List.generate(
    _maxPhysicalTiles,
    (_) => <TileCandidate>[],
  );
  final List<bool> _isClassifying = List.filled(_maxPhysicalTiles, false);
  final List<img.Image?> _croppedImages = List.filled(_maxPhysicalTiles, null);
  // Cached JPEG encoding of `_croppedImages`, computed once when a crop is
  // set rather than in build() — re-encoding 14 images per rebuild (e.g. on
  // every drag frame of a box edit) was the main source of the "重い"
  // (heavy/laggy) results-screen feedback.
  final List<Uint8List?> _croppedImageThumbnails = List.filled(
    _maxPhysicalTiles,
    null,
  );
  // Each tile's crop region as 4 independent corners (not just an
  // axis-aligned Rect) — see `TileQuad` for why: a tile photographed at an
  // angle projects as a general quadrilateral, not just a rotated
  // rectangle. In `_capturedImage`'s (corrected) pixel space.
  final List<TileQuad?> _tileQuads = List.filled(_maxPhysicalTiles, null);

  // Live auto-shutter detection (FEZ-96): runs TileDetector against the
  // camera preview stream and captures automatically once a full 14-tile
  // detection has stayed stable for a few frames in a row, instead of
  // requiring the user to judge readiness and tap the shutter themselves.
  // Opt-in — this is the first on-device verification of the approach
  // (interval/streak below are unverified guesses, and detection only
  // checks the tile count, not that the same tiles/positions held
  // steady), so it defaults off until real-device behavior is confirmed.
  bool _autoCaptureEnabled = false;
  bool _isLiveStreamActive = false;
  bool _isAnalyzingFrame = false;
  CameraImage? _latestFrame;
  Timer? _analysisTimer;
  TileDetectorResult? _liveDetectorResult;
  int _stableDetectionStreak = 0;
  static const int _requiredStableFrames = 2;
  static const Duration _analysisInterval = Duration(seconds: 1);

  bool _isCapturing = false;
  bool _isScoring = false;
  bool _isInterpreting = false;
  bool _isSendingTraining = false;
  bool _trainingDataSent = false;
  bool _isUndoingTraining = false;
  List<String> _sentTrainingEntryIds = [];
  ScoreResponse? _scoreResult;
  bool _isNotWinning = false;
  InterpretationResult? _interpretation;
  String? _confirmedWinningTileId;
  // Tracks whether `_confirmedWinningTileId` came from the user moving it
  // themselves (the ◀/▶ buttons), as opposed to the rightmost-tile default
  // below or the AI's own suggestion in `_runInterpretation` — only a
  // manual choice may never be silently overwritten.
  bool _winningTileManuallySet = false;
  final List<ConfirmedMeld> _confirmedMelds = [];
  HandOperation _operation = HandOperation.score;
  Map<String, dynamic>? _analysisResult;
  final RequestEpoch _requestEpoch = RequestEpoch();

  // Inline meld-selection mode (see `_buildTileControlsRow`): while active, taps
  // on the thumbnail row pick meld members instead of their normal
  // edit/correct behavior.
  bool _isSelectingMeld = false;
  final Set<int> _meldSelection = {};

  // Set by long-pressing a thumbnail (see `_handleThumbnailTap`): shows a
  // small ✕ badge on that slot to confirm deleting it, instead of deleting
  // immediately on long-press itself.
  int? _deleteAffordanceIndex;

  ContextInput _context = ContextInput();

  /// The rightmost identified physical tile's observation id, or null if
  /// none are identified yet — the results screen's default あがり牌 frame
  /// position before the AI suggests one or the user drags it themselves.
  String? get _defaultWinningTileId {
    for (int index = _maxPhysicalTiles - 1; index >= 0; index--) {
      if (_tiles[index] != null) {
        return 'tile-${index.toString().padLeft(3, '0')}';
      }
    }
    return null;
  }

  void _invalidateInterpretation() {
    _invalidateAnalysis();
    _interpretation = null;
    _confirmedWinningTileId = _defaultWinningTileId;
    _winningTileManuallySet = false;
    _confirmedMelds.clear();
    _isSelectingMeld = false;
    _meldSelection.clear();
    _deleteAffordanceIndex = null;
  }

  /// Physical-tile indices with an identified tile, ascending — the ◀/▶
  /// あがり牌 controls step through exactly this list.
  List<int> get _identifiedIndices => [
    for (int index = 0; index < _maxPhysicalTiles; index++)
      if (_tiles[index] != null) index,
  ];

  /// The current あがり牌's position within `_identifiedIndices`, or null
  /// if none is set yet — drives the ◀/▶ controls' enabled state.
  int? get _winningTilePosition {
    final currentIndex = _confirmedWinningTileId == null
        ? null
        : int.tryParse(_confirmedWinningTileId!.split('-').last);
    if (currentIndex == null) return null;
    final position = _identifiedIndices.indexOf(currentIndex);
    return position == -1 ? null : position;
  }

  void _moveWinningTile(int delta) {
    final indices = _identifiedIndices;
    if (indices.isEmpty) return;
    final position = _winningTilePosition;
    final nextPosition = (position == null ? 0 : position + delta).clamp(
      0,
      indices.length - 1,
    );
    setState(() {
      _confirmedWinningTileId =
          'tile-${indices[nextPosition].toString().padLeft(3, '0')}';
      _winningTileManuallySet = true;
      _invalidateAnalysis();
    });
  }

  /// Dispatches a normal thumbnail tap (`action`), unless a ✕ delete badge
  /// is currently showing on some slot (`_deleteAffordanceIndex`) — in that
  /// case the tap just dismisses the badge instead, a "tap away to cancel"
  /// pattern so an accidental tap right after a long-press can't also
  /// trigger the box editor or tile picker.
  void _handleThumbnailTap(VoidCallback action) {
    if (_deleteAffordanceIndex != null) {
      setState(() => _deleteAffordanceIndex = null);
      return;
    }
    action();
  }

  void _invalidateAnalysis() {
    _requestEpoch.invalidate();
    _analysisResult = null;
    _scoreResult = null;
    _isNotWinning = false;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initClassifier();
  }

  Future<void> _initClassifier() async {
    try {
      await _classifier.init();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Classifier init error: $e');
      _showError('牌識別モデル読込エラー: $e');
    }
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      // Needed for startImageStream()'s live auto-detect (see below) to get
      // a predictable YUV plane layout on both Android and iOS; takePicture()
      // (still JPEG) is unaffected.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await _controller!.initialize();
      // The phone is held nearly flat, pointed down at tiles on a table —
      // the accelerometer can't reliably tell landscape from portrait in
      // that position, so ambient device-orientation detection (what both
      // the live preview and the captured photo would otherwise fall back
      // on) is unusable here. Pin it explicitly instead: this is what
      // actually determines CameraPreview's aspect ratio (it checks
      // `lockedCaptureOrientation` before the ambient sensor) and the
      // orientation `takePicture()` bakes into the photo.
      await _controller!.lockCaptureOrientation(
        DeviceOrientation.landscapeLeft,
      );
      if (mounted) setState(() {});
      await _startLiveDetection();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _startLiveDetection() async {
    await _stopLiveDetection();
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.startImageStream((image) => _latestFrame = image);
      _isLiveStreamActive = true;
    } catch (e) {
      debugPrint('Live detection stream start error: $e');
      return;
    }
    _analysisTimer = Timer.periodic(
      _analysisInterval,
      (_) => _analyzeLatestFrame(),
    );
  }

  Future<void> _stopLiveDetection() async {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _latestFrame = null;
    _stableDetectionStreak = 0;
    if (_isLiveStreamActive) {
      try {
        await _controller?.stopImageStream();
      } catch (e) {
        debugPrint('Live detection stream stop error: $e');
      }
      _isLiveStreamActive = false;
    }
  }

  Future<void> _analyzeLatestFrame() async {
    if (_isAnalyzingFrame || _isCapturing || _phase != _ScanPhase.camera) {
      return;
    }
    final frame = _latestFrame;
    if (frame == null) return;

    _isAnalyzingFrame = true;
    try {
      final result = await TileDetector.detect(frame);
      if (!mounted || _phase != _ScanPhase.camera) return;

      final isFullDetection = result.tileCount == TileDetector.targetTileCount;
      setState(() {
        _liveDetectorResult = result;
        _stableDetectionStreak = isFullDetection
            ? _stableDetectionStreak + 1
            : 0;
      });

      if (_autoCaptureEnabled &&
          !_isCapturing &&
          _stableDetectionStreak >= _requiredStableFrames) {
        _stableDetectionStreak = 0;
        await _capture();
      }
    } catch (e) {
      debugPrint('Live tile detection error: $e');
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCaptureEnabled = !_autoCaptureEnabled;
      _stableDetectionStreak = 0;
    });
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _controller?.dispose();
    _classifier.dispose();
    super.dispose();
  }

  // ── Phase 1: Capture ──

  Future<void> _capture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    await _stopLiveDetection();
    // Mirrors CameraScreen's original auto-detect prototype: the native
    // camera needs a moment to fully release the image stream before
    // takePicture(), or the capture can fail/stall.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      if (mounted) setState(() => _isCapturing = false);
      return;
    }

    bool capturedOk = false;
    try {
      final xFile = await _controller!.takePicture();
      final bytes = await File(xFile.path).readAsBytes();
      // Off the main isolate: decoding a high-resolution JPEG synchronously
      // here blocked the UI thread long enough that the camera preview
      // visibly froze on a stale frame right after the shutter.
      final decoded = await compute(img.decodeImage, bytes);
      if (decoded == null) throw Exception('画像のデコードに失敗');
      capturedOk = true;

      setState(() {
        _capturedBytes = bytes;
        _capturedImage = decoded;
        _phase = _ScanPhase.detecting;
        for (int i = 0; i < _maxPhysicalTiles; i++) {
          _tiles[i] = null;
          _predictedTiles[i] = null;
          _candidates[i] = [];
          _isClassifying[i] = false;
          _croppedImages[i] = null;
          _croppedImageThumbnails[i] = null;
          _tileQuads[i] = null;
        }
      });

      // Always proceed straight to the results phase with whatever
      // detection found (13/14 clean, or short/over-counted) — the results
      // screen's "枠を追加" button and per-tile box editor already cover
      // fixing up any missing/wrong boxes, so a partial/imperfect detection
      // no longer needs to fall back to the separate manual grid-alignment
      // phase (that fallback used to trigger on any non-13/14 count, which
      // was hitting often enough to be disruptive on its own).
      final detected = await compute(segmentTilesWithHintsFromBytes, bytes);
      if (!mounted) return;
      await _classifyBoxesAndFinish(
        detected.boxes,
        angleHints: detected.angleHints,
      );
    } catch (e) {
      _showError('撮影エラー: $e');
      // If capture/decode itself failed, stay on the camera phase; if it was
      // detection that failed after a successful capture, still move on to
      // the results phase (empty boxes) rather than getting stuck on the
      // spinner — the user can add all 14 boxes manually from there.
      if (capturedOk) await _classifyBoxesAndFinish(const []);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
      // takePicture() itself failed (capturedOk stayed false): we're still
      // on the camera phase, so resume live detection instead of leaving
      // the preview stuck without it.
      if (mounted && _phase == _ScanPhase.camera) await _startLiveDetection();
    }
  }

  /// Crop and on-device-classify each of [boxes] (in `_capturedImage`'s pixel
  /// coordinate space), populating `_tiles`/`_croppedImages`/`_tileQuads`,
  /// then move to the results phase. [angleHints] has one entry per box —
  /// see `segmentTilesWithHints`.
  Future<void> _classifyBoxesAndFinish(
    List<Rect> boxes, {
    List<double>? angleHints,
  }) async {
    final srcImage = _capturedImage;
    if (srcImage == null) return;

    setState(() {
      for (int i = 0; i < _maxPhysicalTiles; i++) {
        _tiles[i] = null;
        _predictedTiles[i] = null;
        _candidates[i] = [];
        _isClassifying[i] = false;
        _croppedImages[i] = null;
        _croppedImageThumbnails[i] = null;
        _tileQuads[i] = null;
      }
      _invalidateInterpretation();
    });

    for (int i = 0; i < boxes.length && i < _maxPhysicalTiles; i++) {
      final box = boxes[i];
      final refined = refineTileCropWithRect(
        srcImage,
        box,
        angleHint: angleHints?[i] ?? 0.0,
      );
      final cropped = refined.image;
      _croppedImages[i] = cropped;
      _croppedImageThumbnails[i] = Uint8List.fromList(img.encodeJpg(cropped));
      // The displayed/editable box starts from the actual tight refined
      // crop region, not the coarse uniform-pitch `box` from segmentTiles
      // (every tile in a row would otherwise show the same size marker).
      _tileQuads[i] = refined.sourceQuad;
    }

    setState(() => _phase = _ScanPhase.results);
  }

  /// Classifies every cropped tile (`_croppedImages`) at once. Separate
  /// from cropping itself (both the auto-detect path above and
  /// `_openBoxEditor` only crop) so the AI doesn't run on every box edit —
  /// only when the user explicitly asks for it via the results screen's
  /// "識別実行" button.
  Future<void> _runClassification() async {
    if (!_classifier.isReady) {
      _showError('牌識別モデルが読み込まれていません');
      return;
    }

    setState(() {
      for (int i = 0; i < _maxPhysicalTiles; i++) {
        if (_croppedImages[i] != null) _isClassifying[i] = true;
      }
    });

    for (int i = 0; i < _maxPhysicalTiles; i++) {
      final cropped = _croppedImages[i];
      if (cropped == null) continue;
      final results = await _classifier.classify(cropped, topK: 3);
      setState(() {
        final prediction = results.isNotEmpty ? results.first.tileCode : null;
        _tiles[i] = prediction;
        _predictedTiles[i] = prediction;
        _candidates[i] = results
            .map(
              (result) => TileCandidate(
                tile: result.tileCode,
                confidence: result.confidence,
              ),
            )
            .toList(growable: false);
        _isClassifying[i] = false;
      });
    }

    setState(() {
      _invalidateInterpretation();
    });
  }

  // ── Results phase: manual box correction ──

  /// Opens the full-screen quad editor for tile [index] (see
  /// `TileBoxEditorScreen` for why it's a separate route rather than
  /// embedded here). [initialDecodedQuad] seeds the editor when the tile
  /// has no quad yet (the "枠を追加" path); otherwise the existing
  /// `_tileQuads[index]` is used. On confirm, re-crops via `_cropQuad`
  /// (perspective-rectifies the quad — handles a tile that photographed as
  /// a trapezoid, not just a rotated rectangle). Does NOT reclassify —
  /// only the results screen's "識別実行" button runs the AI, so editing a
  /// box clears that tile's previous result rather than guessing again
  /// immediately. On delete, clears the slot entirely via `_clearTileSlot`
  /// (see FEZ-193 — previously the only way to undo a wrongly-added box
  /// was to retake the whole photo).
  Future<void> _openBoxEditor(int index, {TileQuad? initialDecodedQuad}) async {
    final srcImage = _capturedImage;
    final imageBytes = _capturedBytes;
    if (srcImage == null || imageBytes == null) return;

    final quad = _tileQuads[index] ?? initialDecodedQuad;
    if (quad == null) return;

    final result = await Navigator.of(context).push<TileBoxEditorResult>(
      MaterialPageRoute(
        builder: (_) => TileBoxEditorScreen(
          rawImageBytes: imageBytes,
          rawWidth: srcImage.width,
          rawHeight: srcImage.height,
          initialQuad: quad,
        ),
      ),
    );
    if (result == null || !mounted) return;

    if (result is TileBoxEditorDeleted) {
      setState(() => _clearTileSlot(index));
      return;
    }

    final newQuad = (result as TileBoxEditorConfirmed).quad;
    final cropped = _cropQuad(srcImage, newQuad);

    setState(() {
      _tileQuads[index] = newQuad;
      _croppedImages[index] = cropped;
      _croppedImageThumbnails[index] = Uint8List.fromList(
        img.encodeJpg(cropped),
      );
      _tiles[index] = null;
      _predictedTiles[index] = null;
      _candidates[index] = [];
      _invalidateInterpretation();
    });
  }

  /// Resets tile slot [index] back to empty (no quad, crop, or
  /// classification) — the per-tile counterpart to `_backToCamera`'s full
  /// reset. Must be called inside `setState`.
  void _clearTileSlot(int index) {
    _tileQuads[index] = null;
    _croppedImages[index] = null;
    _croppedImageThumbnails[index] = null;
    _tiles[index] = null;
    _predictedTiles[index] = null;
    _candidates[index] = [];
    _isClassifying[index] = false;
    _invalidateInterpretation();
  }

  /// Opens the editor for the next empty physical-tile slot, seeded with a
  /// median-size placeholder for the user to move into place.
  void _addMissingTileBox() {
    final srcImage = _capturedImage;
    if (srcImage == null) return;
    final existing = _tileQuads
        .whereType<TileQuad>()
        .map((q) => q.boundingRect)
        .toList();
    if (existing.isEmpty) return;
    final newIndex = _tileQuads.indexWhere((q) => q == null);
    if (newIndex == -1) return;

    final medianW = _median(existing.map((r) => r.width).toList());
    final medianH = _median(existing.map((r) => r.height).toList());
    final placeholder = TileQuad.fromRect(
      Rect.fromCenter(
        center: Offset(srcImage.width / 2, srcImage.height / 2),
        width: medianW,
        height: medianH,
      ),
    );

    _openBoxEditor(newIndex, initialDecodedQuad: placeholder);
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Perspective-rectifies the quadrilateral [quad] (in `source`'s pixel
  /// space) into an axis-aligned tile image, via `package:image`'s
  /// `copyRectify` (bilinear-samples the quad onto a rectangle — a
  /// general quad-to-rect warp, not just a rotation, so it also corrects a
  /// tile that photographed as a trapezoid). Output size is the average of
  /// the quad's own edge lengths; `TileClassifier.classify` resizes to its
  /// fixed input size regardless, so only the aspect ratio matters here.
  img.Image _cropQuad(img.Image source, TileQuad quad) {
    final w =
        ((quad.topRight - quad.topLeft).distance +
            (quad.bottomRight - quad.bottomLeft).distance) /
        2;
    final h =
        ((quad.bottomLeft - quad.topLeft).distance +
            (quad.bottomRight - quad.topRight).distance) /
        2;
    final outW = w.round().clamp(8, 2000);
    final outH = h.round().clamp(8, 2000);
    final out = img.Image(width: outW, height: outH);
    return img.copyRectify(
      source,
      topLeft: img.Point(quad.topLeft.dx, quad.topLeft.dy),
      topRight: img.Point(quad.topRight.dx, quad.topRight.dy),
      bottomLeft: img.Point(quad.bottomLeft.dx, quad.bottomLeft.dy),
      bottomRight: img.Point(quad.bottomRight.dx, quad.bottomRight.dy),
      interpolation: img.Interpolation.linear,
      toImage: out,
    );
  }

  // ── Phase 3: Interpretation, confirmation, and explicit operation ──

  ObservationV1 _buildObservation() {
    final image = _capturedImage;
    if (image == null) throw StateError('撮影画像がありません');
    final inputs = <ScanObservationInput>[];
    for (int index = 0; index < _maxPhysicalTiles; index++) {
      final tile = _tiles[index];
      if (tile == null) continue;
      final candidates = _candidates[index].isEmpty
          ? [TileCandidate(tile: tile, confidence: 1.0)]
          : _candidates[index];
      inputs.add(
        ScanObservationInput(
          index: index,
          candidates: candidates,
          quad: _tileQuads[index],
        ),
      );
    }
    return buildScanObservationV1(
      imageWidth: image.width,
      imageHeight: image.height,
      tiles: inputs,
    );
  }

  Future<void> _runInterpretation() async {
    if (!_allDetectedTilesReady) return;
    setState(() {
      _isInterpreting = true;
      _invalidateInterpretation();
    });
    final requestEpoch = _requestEpoch.current;
    try {
      final result = await _api.interpret(
        InterpretationRequest(observation: _buildObservation()),
      );
      if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
      setState(() {
        _interpretation = result;
        // Pre-fill the winning-tile marker (the actual selection UI, in
        // the thumbnail row above) from the image's own reading, when it
        // found one and the user hasn't already dragged the frame
        // themselves (whatever it's currently showing before this point is
        // at most the rightmost-tile default from `_invalidateInterpretation`,
        // never a manual choice) — this replaces a separate, confusing
        // "suggested winning tile" text block that duplicated this same
        // information without driving the real control.
        final suggestedId = result.winningTile.observationId;
        if (_operation == HandOperation.score &&
            !_winningTileManuallySet &&
            suggestedId != null &&
            result.winningTile.status != FactStatus.unknown) {
          _confirmedWinningTileId = suggestedId;
        }
      });
    } catch (error) {
      if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
        _showError('画像解釈エラー: $error');
      }
    } finally {
      if (mounted) setState(() => _isInterpreting = false);
    }
  }

  /// The bottom bar's "実行" button, combined into one tap: run image
  /// interpretation if it hasn't happened yet for the current tiles, then
  /// immediately proceed to confirm+analyze. Previously these were two
  /// separate taps under the same always-"実行"-labeled button (see the
  /// FEZ-191 follow-up note below) — harmless while the first tap's result
  /// (`_runInterpretation` setting `_interpretation`) was visible via
  /// `_buildInterpretationConfirmation()`'s "画像解釈の確認" panel, but once
  /// あがり牌 got a default value that panel's guard
  /// (`_confirmedWinningTileId == null`) stopped ever being true, so the
  /// first tap silently did nothing visible and the button looked broken
  /// until pressed a second time.
  Future<void> _runInterpretationAndAnalyze() async {
    if (_interpretation == null) {
      await _runInterpretation();
      if (!mounted || _interpretation == null) return;
    }
    await _confirmAndAnalyze();
  }

  Future<void> _confirmAndAnalyze() async {
    if (_interpretation == null) return;
    if (_operation == HandOperation.score && _confirmedWinningTileId == null) {
      _showError('あがり牌を選択してください');
      return;
    }

    final observation = _buildObservation();
    final confirmation = ConfirmationV1(
      operation: _operation,
      confirmedTiles: observation.observations
          .map(
            (item) => ConfirmedTile(
              observationId: item.observationId,
              tile: _tiles[item.index]!,
            ),
          )
          .toList(growable: false),
      confirmedWinningTileId: _operation == HandOperation.score
          ? _confirmedWinningTileId
          : null,
      confirmedMelds: List.unmodifiable(_confirmedMelds),
    );

    setState(() {
      _isScoring = true;
      _scoreResult = null;
      _analysisResult = null;
      _isNotWinning = false;
    });
    final requestEpoch = _requestEpoch.current;
    try {
      final state = await _api.confirmHand(
        request: InterpretationRequest(
          observation: observation,
          confirmation: confirmation,
        ),
      );
      if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
      final rules = RuleSet();
      switch (_operation) {
        case HandOperation.score:
          final winTile = state.hand.winTile;
          if (winTile == null) throw StateError('確定済みのあがり牌がありません');
          // Red-five tiles ("5mr"/"5pr"/"5sr") are already identified as
          // such by the recognizer — count them directly from the
          // confirmed hand instead of asking the user to separately keep
          // a manual 赤ドラ counter in sync with what they just
          // photographed (a duplicate, easy-to-forget input for
          // information the app already has).
          final akaDoraCount = [
            ...state.hand.closedTiles,
            for (final meld in state.hand.melds) ...meld.tiles,
          ].where((tile) => tile.endsWith('r')).length;
          final result = await _api.calculateScore(
            ScoreRequest(
              hand: HandInput(
                closedTiles: state.hand.closedTiles,
                melds: state.hand.melds
                    .map(
                      (meld) => Meld(
                        type: meld.type,
                        tiles: meld.tiles,
                        open: meld.open,
                      ),
                    )
                    .toList(growable: false),
                winTile: winTile,
              ),
              context: _context.copyWith(akaDora: akaDoraCount),
              rules: rules,
            ),
          );
          if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
          setState(() {
            _scoreResult = result;
            _isNotWinning = result == null;
          });
          _showResultDialog();
          break;
        case HandOperation.tenpai:
          final result = await _api.analyzeTenpai(
            state: state,
            context: _context,
            rules: rules,
          );
          if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
            setState(() => _analysisResult = result);
            _showResultDialog();
          }
          break;
        case HandOperation.discardAnalysis:
          final result = await _api.analyzeDiscards(
            state: state,
            context: _context,
            rules: rules,
          );
          if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
            setState(() => _analysisResult = result);
            _showResultDialog();
          }
          break;
      }
    } catch (error) {
      if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
        _showError('解析エラー: $error');
      }
    } finally {
      if (mounted) setState(() => _isScoring = false);
    }
  }

  void _onSlotTap(int index) async {
    final selected = await TileImagePicker.show(
      context,
      currentTile: _tiles[index],
    );
    if (selected != null && mounted) {
      setState(() {
        _tiles[index] = selected;
        _candidates[index] = [TileCandidate(tile: selected, confidence: 1.0)];
        _invalidateInterpretation();
      });
    }
  }

  /// Opens the game-context settings (場風/自風/リーチ/ドラ表示牌 etc., via
  /// `ContextInputPanel`) as a bottom sheet instead of always inline in the
  /// scroll — most hands don't need to touch these every time. Wrapped in
  /// `StatefulBuilder` so the sheet's own content redraws immediately after
  /// each edit; `ContextInputPanel` only re-renders when given a new
  /// `context_`, and a plain `setState` here rebuilds `ScanScreen`, not this
  /// separately-routed sheet.
  /// Applies a new `_context` and clears any stale result computed from the
  /// old one — shared by every place that edits it (the 詳細条件 sheet, the
  /// quick ツモ/ロン・リーチ controls in the bottom bar, and
  /// `GameStatePanel`). Callers still wrap this in their own `setState`.
  void _updateContext(ContextInput c) {
    _context = c;
    _scoreResult = null;
    _analysisResult = null;
    _isNotWinning = false;
  }

  void _showContextDetailsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: 12 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: ContextInputPanel(
                  context_: _context,
                  onChanged: (c) {
                    setState(() => _updateContext(c));
                    setSheetState(() {});
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _backToCamera() {
    setState(() {
      _phase = _ScanPhase.camera;
      _capturedBytes = null;
      _capturedImage = null;
      for (int i = 0; i < _maxPhysicalTiles; i++) {
        _tiles[i] = null;
        _predictedTiles[i] = null;
        _candidates[i] = [];
        _isClassifying[i] = false;
        _croppedImages[i] = null;
        _croppedImageThumbnails[i] = null;
        _tileQuads[i] = null;
      }
      _invalidateInterpretation();
      _isSendingTraining = false;
      _trainingDataSent = false;
      _isUndoingTraining = false;
      _sentTrainingEntryIds = [];
    });
    _startLiveDetection();
  }

  bool get _allDetectedTilesReady {
    final detected = [
      for (int index = 0; index < _maxPhysicalTiles; index++)
        if (_tileQuads[index] != null) index,
    ];
    return detected.isNotEmpty &&
        detected.every((index) => _tiles[index] != null);
  }

  // Any number of created boxes (13-18, to also cover kan hands) counts as
  // ready, as long as every one of them has been classified — not just
  // exactly 14, which used to make training-data submission impossible for
  // any hand with a kan (see "鳴き・槓を追加").
  bool get _trainingTilesReady {
    final created = [
      for (int index = 0; index < _maxPhysicalTiles; index++)
        if (_croppedImages[index] != null) index,
    ];
    return created.isNotEmpty &&
        created.every(
          (index) => _tiles[index] != null && _predictedTiles[index] != null,
        );
  }

  int get _visibleSlotCount {
    var last = -1;
    for (int index = 0; index < _maxPhysicalTiles; index++) {
      if (_tileQuads[index] != null || _tiles[index] != null) last = index;
    }
    return math.max(14, last + 1).clamp(14, _maxPhysicalTiles);
  }

  String _operationLabel(HandOperation operation) => switch (operation) {
    HandOperation.score => '点数計算',
    HandOperation.tenpai => 'テンパイ・待ち',
    HandOperation.discardAnalysis => '打牌分析',
  };

  String _analysisSummary(Map<String, dynamic> result) {
    final shanten = result['shanten'];
    final improving = result['improving_tiles'];
    if (improving is List) {
      final tiles = improving
          .whereType<Map>()
          .map((item) => '${item['tile']}(${item['remaining']})')
          .join('、');
      return 'シャンテン数: $shanten\n有効牌・待ち: ${tiles.isEmpty ? 'なし' : tiles}';
    }
    final discards = result['discards'];
    if (discards is List) {
      final lines = discards.whereType<Map>().take(8).map((item) {
        final options = item['improving_tiles'];
        final count = options is List
            ? options.fold<int>(
                0,
                (sum, option) =>
                    sum + ((option as Map)['remaining'] as num).toInt(),
              )
            : 0;
        return '${item['discard']}: ${item['shanten']}シャンテン / 有効牌$count枚';
      });
      return ['シャンテン数: $shanten', ...lines].join('\n');
    }
    return result.toString();
  }

  /// Physical-tile indices eligible to join a new meld: identified, and not
  /// already claimed by an existing `ConfirmedMeld`.
  List<int> get _meldEligibleIndices => [
    for (int index = 0; index < _maxPhysicalTiles; index++)
      if (_tiles[index] != null &&
          !_confirmedMelds.any(
            (meld) => meld.observationIds.contains(
              'tile-${index.toString().padLeft(3, '0')}',
            ),
          ))
        index,
  ];

  bool _isConfirmedMeldMember(int index) => _confirmedMelds.any(
    (meld) => meld.observationIds.contains(
      'tile-${index.toString().padLeft(3, '0')}',
    ),
  );

  void _resetMelds() {
    setState(() {
      _confirmedMelds.clear();
      _invalidateAnalysis();
    });
  }

  void _startMeldSelection() {
    setState(() {
      _isSelectingMeld = true;
      _meldSelection.clear();
      _deleteAffordanceIndex = null;
    });
  }

  void _cancelMeldSelection() {
    setState(() {
      _isSelectingMeld = false;
      _meldSelection.clear();
    });
  }

  void _toggleMeldSelection(int index) {
    if (!_meldEligibleIndices.contains(index)) return;
    setState(() {
      if (_meldSelection.contains(index)) {
        _meldSelection.remove(index);
      } else if (_meldSelection.length < 4) {
        _meldSelection.add(index);
      }
    });
  }

  List<String> get _meldSelectionTileCodes => _meldSelection
      .map((index) => _tiles[index])
      .whereType<String>()
      .toList(growable: false);

  /// Appends a `ConfirmedMeld` built from the current `_meldSelection` and
  /// exits selection mode. [type]/[open] are the wire values to record —
  /// callers must already know these are valid for the current selection
  /// (pon/chi from `detectMeldType`, or the user's own 暗槓/明槓 choice for a
  /// 4-tile kan).
  void _confirmMeldSelection({required String type, required bool open}) {
    final observationIds = _meldSelection
        .map((index) => 'tile-${index.toString().padLeft(3, '0')}')
        .toList(growable: false);
    setState(() {
      _confirmedMelds.add(
        ConfirmedMeld(observationIds: observationIds, type: type, open: open),
      );
      _isSelectingMeld = false;
      _meldSelection.clear();
      _invalidateAnalysis();
    });
  }

  /// Compact ツモ/ロン + リーチ(一発) controls for the bottom action bar —
  /// the two win-time conditions used on nearly every hand, pulled out of
  /// the "詳細条件" sheet (`ContextInputPanel`) so they don't need an extra
  /// tap to reach. Everything else (海底・河底・嶺上・槍槓・地和・天和) stays
  /// in that sheet.
  Widget _buildQuickWinConditions() {
    final isTsumo = _context.winType == 'tsumo';
    final isNoneRiichi = !_context.riichi && !_context.doubleRiichi;
    final isRiichi = _context.riichi && !_context.doubleRiichi;
    final isDoubleRiichi = _context.doubleRiichi;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _quickChip(
          'ツモ',
          isTsumo,
          () => setState(
            () => _updateContext(_context.copyWith(winType: 'tsumo')),
          ),
        ),
        const SizedBox(width: 3),
        _quickChip(
          'ロン',
          !isTsumo,
          () => setState(
            () => _updateContext(_context.copyWith(winType: 'ron')),
          ),
        ),
        const SizedBox(width: 8),
        _quickChip(
          'なし',
          isNoneRiichi,
          () => setState(
            () => _updateContext(
              _context.copyWith(
                riichi: false,
                doubleRiichi: false,
                ippatsu: false,
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        _quickChip(
          'リーチ',
          isRiichi,
          () => setState(
            () => _updateContext(
              _context.copyWith(riichi: true, doubleRiichi: false),
            ),
          ),
        ),
        const SizedBox(width: 3),
        _quickChip(
          'Wリーチ',
          isDoubleRiichi,
          () => setState(
            () => _updateContext(
              _context.copyWith(riichi: true, doubleRiichi: true),
            ),
          ),
        ),
        if (_context.riichi || _context.doubleRiichi) ...[
          const SizedBox(width: 3),
          _quickChip(
            '一発',
            _context.ippatsu,
            () => setState(
              () => _updateContext(
                _context.copyWith(ippatsu: !_context.ippatsu),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _quickChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: Colors.greenAccent, width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.greenAccent : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// ◀/▶ controls stepping あがり牌 through `_identifiedIndices`.
  /// Combined 副露 add/reset controls (left) and あがり牌 ◀/▶ control
  /// (right) in a single row, directly below the thumbnail row — no boxed
  /// section around it (an earlier version wrapped 副露 controls in their
  /// own always-visible `Container`, which the user found needlessly tall).
  /// While `_isSelectingMeld`, this row is replaced entirely by
  /// `_buildMeldSelectionStatus()`.
  Widget _buildTileControlsRow() {
    if (_isSelectingMeld) return _buildMeldSelectionStatus();

    final position = _winningTilePosition;
    final lastPosition = _identifiedIndices.length - 1;
    final winningTileCode = _confirmedWinningTileId == null
        ? null
        : _tiles[int.parse(_confirmedWinningTileId!.split('-').last)];

    return Row(
      children: [
        TextButton.icon(
          onPressed: _meldEligibleIndices.isEmpty ? null : _startMeldSelection,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('副露を追加'),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: _confirmedMelds.isEmpty ? null : _resetMelds,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('副露をリセット'),
        ),
        const Spacer(),
        if (_operation == HandOperation.score &&
            _identifiedIndices.isNotEmpty) ...[
          const Text(
            'あがり牌',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          IconButton(
            onPressed: position == null || position > 0
                ? () => _moveWinningTile(-1)
                : null,
            icon: const Icon(Icons.chevron_left),
            color: Colors.white70,
          ),
          SizedBox(
            width: 30,
            height: 40,
            child: winningTileCode == null
                ? null
                : TileGlyph(
                    tileCode: winningTileCode,
                    fallbackTextStyle: const TextStyle(color: Colors.amber),
                  ),
          ),
          IconButton(
            onPressed: position == null || position < lastPosition
                ? () => _moveWinningTile(1)
                : null,
            icon: const Icon(Icons.chevron_right),
            color: Colors.white70,
          ),
        ],
      ],
    );
  }

  /// The inline status/confirm row shown while `_isSelectingMeld` — replaces
  /// `MeldTilePicker`'s bottom sheet: the user taps thumbnails in the
  /// results row directly (see `_toggleMeldSelection`) instead of picking
  /// from a separate grid, and pon/chi/kan is inferred from what they picked
  /// (`detectMeldType`) instead of an explicit type dropdown.
  Widget _buildMeldSelectionStatus() {
    final codes = _meldSelectionTileCodes;
    final detection = detectMeldType(codes);
    final count = _meldSelection.length;
    final target = count == 4 ? 4 : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'サムネイルをタップして3枚（チー/ポン）または4枚（槓）選択 '
          '($count/$target)',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: _cancelMeldSelection,
              child: const Text('キャンセル'),
            ),
            const SizedBox(width: 8),
            if (detection == MeldDetection.kan) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _confirmMeldSelection(
                    type: 'ankan',
                    open: false,
                  ),
                  child: const Text('暗槓（閉じ）'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      _confirmMeldSelection(type: 'kan', open: true),
                  child: const Text('明槓（開き）'),
                ),
              ),
            ] else
              Expanded(
                child: FilledButton(
                  onPressed:
                      detection == MeldDetection.pon ||
                          detection == MeldDetection.chi
                      ? () => _confirmMeldSelection(
                          type: detection == MeldDetection.pon
                              ? 'pon'
                              : 'chi',
                          open: true,
                        )
                      : null,
                  child: const Text('確定'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Shows the score/analysis result (`_scoreResult`/`_analysisResult`/
  /// `_isNotWinning`, whichever `_confirmAndAnalyze` just set) as a popup
  /// instead of appending it inline to the scrolling results column —
  /// closes only via the ✕ button (`barrierDismissible: false`, no
  /// tap-outside-to-dismiss), so a result can't be lost by an accidental
  /// tap. Reuses the exact same content widgets the inline version used.
  void _showResultDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ),
                if (_isNotWinning) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '上がりの形になっていません',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_scoreResult != null)
                  ScoreResultPanel(scoreResponse: _scoreResult!),
                if (_analysisResult != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _analysisSummary(_analysisResult!),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterpretationConfirmation() {
    final interpretation = _interpretation;
    if (interpretation == null) return const SizedBox.shrink();
    if (!(_operation == HandOperation.score &&
        _confirmedWinningTileId == null)) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '画像解釈の確認',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          Text(
            'あがり牌: 上の牌画像の枠の下にある◀▶ボタンで選べます',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTrainingData() async {
    if (_isSendingTraining || _trainingDataSent) return;
    final createdIndices = [
      for (int index = 0; index < _maxPhysicalTiles; index++)
        if (_croppedImages[index] != null) index,
    ];
    final images = [for (final index in createdIndices) _croppedImages[index]!];
    final tiles = [for (final index in createdIndices) _tiles[index]!];
    final predictedTiles = [
      for (final index in createdIndices) _predictedTiles[index]!,
    ];
    final predictedConfidences = [
      for (final index in createdIndices)
        _candidates[index].isEmpty ? null : _candidates[index].first.confidence,
    ];
    if (images.isEmpty ||
        !createdIndices.every(
          (index) => _tiles[index] != null && _predictedTiles[index] != null,
        )) {
      _showError('全ての牌の識別結果が必要です');
      return;
    }

    setState(() => _isSendingTraining = true);
    try {
      final result = await _trainingClient.uploadBatch(
        images: images,
        tileCodes: tiles,
        predictedTileCodes: predictedTiles,
        predictedConfidences: predictedConfidences,
        recognitionModelVersion: _classifier.modelVersion,
        recognitionModelSource: _classifier.modelSource,
        preprocessingVersion: _classifier.preprocessingVersion,
      );
      if (mounted) {
        setState(() {
          _trainingDataSent = true;
          _sentTrainingEntryIds = result.entryIds;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.uploadedCount}枚の学習データを送信しました')),
        );
      }
    } catch (e) {
      _showError('送信エラー: $e');
    } finally {
      if (mounted) setState(() => _isSendingTraining = false);
    }
  }

  Future<void> _undoTrainingData() async {
    if (_isUndoingTraining || !_trainingDataSent) return;
    setState(() => _isUndoingTraining = true);
    try {
      final deletedCount = await _trainingClient.deleteEntries(
        _sentTrainingEntryIds,
      );
      if (mounted) {
        setState(() {
          _trainingDataSent = false;
          _sentTrainingEntryIds = [];
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$deletedCount枚の学習データを取り消しました')));
      }
    } catch (e) {
      _showError('取り消しエラー: $e（管理者権限のアカウントが必要です）');
    } finally {
      if (mounted) setState(() => _isUndoingTraining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // No AppBar: its only job would have been a back button, which
      // duplicated "撮り直す" (retake stays within this screen, keeping the
      // camera controller alive; a real back button would instead pop the
      // whole screen back to Home). Resolved by dropping the AppBar rather
      // than keeping both — see FEZ-191 follow-up.
      body: switch (_phase) {
        _ScanPhase.camera => _buildCameraPhase(),
        _ScanPhase.detecting => _buildDetectingPhase(),
        _ScanPhase.results => _buildResultsPhase(),
      },
    );
  }

  // ════════════════════════════════════════
  // Phase: Detecting (automatic tile detection)
  // ════════════════════════════════════════

  Widget _buildDetectingPhase() {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_capturedBytes != null)
            Opacity(
              opacity: 0.4,
              child: Image.memory(
                _capturedBytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.greenAccent),
                SizedBox(height: 12),
                Text('牌を検出中...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════
  // Phase 1: Camera
  // ════════════════════════════════════════

  Widget _buildCameraPhase() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: Text('カメラ初期化中...', style: TextStyle(color: Colors.white)),
      );
    }

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: CameraPreview(_controller!)),
          // Simple instruction
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '解析対象の牌がすべて映るように撮影してください',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
          // Live detection tile-count badge + auto/manual shutter toggle
          // (FEZ-96 verification: auto-shutter behavior is unconfirmed on
          // real devices, so manual capture must remain available).
          Positioned(
            top: 8,
            right: 12,
            child: Row(
              children: [
                _buildLiveTileCountBadge(),
                const SizedBox(width: 8),
                _buildAutoCaptureToggle(),
              ],
            ),
          ),
          // Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: _isCapturing
                        ? Colors.grey
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 32,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTileCountBadge() {
    final count = _liveDetectorResult?.tileCount ?? 0;
    final isReady = count == TileDetector.targetTileCount;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isReady ? Colors.green : Colors.black54).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.search,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '$count / ${TileDetector.targetTileCount} 牌',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: isReady ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoCaptureToggle() {
    return GestureDetector(
      onTap: _toggleAutoCapture,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _autoCaptureEnabled
                  ? Icons.auto_awesome
                  : Icons.auto_awesome_outlined,
              color: _autoCaptureEnabled ? Colors.amberAccent : Colors.white54,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _autoCaptureEnabled ? '自動' : '手動',
              style: TextStyle(
                color: _autoCaptureEnabled
                    ? Colors.amberAccent
                    : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════
  // Phase 3: Results
  // ════════════════════════════════════════

  Widget _buildTileMarkerOverlay() {
    return TileMarkerOverlay(
      imageBytes: _capturedBytes!,
      imageWidth: _capturedImage!.width,
      imageHeight: _capturedImage!.height,
      boxes: _tileQuads.map((q) => q?.boundingRect).toList(),
      tiles: _tiles,
      onTap: _openBoxEditor,
    );
  }

  Widget _buildResultsPhase() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Retake, above the photo as its own bar (not overlaid on
                  // it) so it can't be mis-tapped during the photo's own
                  // pinch-zoom/pan gestures, and not pinned to the bottom
                  // bar either — it scrolls away with the rest of the
                  // content like any other one-off decision made right
                  // after reviewing the capture (see FEZ-191 follow-up: it
                  // used to live in the bottom action bar, which hid it
                  // entirely until every tile was identified — too late to
                  // catch an obviously bad photo).
                  // Retake (left) / training-data send-undo (right, opposite
                  // side) — both one-off decisions made right after
                  // reviewing the capture, not pinned to the bottom bar (see
                  // FEZ-191 follow-up for why retake lives here).
                  Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _backToCamera,
                          icon: const Icon(Icons.replay, size: 18, color: Colors.white70),
                          label: const Text(
                            '撮り直す',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(AppConfig.apiBaseUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(
                            Icons.dashboard_outlined,
                            size: 18,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'Webダッシュボード',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        if (_trainingTilesReady)
                          TextButton.icon(
                            onPressed: _isSendingTraining || _isUndoingTraining
                                ? null
                                : _trainingDataSent
                                ? _undoTrainingData
                                : _sendTrainingData,
                            icon: _isSendingTraining || _isUndoingTraining
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.orangeAccent,
                                    ),
                                  )
                                : Icon(
                                    _trainingDataSent
                                        ? Icons.undo
                                        : Icons.school,
                                    size: 18,
                                    color: Colors.orangeAccent,
                                  ),
                            label: Text(
                              _isSendingTraining
                                  ? '送信中...'
                                  : _isUndoingTraining
                                  ? '取り消し中...'
                                  : _trainingDataSent
                                  ? '取り消す'
                                  : '学習データ送信',
                              style: const TextStyle(color: Colors.orangeAccent),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Full photo with detected-tile markers, capped to a
                  // fraction of the screen height so it doesn't dominate the
                  // scroll — `AspectRatio` still fits inside that cap using
                  // the photo's own aspect ratio. Tapping a marker opens the
                  // full-screen box editor for that tile (`_openBoxEditor`);
                  // pinch-zoom is safe to leave on here since nothing on
                  // this screen does its own dragging anymore (editing
                  // happens in `TileBoxEditorScreen`, a separate route with
                  // no zoom of its own).
                  if (_capturedBytes != null) ...[
                    // A landscape hand photo (typically ~16:9) genuinely
                    // cannot both fill this app's wide-but-short landscape
                    // screen width AND stay a modest fraction of its height
                    // — filling ~850 logical px of width at 16:9 needs
                    // ~478px of height, more than this device's entire
                    // 402px-tall screen. Capping height alone (as an
                    // earlier version did) left the image pillarboxed
                    // (narrow, lots of empty width) since AspectRatio still
                    // has to shrink width to match a short height. Capping
                    // BOTH width and height to a moderate size and
                    // centering instead — rather than stretching to the
                    // column's full width — is the deliberate middle
                    // ground: bigger than the pillarboxed version, but
                    // still leaves the controls below reachable without
                    // this photo alone eating most of the screen.
                    Center(
                      child: RepaintBoundary(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.55,
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.55,
                          ),
                          child: AspectRatio(
                            aspectRatio:
                                _capturedImage!.width / _capturedImage!.height,
                            child: InteractiveViewer(
                              minScale: 1.0,
                              maxScale: 4.0,
                              child: _buildTileMarkerOverlay(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Cropped images preview, each paired with its identified
                  // tile's illustration directly below (or "?" until "識別実行"
                  // has been run for it), plus a trailing add-box tile when a
                  // slot is still undetected. Tapping the crop opens the box
                  // editor (`_openBoxEditor`); tapping the illustration opens
                  // the image-based picker (`_onSlotTap`) to correct it
                  // manually — except while `_isSelectingMeld`, when every
                  // tap instead toggles that slot's meld membership
                  // (`_toggleMeldSelection`). Long-pressing a crop (outside
                  // meld-selection mode) shows a ✕ badge to delete that slot
                  // (`_deleteAffordanceIndex`/`_handleThumbnailTap`). The
                  // あがり牌 frame and confirmed-meld-membership frame are
                  // border overlays; あがり牌 itself moves via the ◀/▶
                  // controls below the row, not by dragging.
                  SizedBox(
                    height: 118,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          _visibleSlotCount +
                          (_tileQuads.any((q) => q == null) ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _visibleSlotCount) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: GestureDetector(
                              onTap: _addMissingTileBox,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ),
                          );
                        }
                        final thumb = _croppedImageThumbnails[i];
                        if (thumb == null) return const SizedBox(width: 40);
                        final tile = _tiles[i];
                        final tileAsset = tile == null
                            ? null
                            : tileAssetPath(tile);
                        final winningTileId =
                            'tile-${i.toString().padLeft(3, '0')}';
                        final isWinningTile =
                            _confirmedWinningTileId == winningTileId;
                        final isMeldSelected = _meldSelection.contains(i);
                        final isMeldEligible = _meldEligibleIndices.contains(
                          i,
                        );
                        final canBeWinningTile =
                            _operation == HandOperation.score &&
                            tile != null &&
                            !_isSelectingMeld;
                        final showMeldFrame =
                            !_isSelectingMeld && _isConfirmedMeldMember(i);

                        final Widget cropImage = GestureDetector(
                          onTap: _isSelectingMeld
                              ? () => _toggleMeldSelection(i)
                              : () => _handleThumbnailTap(
                                  () => _openBoxEditor(i),
                                ),
                          onLongPress: _isSelectingMeld
                              ? null
                              : () =>
                                    setState(() => _deleteAffordanceIndex = i),
                          child: Image.memory(
                            thumb,
                            width: 40,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        );

                        final Widget glyphCore = GestureDetector(
                          onTap: _isSelectingMeld
                              ? () => _toggleMeldSelection(i)
                              : () =>
                                    _handleThumbnailTap(() => _onSlotTap(i)),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: _isClassifying[i]
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white54,
                                    ),
                                  )
                                : tileAsset != null
                                ? Image.asset(tileAsset, fit: BoxFit.contain)
                                : const Text(
                                    '?',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        );

                        // あがり牌 (amber) / confirmed meld membership
                        // (light blue) borders sit around the glyph only,
                        // not the crop thumbnail above it.
                        final Widget glyph = Stack(
                          clipBehavior: Clip.none,
                          children: [
                            glyphCore,
                            if (canBeWinningTile && isWinningTile)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.amber,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            if (showMeldFrame)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.lightBlueAccent,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );

                        Widget column = Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [cropImage, const SizedBox(height: 4), glyph],
                        );

                        // Meld-selection-mode affordance: a colored border
                        // on a selected slot, dimmed when the slot can't
                        // join a meld (unidentified or already claimed).
                        if (_isSelectingMeld) {
                          column = Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: isMeldSelected
                                  ? Border.all(
                                      color: Colors.greenAccent,
                                      width: 2,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Opacity(
                              opacity: isMeldEligible ? 1.0 : 0.35,
                              child: column,
                            ),
                          );
                        }

                        // ✕ delete badge when this slot's long-press
                        // affordance is showing.
                        final Widget framed = Stack(
                          clipBehavior: Clip.none,
                          children: [
                            column,
                            if (_deleteAffordanceIndex == i)
                              Positioned(
                                top: -6,
                                right: -6,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _clearTileSlot(i);
                                    _deleteAffordanceIndex = null;
                                  }),
                                  child: const Icon(
                                    Icons.cancel,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        );

                        return RepaintBoundary(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: framed,
                          ),
                        );
                      },
                    ),
                  ),

                  // Combined 副露 add/reset + あがり牌 ◀/▶ controls, one
                  // row directly under the thumbnails. Gated on 識別実行
                  // having produced a tile for every detected box — before
                  // that there's nothing yet to mark as 副露 or あがり牌.
                  if (_allDetectedTilesReady) ...[
                    const SizedBox(height: 4),
                    _buildTileControlsRow(),
                    const SizedBox(height: 12),
                  ],

                  // Round/hand facts (winds, dora indicators, honba,
                  // kyotaku) — only relevant to score calculation, unlike
                  // the win-time conditions in the "詳細条件" sheet, which
                  // apply here too but not to tenpai/discard-analysis mode.
                  if (_operation == HandOperation.score) ...[
                    GameStatePanel(
                      context_: _context,
                      onChanged: (c) => setState(() => _updateContext(c)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_interpretation != null) ...[
                    _buildInterpretationConfirmation(),
                    const SizedBox(height: 12),
                  ],

                ],
              ),
            ),
          ),

          // Fixed action bar: always reachable without scrolling, unlike
          // everything above. Left to right: function (HandOperation)
          // dropdown, quick ツモ/ロン・リーチ(一発) controls + 詳細条件
          // (score mode only), then the main action — "識別実行" until every
          // detected tile has a result, then a plain "実行" that runs
          // `_runInterpretationAndAnalyze` (interpretation + confirm+analyze
          // in one tap; seealso that method's own doc comment for why it's
          // not split into two taps anymore). Retake lives in its own bar
          // above the photo instead — a
          // "撮り直す" here was only ever reachable once identification
          // finished, too late to catch an obviously bad photo, and
          // duplicated in intent with a since-removed AppBar back button.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<HandOperation>(
                      value: _operation,
                      isDense: true,
                      dropdownColor: Colors.grey.shade900,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: HandOperation.values
                          .map(
                            (operation) => DropdownMenuItem(
                              value: operation,
                              child: Text(_operationLabel(operation)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (operation) {
                        if (operation == null) return;
                        setState(() {
                          _operation = operation;
                          _invalidateInterpretation();
                        });
                      },
                    ),
                  ),
                ),
                if (_operation == HandOperation.score) ...[
                  const SizedBox(width: 8),
                  // ツモ/ロン・リーチ(一発) — used on nearly every hand, so
                  // they sit directly in the bar instead of behind 詳細条件
                  // (see `_buildQuickWinConditions`). Horizontally
                  // scrollable as a safety margin against overflow on a
                  // narrower device; this app's own landscape screens have
                  // room to show it in full without scrolling.
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildQuickWinConditions(),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  // Riichi/ippatsu/haitei etc. only affect score
                  // calculation, so there's nothing useful to set here in
                  // tenpai/discard-analysis mode. The rare situational
                  // flags (海底・河底・嶺上・槍槓・地和・天和) — everything
                  // except ツモ/ロン・リーチ(一発), which moved to the bar
                  // itself above — still live behind this icon.
                  onPressed: _operation == HandOperation.score
                      ? _showContextDetailsSheet
                      : null,
                  icon: const Icon(Icons.tune),
                  color: Colors.white70,
                  disabledColor: Colors.white24,
                  tooltip: '詳細条件',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: !_allDetectedTilesReady
                      ? OutlinedButton.icon(
                          onPressed: _croppedImages.any((c) => c != null)
                              ? _runClassification
                              : null,
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('識別実行'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.greenAccent,
                            side: const BorderSide(color: Colors.greenAccent),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: !_isScoring && !_isInterpreting
                              ? _runInterpretationAndAnalyze
                              : null,
                          icon: _isScoring || _isInterpreting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow, size: 20),
                          label: const Text('実行'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.withValues(
                              alpha: 0.6,
                            ),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
