import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../widgets/photo_input.dart';
import '../services/photo_import.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint, kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/tile_classifier.dart';
import '../services/api_client.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';
import '../models/history_entry.dart';
import '../models/ai_chat_message.dart';
import '../models/interpretation_request.dart';
import '../models/scan_purpose.dart';
import '../models/interpretation_result.dart';
import '../models/tile_observation.dart';
import '../widgets/tile_image_picker.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/game_state_panel.dart';
import '../widgets/score_result_panel.dart';
import '../widgets/analysis_result_panel.dart';
import '../widgets/tile_marker_overlay.dart';
import '../widgets/tile_count_selector.dart';
import '../widgets/ai_chat_sheet.dart';
import '../services/training_data_client.dart';
import '../services/tile_segmenter.dart';
import '../services/tile_assets.dart';
import '../services/meld_detector.dart';
import '../models/tile_quad.dart';
import '../services/scan_observation_builder.dart';
import '../services/request_epoch.dart';
import '../services/history_service.dart';
import '../services/auth_service.dart';
import '../services/capture_framing.dart';
import '../services/performance_trace.dart';
import 'tile_box_editor_screen.dart';
import 'photo_crop_screen.dart';
import '../services/hand_error_messages.dart';
import '../services/purpose_switch.dart';
import '../widgets/purpose_switch_dialogs.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/status_banner.dart';
import '../widgets/toggle_chip.dart';
import '../widgets/screen_header.dart';

class ScoreWinnerOption {
  const ScoreWinnerOption({required this.label, required this.context});

  final String label;
  final ContextInput context;
}

class ScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final bool autoClassify;
  final String initialRoundWind;
  final ValueChanged<String>? onRoundWindChanged;
  final ScanPurpose purpose;
  final bool showTrainingDataActions;
  final ContextInput? initialContext;
  final List<ScoreWinnerOption> winnerOptions;
  final int? initialWinnerIndex;
  final ValueChanged<int>? onScoreConfirmed;
  final String? historyRoundLabel;
  final MahjongRuleSettings ruleSettings;

  const ScanScreen({
    super.key,
    required this.cameras,
    this.autoClassify = true,
    this.initialRoundWind = 'E',
    this.onRoundWindChanged,
    this.purpose = ScanPurpose.score,
    this.showTrainingDataActions = false,
    this.initialContext,
    this.winnerOptions = const [],
    this.initialWinnerIndex,
    this.onScoreConfirmed,
    this.historyRoundLabel,
    this.ruleSettings = const MahjongRuleSettings(),
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanPhase { camera, detecting, results }

enum _WinConditionStep { riichi, dora, uraDora, waiting }

class _ScanScreenState extends State<ScanScreen> {
  static const int _maxPhysicalTiles = 18;

  /// Tile boxes can be added up to [_maxPhysicalTiles] and deleted down to
  /// this many (13: the smallest hand any check works on).
  static const int _minTileBoxes = 13;
  /// Up to four 槓子; each adds one physical tile to the purpose's base.
  static const int _maxKans = 4;
  CameraController? _controller;
  String? _cameraInitError;
  final TileClassifier _classifier = TileClassifier();
  late final Future<void> _classifierInitialization;
  final ApiClient _api = ApiClient();
  final TrainingDataClient _trainingClient = TrainingDataClient();
  final HistoryService _historyService = HistoryService();
  Future<void> _historyUpdateQueue = Future.value();
  // Not final: 「別の確認へ」 starts a new history entry for the new purpose
  // instead of overwriting the previous purpose's result.
  String _historyEntryId = HistoryService.createId();
  DateTime _historyCreatedAt = DateTime.now().toUtc();

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

  // FEZ-93 recovery flow: the sub-region of `_capturedImage` that detection
  // was last restricted to (via `PhotoCropScreen`), or null when the whole
  // photo was used. `_capturedImage`/`_capturedBytes` themselves are never
  // mutated by cropping — this is purely a record of what to re-open the
  // crop editor with, and what "元の範囲に戻す" resets away. Always the
  // exact (integer, clamped) rect actually cropped to — not the raw
  // `PhotoCropScreen` selection — so it lines up pixel-for-pixel with
  // `_cropDisplayBytes` and the offset applied to detected boxes.
  Rect? _cropRegion;
  // The re-encoded JPEG for just `_cropRegion` (already produced once, to
  // feed detection — see `_redetectInRegion`), reused as the results
  // screen's preview image instead of the uncropped `_capturedBytes` so the
  // photo shown matches what detection actually saw. Null when `_cropRegion`
  // is null (the full original photo is shown, uncompressed a second time).
  Uint8List? _cropDisplayBytes;

  // Capture is manual only (decided 2026-10-04): the live auto-shutter of
  // FEZ-96 counted stray candidates (often ~100) before capture, which read
  // as poor accuracy, so there is no detection until the shutter is tapped.
  Timer? _scoreRecalculationTimer;
  PerformanceTrace? _performanceTrace;
  int? _expectedTileCount;
  int? _autoDetectedTileCount;

  bool _isCapturing = false;
  bool _isRunningFullClassification = false;
  bool _isScoring = false;
  bool _isInterpreting = false;
  bool _isSendingTraining = false;
  bool _trainingDataSent = false;
  bool _isUndoingTraining = false;
  List<String> _sentTrainingEntryIds = [];
  ScoreResponse? _tsumoScoreResult;
  ScoreResponse? _ronScoreResult;
  bool _isNotWinning = false;
  InterpretationResult? _interpretation;
  String? _confirmedWinningTileId;
  // Tracks whether `_confirmedWinningTileId` came from the user moving it
  // themselves (the ◀/▶ buttons), as opposed to the rightmost-tile default
  // below or the AI's own suggestion in `_runInterpretation` — only a
  // manual choice may never be silently overwritten.
  bool _winningTileManuallySet = false;
  final List<ConfirmedMeld> _confirmedMelds = [];
  // The purpose currently shown on the results screen. Starts as
  // `widget.purpose` and changes only through 「別の確認へ」.
  late ScanPurpose _purpose;
  late HandOperation _operation;
  Map<String, dynamic>? _analysisResult;
  List<AIChatMessage> _chatMessages = [];
  final RequestEpoch _requestEpoch = RequestEpoch();

  late ContextInput _context;
  _WinConditionStep _winConditionStep = _WinConditionStep.riichi;
  bool _winConditionsComplete = false;
  bool _recognitionComplete = false;
  int _doraSlotCount = 1;
  int? _selectedWinnerIndex;
  bool _resumeWinConditionsAfterRetake = false;

  bool get _usesWinConditionWizard =>
      widget.onScoreConfirmed != null && widget.purpose == ScanPurpose.score;

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
  }

  /// Pre-fill the あがり牌 from the image's own reading, unless the user chose
  /// it themselves. Only score uses an あがり牌.
  void _applySuggestedWinningTile(InterpretationResult result) {
    final suggestedId = result.winningTile.observationId;
    if (_operation == HandOperation.score &&
        !_winningTileManuallySet &&
        suggestedId != null &&
        result.winningTile.status != FactStatus.unknown) {
      _confirmedWinningTileId = suggestedId;
    }
  }

  /// Physical-tile indices with an identified tile, ascending — the ◀/▶
  /// あがり牌 controls step through exactly this list.
  List<int> get _identifiedIndices => [
    for (int index = 0; index < _maxPhysicalTiles; index++)
      if (_tiles[index] != null) index,
  ];

  void _setWinningTile(int index) {
    setState(() {
      _confirmedWinningTileId = 'tile-${index.toString().padLeft(3, '0')}';
      _winningTileManuallySet = true;
      _invalidateAnalysisAndMaybeRecalculate();
    });
  }

  /// Picks the あがり牌 from the identified tiles, opened by tapping the
  /// 「↑ 和了牌」 mark (device check 2026-10-04: ◀/▶ stepping was hard to
  /// follow once the tile row scrolls sideways).
  Future<void> _showWinningTileDialog() async {
    final current = _confirmedWinningTileId == null
        ? null
        : int.tryParse(_confirmedWinningTileId!.split('-').last);
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('和了牌を選択')),
            CloseButton(onPressed: () => Navigator.pop(dialogContext)),
          ],
        ),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final index in _concealedIndices)
                Semantics(
                  button: true,
                  selected: index == current,
                  label: '${_tiles[index]}を和了牌にする',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: ValueKey('winning-choice-$index'),
                    onTap: () => Navigator.pop(dialogContext, index),
                    child: Container(
                      width: 44,
                      height: 58,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: index == current ? _colors.soft : null,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        border: Border.all(
                          color: index == current
                              ? _colors.winningTile
                              : _scheme.outlineVariant,
                          width: index == current ? 2 : 1,
                        ),
                      ),
                      child: TileGlyph(tileCode: _tiles[index]!),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) _setWinningTile(selected);
  }

  /// Why ツモ / ロン has no score while the other side has one.
  String? _tsumoNote;
  String? _ronNote;

  /// The last failure of 実行 (interpretation, analysis or score), shown on
  /// screen until the next run or edit instead of a short-lived snack bar.
  String? _runError;

  void _invalidateAnalysis() {
    _requestEpoch.invalidate();
    _analysisResult = null;
    _chatMessages = [];
    _tsumoScoreResult = null;
    _ronScoreResult = null;
    _tsumoNote = null;
    _ronNote = null;
    _isNotWinning = false;
    _runError = null;
  }

  bool get _hasScoreCalculation =>
      _tsumoScoreResult != null ||
      _ronScoreResult != null ||
      _isNotWinning ||
      _isScoring;

  void _invalidateAnalysisAndMaybeRecalculate() {
    final shouldRecalculate =
        _phase == _ScanPhase.results &&
        _operation == HandOperation.score &&
        _interpretation != null &&
        _allDetectedTilesReady &&
        _hasScoreCalculation;
    _invalidateAnalysis();
    _isScoring = false;
    if (shouldRecalculate) _scheduleScoreRecalculation();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scheduleRecognitionFirstPaint() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final trace = _performanceTrace;
      if (trace == null || !mounted || _phase != _ScanPhase.results) return;
      trace.mark('recognitionFirstPaint');
      trace.log();
      if (identical(_performanceTrace, trace)) _performanceTrace = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _purpose = widget.purpose;
    _operation = _purpose.operation;
    _expectedTileCount = _purpose.defaultTileCount;
    _context =
        widget.initialContext ??
        // Single checks start as 東家 (親); a match passes the seat's own.
        ContextInput(
          roundWind: widget.initialRoundWind,
          seatWind: 'E',
          isDealer: true,
        );
    _selectedWinnerIndex = widget.initialWinnerIndex;
    if (!kIsWeb) _initCamera();
    _classifierInitialization = _initClassifier();
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

  CameraDescription _preferredCamera() {
    final rearCameras = widget.cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList();
    final candidates = rearCameras.isEmpty ? widget.cameras : rearCameras;
    for (final lensType in [CameraLensType.ultraWide, CameraLensType.wide]) {
      for (final camera in candidates) {
        if (camera.lensType == lensType) return camera;
      }
    }
    return candidates.first;
  }

  Future<void> _initCamera([CameraDescription? camera]) async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        setState(() => _cameraInitError = '利用できるカメラが見つかりませんでした');
      }
      return;
    }
    final selectedCamera = camera ?? _preferredCamera();
    final previousController = _controller;
    if (previousController != null) {
      await previousController.dispose();
    }
    if (mounted) {
      setState(() {
        _controller = null;
        _cameraInitError = null;
      });
    }

    final controller = CameraController(
      selectedCamera,
      // On iOS, `high` is only 720x1280. In portrait that leaves a
      // 720x405 image after the 16:9 result crop: roughly 51 horizontal
      // pixels per tile for a 14-tile hand, which is far below the
      // classifier's 224x224 input. `ultraHigh` targets 2160x3840, retaining
      // about 154 pixels per tile after the same crop while still allowing
      // the plugin to fall back on devices that cannot provide it.
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      // A predictable YUV plane layout on both Android and iOS;
      // takePicture() (still JPEG) is unaffected.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
      // The phone is held nearly flat, pointed down at tiles on a table —
      // the accelerometer can't reliably tell landscape from portrait in
      // that position, so ambient device-orientation detection (what both
      // the live preview and the captured photo would otherwise fall back
      // on) is unusable here. Pin it explicitly instead: this is what
      // actually determines CameraPreview's aspect ratio (it checks
      // `lockedCaptureOrientation` before the ambient sensor) and the
      // orientation `takePicture()` bakes into the photo.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (_controller != controller) {
        await controller.dispose();
        return;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        if (_controller == controller) _controller = null;
        _cameraInitError = 'カメラを開始できませんでした。端末の設定でカメラへのアクセスを確認してください。';
      });
    }
  }

  @override
  void dispose() {
    _scoreRecalculationTimer?.cancel();
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
    final trace = PerformanceTrace(
      name: 'tileRecognition',
      metadata: {
        'purpose': _purpose.name,
        'tile_count_mode': _expectedTileCount == null ? 'automatic' : 'manual',
        'requested_tile_count': _expectedTileCount,
        'auto_inferred_tile_count': _expectedTileCount == null
            ? _autoDetectedTileCount
            : null,
        'capture_mode': 'manual',
      },
    );
    _performanceTrace = trace;
    trace.mark('captureRequested');
    setState(() => _isCapturing = true);

    bool capturedOk = false;
    try {
      final xFile = await _controller!.takePicture();
      trace.mark('pictureTaken');
      final bytes = await xFile.readAsBytes();
      trace.mark('bytesRead');
      // The preview is a centered 16:9 frame. Persist exactly that frame so
      // detection, result display, box editing and training upload all share
      // the same image and coordinate system instead of reverting to the
      // camera plugin's full portrait JPEG after capture.
      final framed = await compute(prepareCapturedFrame, bytes);
      if (!mounted) return;
      final framedBytes = framed.bytes;
      final decoded = framed.image;
      trace.mark('jpegDecoded');
      capturedOk = true;

      _acceptPhoto(framedBytes, decoded);

      // Always proceed straight to the results phase with whatever detection
      // found. Missing or extraneous boxes are recovered by changing the
      // expected count, cropping the source region, or returning to camera.
      final detected = await compute(segmentTilesWithHintsForExpectedCount, (
        bytes: framedBytes,
        expectedTileCount: _expectedTileCount,
        allowExtendedAuto: _expectedTileCount == null,
      ));
      trace.annotate('final_detected_tile_count', detected.boxes.length);
      trace.mark('segmentationCompleted');
      if (!mounted) return;
      await _classifyBoxesAndFinish(
        detected.boxes,
        angleHints: detected.angleHints,
      );
    } catch (e) {
      trace.mark('captureFailed');
      trace.log();
      if (identical(_performanceTrace, trace)) _performanceTrace = null;
      _showError('撮影エラー: $e');
      // If capture/decode itself failed, stay on the camera phase; if it was
      // detection that failed after a successful capture, still move on to
      // the results phase (empty boxes) rather than getting stuck on the
      // spinner — the user can add all 14 boxes manually from there.
      if (capturedOk) await _classifyBoxesAndFinish(const []);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _acceptPhoto(Uint8List framedBytes, img.Image decoded) {
    setState(() {
      final resumeWinConditions = _resumeWinConditionsAfterRetake;
      _capturedBytes = framedBytes;
      _capturedImage = decoded;
      _phase = _ScanPhase.detecting;
      _recognitionComplete = false;
      if (!resumeWinConditions) {
        _winConditionStep = _WinConditionStep.riichi;
        _winConditionsComplete = false;
        _doraSlotCount = math.max(1, _context.doraIndicators.length);
      }
      _resumeWinConditionsAfterRetake = false;
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
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    bool accepted = false;
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photo == null || !mounted) return;
      if (await photo.length() > 20 * 1024 * 1024) {
        throw const FormatException('画像は20MB以下で選んでください');
      }
      final prepared = await compute(
        prepareImportedPhoto,
        await photo.readAsBytes(),
      );
      if (!mounted) return;
      _acceptPhoto(prepared.bytes, prepared.image);
      accepted = true;
      final detected = await compute(segmentTilesWithHintsForExpectedCount, (
        bytes: prepared.bytes,
        expectedTileCount: _expectedTileCount,
        allowExtendedAuto: _expectedTileCount == null,
      ));
      if (!mounted) return;
      await _classifyBoxesAndFinish(
        detected.boxes,
        angleHints: detected.angleHints,
      );
    } catch (error) {
      if (!mounted) return;
      _showError('画像読込エラー: $error');
      if (accepted) await _classifyBoxesAndFinish(const []);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
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
      if (_expectedTileCount == null &&
          boxes.length >= 13 &&
          boxes.length <= 18) {
        _autoDetectedTileCount = boxes.length;
      }
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
    _performanceTrace?.mark('cropsPrepared');

    if (!_usesWinConditionWizard) {
      setState(() => _phase = _ScanPhase.results);
    }
    if (widget.autoClassify && boxes.isNotEmpty) {
      await _runClassification();
    }
    if (_usesWinConditionWizard && mounted) {
      setState(() {
        _recognitionComplete = true;
        if (_winConditionsComplete) _phase = _ScanPhase.results;
      });
    }
    if (mounted && _phase == _ScanPhase.results) {
      _scheduleRecognitionFirstPaint();
    }
  }

  /// Opens `PhotoCropScreen` seeded with the current crop region (or the
  /// whole photo, the first time), then re-detects within whatever the user
  /// confirms. FEZ-93's recovery flow for a stray reflection or unrelated
  /// object getting detected as a tile — see `_redetectInRegion`.
  Future<void> _cropAndRedetect() async {
    final srcImage = _capturedImage;
    final imageBytes = _capturedBytes;
    if (srcImage == null || imageBytes == null) return;

    final initialRegion =
        _cropRegion ??
        Rect.fromLTWH(
          0,
          0,
          srcImage.width.toDouble(),
          srcImage.height.toDouble(),
        );

    final region = await Navigator.of(context).push<Rect>(
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(
          rawImageBytes: imageBytes,
          rawWidth: srcImage.width,
          rawHeight: srcImage.height,
          initialRegion: initialRegion,
        ),
      ),
    );
    if (region == null || !mounted) return;
    await _redetectInRegion(region);
  }

  /// Re-runs on-device tile detection restricted to [region] (in
  /// `_capturedImage`'s pixel space), or the whole photo when null (the
  /// "元の範囲に戻す" path). Adopted policy for FEZ-93: manually excluding
  /// the offending area and re-detecting on-device is cheaper and more
  /// predictable than a generative-AI preprocessing step, and needs no
  /// server/external API call. Reuses `_classifyBoxesAndFinish`, so a
  /// re-detect clears every previous box/crop/classification exactly like
  /// the initial capture does, and keeps using `_expectedTileCount`
  /// (the count chosen before capture is never reset by re-detection).
  Future<void> _redetectInRegion(Rect? region) async {
    final srcImage = _capturedImage;
    if (srcImage == null) return;

    final x = (region?.left ?? 0).round().clamp(0, srcImage.width - 1);
    final y = (region?.top ?? 0).round().clamp(0, srcImage.height - 1);
    final w = (region?.width ?? srcImage.width.toDouble()).round().clamp(
      1,
      srcImage.width - x,
    );
    final h = (region?.height ?? srcImage.height.toDouble()).round().clamp(
      1,
      srcImage.height - y,
    );
    // The exact rect actually cropped to, in `_capturedImage`'s pixel space
    // — built from the clamped ints above, not the raw `region` argument,
    // so it's pixel-exact with what `copyCrop` below and the box-offset
    // further down both use. Null (not this) when resetting to the full
    // photo, even though x/y/w/h above still describe that full extent.
    final clampedRegion = region == null
        ? null
        : Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());

    setState(() {
      _phase = _ScanPhase.detecting;
      _cropRegion = clampedRegion;
    });

    final regionImage = img.copyCrop(srcImage, x: x, y: y, width: w, height: h);
    final regionBytes = await compute(img.encodeJpg, regionImage);
    if (!mounted) return;
    // Reuse the same encode for the results-screen preview when actually
    // cropped; when resetting to the full photo, prefer the original
    // `_capturedBytes` over this redundant re-encode (no generation loss).
    setState(
      () => _cropDisplayBytes = clampedRegion != null ? regionBytes : null,
    );
    final detected = await compute(segmentTilesWithHintsForExpectedCount, (
      bytes: regionBytes,
      expectedTileCount: _expectedTileCount,
      allowExtendedAuto: _expectedTileCount == null,
    ));
    if (!mounted) return;

    // Detection ran on the cropped sub-image, so its boxes are relative to
    // the crop's own top-left — shift them back into `_capturedImage`'s
    // pixel space, the coordinate system every other box/quad on this
    // screen (and `_classifyBoxesAndFinish`) already assumes.
    final offset = Offset(x.toDouble(), y.toDouble());
    final offsetBoxes = [for (final box in detected.boxes) box.shift(offset)];
    await _classifyBoxesAndFinish(offsetBoxes, angleHints: detected.angleHints);
  }

  /// Classifies every cropped tile (`_croppedImages`) at once. Called either
  /// automatically after detection when the home-screen option is enabled,
  /// or explicitly from the results screen's "識別実行" button.
  Future<void> _runClassification() async {
    if (_isRunningFullClassification) return;
    setState(() => _isRunningFullClassification = true);
    try {
      await _classifierInitialization;
      _performanceTrace?.mark('modelReady');
      if (!mounted) return;
      if (!_classifier.isReady) {
        _showError('牌識別モデルが読み込まれていません');
        return;
      }

      for (int i = 0; i < _maxPhysicalTiles; i++) {
        if (_croppedImages[i] != null) await _classifyTile(i);
      }
      _performanceTrace?.mark('classificationCompleted');
    } finally {
      if (mounted) setState(() => _isRunningFullClassification = false);
    }
  }

  /// Classify one crop and update only that slot. This is shared by the full
  /// identification action and FEZ-200's automatic re-identification after a
  /// single box edit, so adjusting one box never reruns the other tiles.
  Future<void> _classifyTile(int index) async {
    final cropped = _croppedImages[index];
    if (cropped == null) return;

    setState(() => _isClassifying[index] = true);
    try {
      final results = await _classifier.classify(cropped, topK: 3);
      if (!mounted) return;
      setState(() {
        final prediction = results.isNotEmpty ? results.first.tileCode : null;
        _tiles[index] = prediction;
        _predictedTiles[index] = prediction;
        _candidates[index] = results
            .map(
              (result) => TileCandidate(
                tile: result.tileCode,
                confidence: result.confidence,
              ),
            )
            .toList(growable: false);
        _invalidateInterpretation();
      });
    } catch (error) {
      _showError('牌識別エラー: $error');
    } finally {
      if (mounted) setState(() => _isClassifying[index] = false);
    }
  }

  // ── Results phase: manual box correction ──

  /// Opens the full-screen quad editor for tile [index] (see
  /// `TileBoxEditorScreen` for why it's a separate route rather than
  /// embedded here). [initialDecodedQuad] seeds the editor when the tile
  /// has no quad yet (the "枠を追加" path); otherwise the existing
  /// `_tileQuads[index]` is used. On confirm, re-crops via `_cropQuad`
  /// (perspective-rectifies the quad — handles a tile that photographed as
  /// a trapezoid, not just a rotated rectangle). Editing clears that tile's
  /// previous result. With automatic identification enabled, only that slot
  /// is then identified again; otherwise the user can run the normal full
  /// identification action. On delete, clears the slot entirely via
  /// `_clearTileSlot`
  /// (see FEZ-193 — previously the only way to undo a wrongly-added box
  /// was to retake the whole photo).
  /// Occupied tile slots (a box, or a tile added without one).
  int get _slotCount => [
    for (var index = 0; index < _maxPhysicalTiles; index++)
      if (_tileQuads[index] != null || _tiles[index] != null) index,
  ].length;

  /// Resets the interpretation after the slots changed, keeping the user's
  /// melds and あがり牌 (already renumbered by the caller), and keeps the
  /// tile-count choice in step with the boxes. Must run inside `setState`.
  void _afterSlotsChanged(List<ConfirmedMeld> melds, String? winningTileId) {
    final manual = _winningTileManuallySet;
    _invalidateInterpretation();
    _confirmedMelds.addAll(melds);
    if (winningTileId != null) {
      _confirmedWinningTileId = winningTileId;
      _winningTileManuallySet = manual;
    }
    _keepWinningTileOutsideMelds();
    _setDisplayedTileCount(_slotCount);
  }

  /// 「この枠を削除」 from the box editor: drops the slot, closing the gap.
  void _deleteTileBox(int index) {
    if (_slotCount <= _minTileBoxes) return;
    final melds = shiftMeldsAfterRemoval(List.of(_confirmedMelds), index);
    final winningTileId = shiftObservationIdAfterRemoval(
      _confirmedWinningTileId,
      index,
    );
    setState(() {
      removeSlot<String?>(_tiles, index, null);
      removeSlot<String?>(_predictedTiles, index, null);
      removeSlot<List<TileCandidate>>(_candidates, index, <TileCandidate>[]);
      removeSlot<bool>(_isClassifying, index, false);
      removeSlot<img.Image?>(_croppedImages, index, null);
      removeSlot<Uint8List?>(_croppedImageThumbnails, index, null);
      removeSlot<TileQuad?>(_tileQuads, index, null);
      _afterSlotsChanged(melds, winningTileId);
    });
  }

  /// 「枠を追加」: opens the box editor on a median-size box in the middle of
  /// the photo; the confirmed box is inserted in left-to-right order and
  /// identified like the others.
  Future<void> _addTileBox() async {
    final srcImage = _capturedImage;
    final imageBytes = _capturedBytes;
    if (srcImage == null || imageBytes == null) return;
    if (_slotCount >= _maxPhysicalTiles) return;
    final existing = _tileQuads
        .whereType<TileQuad>()
        .map((quad) => quad.boundingRect)
        .toList();
    double median(Iterable<double> values) {
      final sorted = values.toList()..sort();
      return sorted[sorted.length ~/ 2];
    }

    final placeholder = TileQuad.fromRect(
      Rect.fromCenter(
        center: Offset(srcImage.width / 2, srcImage.height / 2),
        width: existing.isEmpty
            ? srcImage.width / 16
            : median(existing.map((rect) => rect.width)),
        height: existing.isEmpty
            ? srcImage.width / 12
            : median(existing.map((rect) => rect.height)),
      ),
    );
    final result = await Navigator.of(context).push<TileBoxEditorResult>(
      MaterialPageRoute(
        builder: (_) => TileBoxEditorScreen(
          rawImageBytes: imageBytes,
          rawWidth: srcImage.width,
          rawHeight: srcImage.height,
          initialQuad: placeholder,
        ),
      ),
    );
    if (result is! TileBoxEditorConfirmed || !mounted) return;

    final quad = result.quad;
    final centerX = quad.boundingRect.center.dx;
    var insertAt = _slotCount;
    for (var index = 0; index < _slotCount; index++) {
      final other = _tileQuads[index];
      if (other != null && other.boundingRect.center.dx > centerX) {
        insertAt = index;
        break;
      }
    }
    final cropped = _cropQuad(srcImage, quad);
    final melds = shiftMeldsAfterInsertion(List.of(_confirmedMelds), insertAt);
    final winningTileId = shiftObservationIdAfterInsertion(
      _confirmedWinningTileId,
      insertAt,
    );
    setState(() {
      insertSlot<TileQuad?>(_tileQuads, insertAt, quad);
      insertSlot<img.Image?>(_croppedImages, insertAt, cropped);
      insertSlot<Uint8List?>(
        _croppedImageThumbnails,
        insertAt,
        Uint8List.fromList(img.encodeJpg(cropped)),
      );
      insertSlot<String?>(_tiles, insertAt, null);
      insertSlot<String?>(_predictedTiles, insertAt, null);
      insertSlot<List<TileCandidate>>(
        _candidates,
        insertAt,
        <TileCandidate>[],
      );
      insertSlot<bool>(_isClassifying, insertAt, false);
      _afterSlotsChanged(melds, winningTileId);
    });
    if (!widget.autoClassify) return;
    await _classifierInitialization;
    if (!mounted) return;
    if (!_classifier.isReady) {
      _showError('牌識別モデルが読み込まれていません');
      return;
    }
    await _classifyTile(insertAt);
  }

  Future<void> _openBoxEditor(int index) async {
    final srcImage = _capturedImage;
    final imageBytes = _capturedBytes;
    if (srcImage == null || imageBytes == null) return;
    final shouldReanalyze =
        _operation == HandOperation.score && _hasScoreCalculation;

    final quad = _tileQuads[index];
    if (quad == null) return;

    final result = await Navigator.of(context).push<TileBoxEditorResult>(
      MaterialPageRoute(
        builder: (_) => TileBoxEditorScreen(
          rawImageBytes: imageBytes,
          rawWidth: srcImage.width,
          rawHeight: srcImage.height,
          initialQuad: quad,
          canDelete: _slotCount > _minTileBoxes,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result is TileBoxEditorDeleted) {
      _deleteTileBox(index);
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
    if (widget.autoClassify) {
      await _classifierInitialization;
      if (!mounted) return;
      if (!_classifier.isReady) {
        _showError('牌識別モデルが読み込まれていません');
      } else {
        await _classifyTile(index);
        if (shouldReanalyze && mounted && _allDetectedTilesReady) {
          await _runInterpretationAndAnalyze();
        }
      }
    }
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

  /// [carriedMelds] and [carriedWinningTileId] survive the reset below:
  /// they are user decisions about the current tiles (e.g. carried over by
  /// 「別の確認へ」), not stale facts from a previous interpretation.
  Future<void> _runInterpretation({
    List<ConfirmedMeld> carriedMelds = const [],
    String? carriedWinningTileId,
  }) async {
    if (!_allDetectedTilesReady) return;
    setState(() {
      _isInterpreting = true;
      _invalidateInterpretation();
      _confirmedMelds.addAll(carriedMelds);
      if (carriedWinningTileId != null) {
        _confirmedWinningTileId = carriedWinningTileId;
        _winningTileManuallySet = true;
      }
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
        _applySuggestedWinningTile(result);
        _keepWinningTileOutsideMelds();
      });
    } catch (error) {
      if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
        setState(
          () => _runError =
              '画像の解釈に失敗しました。もう一度「実行」を押してください。（$error）',
        );
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
  Future<void> _runInterpretationAndAnalyze({
    List<ConfirmedMeld> carriedMelds = const [],
    String? carriedWinningTileId,
  }) async {
    final adjusted = await _matchTileCountToPurpose();
    if (adjusted == null || !mounted) return;
    if (adjusted.changed) {
      carriedMelds = adjusted.melds;
      carriedWinningTileId = adjusted.winningTileId;
    } else if (_interpretation == null && carriedMelds.isEmpty) {
      // The interpretation run resets melds; keep the ones the user already
      // registered (a 槓子 registered before 実行 used to be dropped, so a
      // 15-tile hand reached the server as 15 loose tiles).
      carriedMelds = List.of(_confirmedMelds);
      if (_winningTileManuallySet) {
        carriedWinningTileId ??= _confirmedWinningTileId;
      }
    }
    if (_interpretation == null) {
      await _runInterpretation(
        carriedMelds: carriedMelds,
        carriedWinningTileId: carriedWinningTileId,
      );
      if (!mounted || _interpretation == null) return;
    }
    await _confirmAndAnalyze(showResultDialog: false);
  }

  /// Physical tiles the purpose works on: 13 (待ち確認・鳴き判断) or 14
  /// (点数計算・何を切る), plus one for each declared 槓.
  int get _requiredTileCount =>
      _purpose.defaultTileCount +
      _confirmedMelds.where((meld) => meld.observationIds.length == 4).length;

  /// Before running, makes the identified tiles match [_requiredTileCount]:
  /// one too many asks which tile to leave out and one too few asks for the
  /// missing tile (the same dialogs as 「別の確認へ」); further off stops with
  /// a message and opens the photo controls. Without this the server
  /// refused e.g. 14 tiles for 鳴き判断 with an English error.
  ///
  /// Returns null to stop. `changed` is true when a tile was removed or
  /// added; the interpretation is then reset and `melds` / `winningTileId`
  /// must be carried into the rerun.
  Future<({bool changed, List<ConfirmedMeld> melds, String? winningTileId})?>
  _matchTileCountToPurpose() async {
    final count = _identifiedIndices.length;
    final required = _requiredTileCount;
    final delta = count - required;
    if (delta == 0) {
      return (changed: false, melds: const <ConfirmedMeld>[], winningTileId: null);
    }
    if (delta.abs() > 1) {
      setState(() {
        _recognitionDetailsExpanded = true;
        _runError =
            '牌が$count枚あります。${_purpose.label}は$required枚で行います。'
            '槓子の数・枠の追加と削除・トリミングで枚数を合わせてください。';
      });
      return null;
    }
    if (delta == 1) {
      // One extra tile is often an unregistered 槓子 rather than a stray.
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('牌が1枚多いです'),
          content: Text(
            '${_purpose.label}は$required枚（槓子1つにつき+1枚）で行います。'
            '槓子がある場合は槓子として登録してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              child: const Text('外す牌を選ぶ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'kan'),
              child: const Text('槓子を登録'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return null;
      if (choice == 'kan') {
        await _showMeldSelectionDialog();
        if (!mounted) return null;
        // Registered: the count now fits and the run goes on.
        return _identifiedIndices.length == _requiredTileCount
            ? (changed: false, melds: const <ConfirmedMeld>[], winningTileId: null)
            : null;
      }
      final candidates = _concealedIndices;
      if (candidates.isEmpty) return null;
      final removedIndex = await showTileRemovalDialog(
        context,
        target: _purpose,
        candidates: [for (final index in candidates) (index, _tiles[index]!)],
        highlightedIndex: slotForObservationId(_confirmedWinningTileId),
      );
      if (removedIndex == null || !mounted) return null;
      final melds = shiftMeldsAfterRemoval(
        List.of(_confirmedMelds),
        removedIndex,
      );
      final winningTileId = shiftObservationIdAfterRemoval(
        _confirmedWinningTileId,
        removedIndex,
      );
      setState(() {
        removeSlot<String?>(_tiles, removedIndex, null);
        removeSlot<String?>(_predictedTiles, removedIndex, null);
        removeSlot<List<TileCandidate>>(
          _candidates,
          removedIndex,
          <TileCandidate>[],
        );
        removeSlot<bool>(_isClassifying, removedIndex, false);
        removeSlot<img.Image?>(_croppedImages, removedIndex, null);
        removeSlot<Uint8List?>(_croppedImageThumbnails, removedIndex, null);
        removeSlot<TileQuad?>(_tileQuads, removedIndex, null);
        _setDisplayedTileCount(_identifiedIndices.length);
        _invalidateInterpretation();
      });
      return (
        changed: true,
        melds: melds,
        winningTileId: _operation == HandOperation.score ? winningTileId : null,
      );
    }
    if (_nextFreeSlot >= _maxPhysicalTiles) {
      _showError('これ以上牌を追加できません');
      return null;
    }
    final addedTile = await TileImagePicker.show(
      context,
      title: '${_purpose.label}は$required枚で行います。足りない牌を選択',
    );
    if (addedTile == null || !mounted) return null;
    final melds = List.of(_confirmedMelds);
    setState(() {
      final index = _nextFreeSlot;
      _tiles[index] = addedTile;
      _candidates[index] = [TileCandidate(tile: addedTile, confidence: 1.0)];
      _setDisplayedTileCount(index + 1);
      _invalidateInterpretation();
    });
    return (
      changed: true,
      melds: melds,
      // For score the added tile is the drawn one, i.e. the あがり牌.
      winningTileId: _operation == HandOperation.score
          ? _defaultWinningTileId
          : null,
    );
  }

  Future<void> _confirmAndAnalyze({bool showResultDialog = true}) async {
    if (_interpretation == null) return;
    setState(_keepWinningTileOutsideMelds);
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
      _tsumoScoreResult = null;
      _ronScoreResult = null;
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
      final rules = widget.ruleSettings.rules;
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
          final hand = HandInput(
            closedTiles: state.hand.closedTiles,
            melds: state.hand.melds
                .map(
                  (meld) =>
                      Meld(type: meld.type, tiles: meld.tiles, open: meld.open),
                )
                .toList(growable: false),
            winTile: winTile,
          );
          final baseContext = _context.copyWith(akaDora: akaDoraCount);
          // ツモ and ロン are scored separately: one may be refused while the
          // other wins (a 門前清自摸和-only hand, e.g. with a 暗槓, has no
          // 役 for ロン), so one refusal must not hide the other result.
          Future<(ScoreResponse?, HandRequestException?)> attempt(
            String winType,
          ) async {
            try {
              final response = await _api.calculateScore(
                ScoreRequest(
                  hand: hand,
                  context: _contextForWinType(baseContext, winType),
                  rules: rules,
                ),
              );
              return (response, null);
            } on HandRequestException catch (error) {
              return (null, error);
            }
          }

          final tsumoAttempt = attempt('tsumo');
          final ronAttempt = attempt('ron');
          final (tsumoResult, tsumoError) = await tsumoAttempt;
          final (ronResult, ronError) = await ronAttempt;
          if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
          String? note(HandRequestException? error) => error == null
              ? null
              : error.isNoYaku
              ? '役なしのため和了できません'
              : error.message;
          setState(() {
            _tsumoScoreResult = tsumoResult;
            _ronScoreResult = ronResult;
            _tsumoNote = note(tsumoError);
            _ronNote = note(ronError);
            if (tsumoResult == null && ronResult == null) {
              final refused = tsumoError ?? ronError;
              final shapeRefused =
                  (tsumoError == null) || (ronError == null);
              if (refused == null || shapeRefused) {
                _isNotWinning = true;
              } else {
                _runError = refused.message;
              }
            }
          });
          if (tsumoResult != null || ronResult != null) {
            await _saveScoreHistory(
              tsumoResponse: tsumoResult,
              ronResponse: ronResult,
            );
          }
          if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
          if (showResultDialog) _showResultDialog();
          break;
        case HandOperation.tenpai:
          final result = await _api.analyzeTenpai(
            state: state,
            context: _context,
            rules: rules,
          );
          if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
            setState(() => _analysisResult = result);
            await _saveAnalysisHistory(result);
            if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
            if (showResultDialog) _showResultDialog();
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
            await _saveAnalysisHistory(result);
            if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
            if (showResultDialog) _showResultDialog();
          }
          break;
        case HandOperation.callAnalysis:
          final result = await _api.analyzeCalls(
            state: state,
            context: _context,
            rules: rules,
          );
          if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
            setState(() => _analysisResult = result);
            await _saveAnalysisHistory(result);
            if (!mounted || !_requestEpoch.isCurrent(requestEpoch)) return;
            if (showResultDialog) _showResultDialog();
          }
          break;
      }
    } catch (error) {
      if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
        setState(
          () => _runError = error is HandRequestException
              ? error.message
              : '解析できませんでした。通信状態を確認して、もう一度「実行」を押してください。（$error）',
        );
      }
    } finally {
      if (mounted && _requestEpoch.isCurrent(requestEpoch)) {
        setState(() => _isScoring = false);
      }
    }
  }

  ContextInput _contextForWinType(ContextInput base, String winType) {
    if (winType == 'tsumo') {
      return base.copyWith(winType: 'tsumo', houtei: false, chankan: false);
    }
    return base.copyWith(
      winType: 'ron',
      haitei: false,
      rinshan: false,
      chiihou: false,
      tenhou: false,
    );
  }

  Future<void> _saveScoreHistory({
    required ScoreResponse? tsumoResponse,
    required ScoreResponse? ronResponse,
  }) async {
    String label(String winType, ScoreResponse? response) => response == null
        ? '$winType: 不成立'
        : '$winType: ${response.result.han}翻${response.result.fu}符 '
              '${response.result.pointLabel}';
    Map<String, dynamic>? resultDetails(ScoreResponse? response) {
      if (response == null) return null;
      final result = response.result;
      return {
        'han': result.han,
        'fu': result.fu,
        'point_label': result.pointLabel,
        'ron': result.points.ron,
        'tsumo_dealer_pay': result.points.tsumoDealerPay,
        'tsumo_non_dealer_pay': result.points.tsumoNonDealerPay,
        'yaku': result.yaku.map((item) => item.name).toList(growable: false),
      };
    }

    await _saveHistoryWithoutBlockingResult(
      HistoryEntry(
        id: _historyEntryId,
        createdAt: _historyCreatedAt,
        updatedAt: DateTime.now().toUtc(),
        purpose: 'score',
        title: '点数計算',
        summary: [
          label('ツモ', tsumoResponse),
          label('ロン', ronResponse),
        ].join(' / '),
        roundLabel: widget.historyRoundLabel,
        details: {
          'tiles': _tiles.whereType<String>().toList(growable: false),
          'recognition_model': _recognitionModelMetadata,
          'context': _context.toJson(),
          'rule_settings': widget.ruleSettings.toJson(),
          'tsumo': resultDetails(tsumoResponse),
          'ron': resultDetails(ronResponse),
        },
        accountUid: AuthService.currentUser?.uid,
      ),
    );
  }

  Future<void> _saveAnalysisHistory(Map<String, dynamic> result) async {
    final purpose = switch (_purpose) {
      ScanPurpose.wait => 'wait',
      ScanPurpose.callAdvice => 'call_advice',
      _ => 'discard',
    };
    await _saveHistoryWithoutBlockingResult(
      HistoryEntry(
        id: _historyEntryId,
        createdAt: _historyCreatedAt,
        updatedAt: DateTime.now().toUtc(),
        purpose: purpose,
        title: _purpose.label,
        summary: _analysisSummary(result),
        roundLabel: widget.historyRoundLabel,
        details: {
          'tiles': _tiles.whereType<String>().toList(growable: false),
          'recognition_model': _recognitionModelMetadata,
          'context': _context.toJson(),
          'rule_settings': widget.ruleSettings.toJson(),
          'result': result,
          if (_chatMessages.isNotEmpty)
            'ai_conversation': _chatMessages
                .map((message) => message.toJson())
                .toList(growable: false),
        },
        accountUid: AuthService.currentUser?.uid,
      ),
    );
  }

  Future<void> _saveHistoryWithoutBlockingResult(HistoryEntry entry) async {
    final saved = await _historyService.trySave(entry);
    if (!saved && mounted) {
      _showError('結果は確認できますが、履歴を保存できませんでした。端末の空き容量や保存設定を確認してください。');
    }
  }

  Map<String, String> get _recognitionModelMetadata => {
    'version': _classifier.modelVersion,
    'source': _classifier.modelSource,
    'preprocessing_version': _classifier.preprocessingVersion,
  };

  Future<void> _openAiChat({
    Map<String, dynamic>? selectedCall,
    String? discardFocus,
  }) async {
    final result = _analysisResult;
    if (result == null ||
        _purpose == ScanPurpose.score ||
        _purpose == ScanPurpose.wait) {
      return;
    }
    await AIChatSheet.show(
      context,
      purpose: _purpose == ScanPurpose.callAdvice ? 'call_advice' : 'discard',
      tiles: _tiles.whereType<String>().toList(growable: false),
      roundContext: _context.toJson(),
      analysis: {...result, 'selected_call': ?selectedCall},
      initialMessages: _chatMessages,
      initialSituationTags: [?discardFocus],
      initialDraft: discardFocus == null
          ? null
          : '$discardFocusで、上位3候補から何を切るべきか理由も含めて教えて',
      onMessagesChanged: (messages) {
        if (mounted) setState(() => _chatMessages = messages);
        // Each write is isolated: one failed save must not leave the queue
        // in an error state that silently skips every later conversation.
        _historyUpdateQueue = _historyUpdateQueue.then((_) async {
          try {
            await _historyService.updateDetails(_historyEntryId, {
              'ai_conversation': messages
                  .map((message) => message.toJson())
                  .toList(growable: false),
            });
          } catch (error) {
            debugPrint('ScanScreen: failed to save AI conversation: $error');
          }
        });
      },
    );
  }

  /// Concealed (not in a confirmed meld) identified slots, ascending — the
  /// tiles 「別の確認へ」 may leave out when moving from 14 to 13 tiles.
  List<int> get _concealedIndices => [
    for (final index in _identifiedIndices)
      if (!_isConfirmedMeldMember(index)) index,
  ];

  /// The slot right after the last identified tile, where 「別の確認へ」
  /// appends an added drawn tile.
  int get _nextFreeSlot {
    final identified = _identifiedIndices;
    return identified.isEmpty ? 0 : identified.last + 1;
  }

  void _setDisplayedTileCount(int count) {
    if (_expectedTileCount != null) {
      _expectedTileCount = count;
    } else {
      _autoDetectedTileCount = count;
    }
  }

  /// 「別の確認へ」: re-runs analysis for another purpose on the same photo,
  /// boxes and confirmed tiles, without re-capturing or re-detecting. Moving
  /// between 14-tile and 13-tile purposes first asks for the one tile to
  /// leave out or add.
  Future<void> _switchPurpose() async {
    final target = await showPurposeSwitchDialog(context, current: _purpose);
    if (target == null || !mounted) return;

    final adjustment = purposeSwitchAdjustment(_purpose, target);
    int? removedIndex;
    String? addedTile;
    switch (adjustment) {
      case PurposeSwitchAdjustment.none:
        break;
      case PurposeSwitchAdjustment.removeOne:
        final candidates = _concealedIndices;
        if (candidates.isEmpty) return;
        removedIndex = await showTileRemovalDialog(
          context,
          target: target,
          candidates: [for (final index in candidates) (index, _tiles[index]!)],
          highlightedIndex: slotForObservationId(_confirmedWinningTileId),
        );
        if (removedIndex == null || !mounted) return;
      case PurposeSwitchAdjustment.addOne:
        if (_nextFreeSlot >= _maxPhysicalTiles) {
          _showError('これ以上牌を追加できません');
          return;
        }
        addedTile = await TileImagePicker.show(context, title: '追加するツモ牌を選択');
        if (addedTile == null || !mounted) return;
    }

    final tilesChanged = adjustment != PurposeSwitchAdjustment.none;
    var carriedMelds = const <ConfirmedMeld>[];
    String? carriedWinningTileId;
    setState(() {
      final melds = List.of(_confirmedMelds);
      _purpose = target;
      _operation = target.operation;
      _historyEntryId = HistoryService.createId();
      _historyCreatedAt = DateTime.now().toUtc();

      if (removedIndex != null) {
        final index = removedIndex;
        removeSlot<String?>(_tiles, index, null);
        removeSlot<String?>(_predictedTiles, index, null);
        removeSlot<List<TileCandidate>>(_candidates, index, <TileCandidate>[]);
        removeSlot<bool>(_isClassifying, index, false);
        removeSlot<img.Image?>(_croppedImages, index, null);
        removeSlot<Uint8List?>(_croppedImageThumbnails, index, null);
        removeSlot<TileQuad?>(_tileQuads, index, null);
        _setDisplayedTileCount(_identifiedIndices.length);
      }
      if (addedTile != null) {
        final index = _nextFreeSlot;
        _tiles[index] = addedTile;
        _candidates[index] = [TileCandidate(tile: addedTile, confidence: 1.0)];
        _setDisplayedTileCount(index + 1);
      }

      if (tilesChanged) {
        // The interpretation described the old tile set and is redone below.
        // Melds are carried through that reset, renumbered to the shifted
        // slots when a tile was left out.
        _invalidateInterpretation();
        carriedMelds = removedIndex == null
            ? melds
            : shiftMeldsAfterRemoval(melds, removedIndex);
        // The tile the user just added is the drawn tile, so it is the
        // あがり牌 for score — don't let the interpretation's guess move it.
        if (addedTile != null && _operation == HandOperation.score) {
          carriedWinningTileId = _defaultWinningTileId;
        }
      } else {
        _invalidateAnalysis();
        _confirmedWinningTileId ??= _defaultWinningTileId;
        // The kept interpretation may have run for a non-score purpose,
        // which skips its あがり牌 suggestion; apply it now.
        if (_interpretation case final interpretation?) {
          _applySuggestedWinningTile(interpretation);
        }
      }
      _isScoring = false;
    });

    if (_allDetectedTilesReady) {
      await _runInterpretationAndAnalyze(
        carriedMelds: carriedMelds,
        carriedWinningTileId: carriedWinningTileId,
      );
    }
  }

  String _analysisSummary(Map<String, dynamic> result) {
    if (_purpose == ScanPurpose.wait) {
      final tiles = (result['improving_tiles'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => item['tile'])
          .whereType<String>()
          .join(' / ');
      return tiles.isEmpty ? '待ち・有効牌なし' : '待ち・有効牌 $tiles';
    }
    if (_purpose == ScanPurpose.callAdvice) {
      final count = (result['calls'] as List<dynamic>? ?? const []).length;
      return '鳴き候補 $count件';
    }
    final discards = (result['discards'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .take(3)
        .map((item) => item['discard'])
        .whereType<String>()
        .join(' / ');
    return discards.isEmpty ? '打牌候補なし' : '打牌候補 $discards';
  }

  void _onSlotTap(int index) async {
    final shouldReanalyze =
        _operation == HandOperation.score && _hasScoreCalculation;
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
      if (shouldReanalyze && _allDetectedTilesReady) {
        await _runInterpretationAndAnalyze();
      }
    }
  }

  /// Applies a new `_context` and clears any stale result computed from the
  /// old one — shared by every place that edits it (the condition chips and
  /// `GameStatePanel`). Callers still wrap this in their own `setState`.
  void _updateContext(ContextInput c) {
    final roundWindChanged = _context.roundWind != c.roundWind;
    _context = c;
    if (roundWindChanged) widget.onRoundWindChanged?.call(c.roundWind);
    _invalidateAnalysisAndMaybeRecalculate();
  }

  void _selectWinner(int index) {
    if (index < 0 || index >= widget.winnerOptions.length) return;
    final winnerContext = widget.winnerOptions[index].context;
    setState(() {
      _selectedWinnerIndex = index;
      _updateContext(
        _context.copyWith(
          roundWind: winnerContext.roundWind,
          seatWind: winnerContext.seatWind,
          isDealer: winnerContext.isDealer,
          honba: winnerContext.honba,
        ),
      );
    });
  }

  void _scheduleScoreRecalculation() {
    _scoreRecalculationTimer?.cancel();
    _scoreRecalculationTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted ||
          _phase != _ScanPhase.results ||
          _operation != HandOperation.score ||
          _interpretation == null ||
          !_allDetectedTilesReady) {
        return;
      }
      _confirmAndAnalyze(showResultDialog: false);
    });
  }

  void _selectRiichiForWinFlow(bool riichi) {
    final hasRegisteredDora = _context.doraIndicators.isNotEmpty;
    setState(() {
      _updateContext(
        _context.copyWith(riichi: riichi, doubleRiichi: false, ippatsu: false),
      );
      if (hasRegisteredDora) {
        _doraSlotCount = _context.doraIndicators.length;
      }
      _winConditionStep = _WinConditionStep.dora;
    });
    if (hasRegisteredDora) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _winConditionStep != _WinConditionStep.dora) return;
        setState(_advanceAfterDora);
      });
    }
  }

  void _advanceAfterDora() {
    if (_context.riichi) {
      _winConditionStep = _WinConditionStep.uraDora;
    } else {
      _completeWinConditions();
    }
  }

  void _selectConditionTile(String tile, {required bool ura}) {
    setState(() {
      final selected = ura
          ? [..._context.uraDoraIndicators]
          : [..._context.doraIndicators];
      final limit = ura
          ? math.max(1, _context.doraIndicators.length)
          : _doraSlotCount;
      if (selected.length >= limit) return;
      selected.add(tile);
      _updateContext(
        ura
            ? _context.copyWith(uraDoraIndicators: selected)
            : _context.copyWith(doraIndicators: selected),
      );
      if (selected.length >= limit) {
        if (ura) {
          _completeWinConditions();
        } else {
          _advanceAfterDora();
        }
      }
    });
  }

  void _removeConditionTile(int index, {required bool ura}) {
    setState(() {
      final selected = ura
          ? [..._context.uraDoraIndicators]
          : [..._context.doraIndicators];
      selected.removeAt(index);
      _updateContext(
        ura
            ? _context.copyWith(uraDoraIndicators: selected)
            : _context.copyWith(doraIndicators: selected),
      );
    });
  }

  void _skipDoraStep({required bool ura}) {
    setState(() {
      if (ura) {
        _completeWinConditions();
      } else {
        _advanceAfterDora();
      }
    });
  }

  void _completeWinConditions() {
    _winConditionsComplete = true;
    if (_recognitionComplete) {
      _phase = _ScanPhase.results;
      _scheduleRecognitionFirstPaint();
    } else {
      _winConditionStep = _WinConditionStep.waiting;
    }
  }

  void _backToCamera() {
    final preserveWinConditions =
        _usesWinConditionWizard && _capturedImage != null;
    setState(() {
      _phase = _ScanPhase.camera;
      _capturedBytes = null;
      _capturedImage = null;
      _cropRegion = null;
      _cropDisplayBytes = null;
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
      _resumeWinConditionsAfterRetake = preserveWinConditions;
      _recognitionDetailsExpanded = null;
      if (!preserveWinConditions) {
        _winConditionStep = _WinConditionStep.riichi;
        _winConditionsComplete = false;
      }
      _recognitionComplete = false;
    });
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
    final expected =
        _expectedTileCount ??
        _autoDetectedTileCount ??
        _purpose.defaultTileCount;
    return math.max(expected, last + 1).clamp(expected, _maxPhysicalTiles);
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
      _invalidateAnalysisAndMaybeRecalculate();
    });
  }

  /// The あがり牌 is a concealed tile: when it becomes part of a meld, move
  /// it to the rightmost tile left outside the melds. Call inside setState.
  void _keepWinningTileOutsideMelds() {
    final current = slotForObservationId(_confirmedWinningTileId);
    if (current == null || !_isConfirmedMeldMember(current)) return;
    final concealed = _concealedIndices;
    _confirmedWinningTileId = concealed.isEmpty
        ? null
        : observationIdForSlot(concealed.last);
  }

  void _addConfirmedMeld(
    Set<int> selection, {
    required String type,
    required bool open,
  }) {
    final observationIds = (selection.toList()..sort())
        .map((index) => 'tile-${index.toString().padLeft(3, '0')}')
        .toList(growable: false);
    setState(() {
      _confirmedMelds.add(
        ConfirmedMeld(observationIds: observationIds, type: type, open: open),
      );
      _keepWinningTileOutsideMelds();
      _invalidateAnalysisAndMaybeRecalculate();
    });
  }

  Future<void> _showMeldSelectionDialog() async {
    final eligible = _meldEligibleIndices;
    if (eligible.isEmpty) return;
    final selection = <int>{};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final codes = (selection.toList()..sort())
              .map((index) => _tiles[index])
              .whereType<String>()
              .toList(growable: false);
          final detection = detectMeldType(codes);

          void addMeld(String type, {required bool open}) {
            Navigator.pop(dialogContext);
            _addConfirmedMeld(selection, type: type, open: open);
          }

          return AlertDialog(
            title: const Row(
              children: [
                Expanded(child: Text('副露を追加')),
                CloseButton(),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final index in eligible)
                          GestureDetector(
                            key: ValueKey('meld-dialog-tile-$index'),
                            onTap: () => setDialogState(() {
                              if (!selection.remove(index) &&
                                  selection.length < 4) {
                                selection.add(index);
                              }
                            }),
                            child: Container(
                              width: 42,
                              height: 58,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: selection.contains(index)
                                    ? _scheme.primaryContainer
                                    : _scheme.surfaceContainerHighest,
                                border: Border.all(
                                  color: selection.contains(index)
                                      ? _scheme.primary
                                      : _scheme.outlineVariant,
                                  width: selection.contains(index) ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.small,
                                ),
                              ),
                              child: TileGlyph(tileCode: _tiles[index]!),
                            ),
                          ),
                      ],
                    ),
                    if (selection.length == 3) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed:
                            detection == MeldDetection.pon ||
                                detection == MeldDetection.chi
                            ? () => addMeld(
                                detection == MeldDetection.pon ? 'pon' : 'chi',
                                open: true,
                              )
                            : null,
                        child: const Text('確定'),
                      ),
                    ] else if (selection.length == 4 &&
                        detection == MeldDetection.kan) ...[
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final closed = OutlinedButton(
                            onPressed: () => addMeld('ankan', open: false),
                            child: const Text('暗槓で追加'),
                          );
                          final open = FilledButton(
                            onPressed: () => addMeld('kan', open: true),
                            child: const Text('明槓で追加'),
                          );
                          if (constraints.maxWidth < 280) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                closed,
                                const SizedBox(height: 8),
                                open,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: closed),
                              const SizedBox(width: 8),
                              Expanded(child: open),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Win-time condition chips shown in the condition card's wind row.
  /// 立直・ダブル立直・一発 are independent chips (decided 2026-09-26): 一発
  /// and ダブル立直 can be chosen directly and imply 立直 themselves.
  List<Widget> _conditionChips() {
    final c = _context;
    void apply(ContextInput next) => setState(() => _updateContext(next));
    Widget chip(String label, bool selected, ContextInput Function() next) =>
        ToggleChip(
          label: label,
          selected: selected,
          onTap: () => apply(next()),
        );
    return [
      chip(
        '立直',
        c.riichi && !c.doubleRiichi,
        () => c.riichi && !c.doubleRiichi
            ? c.copyWith(riichi: false, ippatsu: false)
            : c.copyWith(riichi: true, doubleRiichi: false),
      ),
      chip(
        '一発',
        c.ippatsu,
        () => c.ippatsu
            ? c.copyWith(ippatsu: false)
            : c.copyWith(ippatsu: true, riichi: true),
      ),
      chip(
        'ダブル立直',
        c.doubleRiichi,
        () => c.doubleRiichi
            ? c.copyWith(riichi: false, doubleRiichi: false, ippatsu: false)
            : c.copyWith(riichi: true, doubleRiichi: true),
      ),
      chip('嶺上開花', c.rinshan, () => c.copyWith(rinshan: !c.rinshan)),
      chip('槍槓', c.chankan, () => c.copyWith(chankan: !c.chankan)),
      chip('海底摸月', c.haitei, () => c.copyWith(haitei: !c.haitei)),
      chip('河底撈魚', c.houtei, () => c.copyWith(houtei: !c.houtei)),
      chip('天和', c.tenhou, () => c.copyWith(tenhou: !c.tenhou)),
      chip('地和', c.chiihou, () => c.copyWith(chiihou: !c.chiihou)),
    ];
  }

  Widget _buildResultTile(int index, double cellWidth) {
    final thumb = _croppedImageThumbnails[index];
    final tile = _tiles[index];
    final tileAsset = tile == null ? null : tileAssetPath(tile);
    final winningTileId = 'tile-${index.toString().padLeft(3, '0')}';
    final isWinningTile = _confirmedWinningTileId == winningTileId;
    final canBeWinningTile = _operation == HandOperation.score && tile != null;
    final showMeldFrame = _isConfirmedMeldMember(index);
    final cropHeight = cellWidth * 1.4;

    final cropImage = GestureDetector(
      onTap: thumb == null ? null : () => _openBoxEditor(index),
      child: SizedBox(
        width: cellWidth,
        height: cropHeight,
        child: thumb == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: _scheme.surfaceContainerHighest,
                ),
              )
            : Image.memory(thumb, fit: BoxFit.cover),
      ),
    );

    final glyphCore = GestureDetector(
      // A tile added by 「別の確認へ」 has no crop but is still correctable.
      onTap: thumb == null && tile == null ? null : () => _onSlotTap(index),
      child: Container(
        width: cellWidth,
        height: cellWidth,
        decoration: BoxDecoration(
          color: _scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        alignment: Alignment.center,
        child: _isClassifying[index]
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : tileAsset != null
            ? Image.asset(tileAsset, fit: BoxFit.contain)
            : Text(
                '?',
                style: _text.titleMedium?.copyWith(
                  color: _scheme.onSurfaceVariant,
                ),
              ),
      ),
    );

    final glyph = Stack(
      children: [
        glyphCore,
        if (canBeWinningTile && isWinningTile)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _colors.winningTile, width: 2),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
              ),
            ),
          ),
        if (showMeldFrame)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _colors.meldTile, width: 2),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
              ),
            ),
          ),
      ],
    );

    final result = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cropImage,
        const SizedBox(height: 4),
        glyph,
        if (canBeWinningTile && isWinningTile)
          Semantics(
            button: true,
            label: '和了牌を変更',
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('winning-tile-mark'),
              onTap: _showWinningTileDialog,
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: SizedBox(
                width: cellWidth,
                height: AppSizes.tapTarget,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      size: 20,
                      color: _colors.winningTile,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '和了牌',
                        style: _text.labelSmall?.copyWith(
                          color: _colors.winningTile,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    return RepaintBoundary(
      key: ValueKey('result-tile-$index'),
      child: SizedBox(width: cellWidth, child: result),
    );
  }

  /// 副露 add/reset, directly below the tile row (plus 「和了牌を選択」 while
  /// no あがり牌 is set; otherwise the mark under that tile opens the choice).
  Widget _buildTileControlsRow() {
    final hasWinningTileControls =
        _operation == HandOperation.score && _identifiedIndices.isNotEmpty;

    final meldControls = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: WrapAlignment.end,
      children: [
        if (_confirmedMelds.isNotEmpty)
          TextButton(onPressed: _resetMelds, child: const Text('副露をリセット')),
        OutlinedButton.icon(
          onPressed: _meldEligibleIndices.isEmpty
              ? null
              : _showMeldSelectionDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('副露を追加'),
        ),
      ],
    );
    // Normally the 「↑ 和了牌」 mark under the tile opens the dialog; this
    // only covers the case where no winning tile is set yet.
    final winningControls = TextButton.icon(
      onPressed: _showWinningTileDialog,
      icon: Icon(Icons.arrow_upward, color: _colors.winningTile),
      label: const Text('和了牌を選択'),
    );

    return Row(
      children: [
        if (hasWinningTileControls && _confirmedWinningTileId == null)
          winningControls,
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: meldControls),
        ),
      ],
    );
  }

  /// Shows the score/analysis result (`_tsumoScoreResult`/`_ronScoreResult`/
  /// `_analysisResult`/
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
                    icon: const Icon(Icons.close),
                  ),
                ),
                if (_isNotWinning) ...[
                  const StatusBanner(
                    kind: StatusKind.error,
                    message: '上がりの形になっていません',
                  ),
                  const SizedBox(height: 8),
                ],
                if (_tsumoScoreResult != null || _ronScoreResult != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.65,
                    ),
                    child: SingleChildScrollView(
                      child: ScoreResultPanel(
                        tsumoResponse: _tsumoScoreResult,
                        ronResponse: _ronScoreResult,
                        tsumoNote: _tsumoNote,
                        ronNote: _ronNote,
                        ruleSettings: widget.ruleSettings,
                        isOpenHand: _confirmedMelds.any((meld) => meld.open),
                      ),
                    ),
                  ),
                if ((_tsumoScoreResult != null || _ronScoreResult != null) &&
                    widget.onScoreConfirmed != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        widget.onScoreConfirmed!(_selectedWinnerIndex ?? 0);
                        Navigator.of(dialogContext).pop();
                        Navigator.of(context).pop();
                      },
                      child: const Text('この結果で局終了'),
                    ),
                  ),
                ],
                if (_analysisResult != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.65,
                    ),
                    child: SingleChildScrollView(
                      child: AnalysisResultPanel(
                        result: _analysisResult!,
                        onAskAiAboutCall: _purpose == ScanPurpose.callAdvice
                            ? (candidate) =>
                                  _openAiChat(selectedCall: candidate)
                            : null,
                        onAskAiWithDiscardFocus: _purpose == ScanPurpose.discard
                            ? (focus) => _openAiChat(discardFocus: focus)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineScoreResult() {
    if (_operation != HandOperation.score) return const SizedBox.shrink();

    if (_isScoring) return _busyCard('点数を更新中...');

    if (_isNotWinning) {
      return const StatusBanner(
        kind: StatusKind.error,
        message: '上がりの形になっていません',
      );
    }

    if (_tsumoScoreResult == null && _ronScoreResult == null) {
      return const SizedBox.shrink();
    }

    final roundLabel = [
      ?widget.historyRoundLabel,
      _context.isDealer ? '親' : '子',
    ].join('・');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('点数', style: _text.titleMedium)),
            Text(
              roundLabel,
              style: _text.bodyMedium?.copyWith(
                color: _scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        if (_context.doraIndicators.isEmpty) ...[
          const StatusBanner(
            kind: StatusKind.warning,
            message: '表ドラ表示牌が未入力のため、翻数と点数は未確定です',
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        ScoreResultPanel(
          tsumoResponse: _tsumoScoreResult,
          ronResponse: _ronScoreResult,
          tsumoNote: _tsumoNote,
          ronNote: _ronNote,
          ruleSettings: widget.ruleSettings,
          isOpenHand: _confirmedMelds.any((meld) => meld.open),
        ),
        if (widget.onScoreConfirmed != null) ...[
          const SizedBox(height: AppSpacing.m),
          FilledButton(
            onPressed: () {
              widget.onScoreConfirmed!(_selectedWinnerIndex ?? 0);
              Navigator.of(context).pop();
            },
            child: const Text('この結果で局終了'),
          ),
        ],
      ],
    );
  }

  Widget _buildWinnerSelector() {
    if (widget.winnerOptions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('和了者', style: _text.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            for (
              int index = 0;
              index < widget.winnerOptions.length;
              index++
            ) ...[
              if (index > 0) const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: _selectedWinnerIndex == index
                      ? FilledButton(
                          onPressed: () => _selectWinner(index),
                          child: Text(widget.winnerOptions[index].label),
                        )
                      : OutlinedButton(
                          onPressed: () => _selectWinner(index),
                          child: Text(widget.winnerOptions[index].label),
                        ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildInterpretationConfirmation() {
    final interpretation = _interpretation;
    if (interpretation == null) return const SizedBox.shrink();
    if (!(_operation == HandOperation.score &&
        _confirmedWinningTileId == null)) {
      return const SizedBox.shrink();
    }
    return const StatusBanner(
      kind: StatusKind.info,
      message: 'あがり牌は牌の下の「↑ 和了牌」をタップすると変更できます',
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

  ColorScheme get _scheme => Theme.of(context).colorScheme;
  TextTheme get _text => Theme.of(context).textTheme;
  AppColors get _colors => context.appColors;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_phase) {
        _ScanPhase.camera => _buildCameraPhase(),
        _ScanPhase.detecting => _buildDetectingPhase(),
        _ScanPhase.results => _buildResultsPhase(),
      },
    );
  }

  /// Number of tiles with an identified type, for progress labels.
  int get _identifiedCount => _identifiedIndices.length;

  /// Deep-green rounded frame that holds a photo or the camera preview.
  Widget _photoFrame({required Widget child, double radius = AppRadius.hero}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: _colors.photoGradient),
          ),
          child: child,
        ),
      );

  /// Translucent pill drawn over the camera preview.
  // ════════════════════════════════════════
  // Phase: Detecting (automatic tile detection)
  // ════════════════════════════════════════

  Widget _buildDetectingPhase() {
    if (_usesWinConditionWizard) return _buildWinConditionPhase();
    return SafeArea(
      child: Column(
        children: [
          ScreenHeader(
            title: '認識中',
            subtitle: _purpose.label,
            backLabel: '撮り直す',
            onBack: _backToCamera,
            trailing: HeaderHomeButton(
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                if (_capturedBytes != null)
                  _photoFrame(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.memory(
                        _capturedBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.m),
                _recognitionStatusCard(
                  title: '牌を識別しています',
                  subtitle: '完了すると結果を自動で表示します',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recognitionStatusCard({
    required String title,
    required String subtitle,
  }) => Container(
    padding: const EdgeInsets.all(AppSpacing.l),
    decoration: BoxDecoration(
      color: _scheme.primary,
      borderRadius: BorderRadius.circular(AppRadius.xLarge),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: _colors.onDark,
            backgroundColor: _colors.onDark.withValues(alpha: 0.25),
          ),
        ),
        const SizedBox(width: AppSpacing.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: _text.titleMedium?.copyWith(color: _colors.onDark),
              ),
              Text(
                subtitle,
                style: _text.bodySmall?.copyWith(color: _colors.onDarkMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildWinConditionPhase() {
    final step = _winConditionStep;
    final (backLabel, onBack) = switch (step) {
      _WinConditionStep.dora => (
        '一つ前',
        () => setState(() => _winConditionStep = _WinConditionStep.riichi),
      ),
      _WinConditionStep.uraDora => (
        '一つ前',
        () => setState(() => _winConditionStep = _WinConditionStep.dora),
      ),
      _ => ('撮り直す', _backToCamera),
    };
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: _purpose.label,
            subtitle: step == _WinConditionStep.waiting ? '認識中' : '条件入力',
            backLabel: backLabel,
            onBack: onBack,
            trailing: HeaderHomeButton(
              tooltip: '対局ホーム',
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.l,
              AppSpacing.l,
              0,
            ),
            child: _recognitionProgressCard(),
          ),
          if (step != _WinConditionStep.waiting) ...[
            const SizedBox(height: AppSpacing.l),
            _stepDots(step),
          ],
          Expanded(
            child: switch (step) {
              _WinConditionStep.riichi => _buildRiichiStep(),
              _WinConditionStep.dora => _buildDoraStep(ura: false),
              _WinConditionStep.uraDora => _buildDoraStep(ura: true),
              _WinConditionStep.waiting => _buildRecognitionWaiting(),
            },
          ),
        ],
      ),
    );
  }

  /// Top card of condition entry: the photo thumbnail and recognition state.
  Widget _recognitionProgressCard() {
    final total = _visibleSlotCount;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _scheme.surface,
        border: Border.all(color: _scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.feature),
      ),
      child: Row(
        children: [
          if (_capturedBytes != null) ...[
            _photoFrame(
              radius: AppRadius.iconTile,
              child: SizedBox(
                width: 90,
                height: 58,
                child: Image.memory(_capturedBytes!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _recognitionComplete ? Icons.check_circle : Icons.circle,
                      size: _recognitionComplete ? 16 : 10,
                      color: _colors.detectionBox,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _recognitionComplete ? '認識完了' : '牌を認識中',
                      style: _text.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _recognitionComplete
                      ? '条件を入力すると結果を表示します'
                      : '条件入力と並行して処理しています',
                  style: _text.bodySmall,
                ),
              ],
            ),
          ),
          if (total > 0)
            Text(
              '$_identifiedCount / $total',
              style: _text.titleSmall?.copyWith(color: _scheme.primary),
            ),
        ],
      ),
    );
  }

  Widget _stepDots(_WinConditionStep current) {
    const steps = [
      _WinConditionStep.riichi,
      _WinConditionStep.dora,
      _WinConditionStep.uraDora,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final step in steps)
          Container(
            width: step == current ? 32 : 9,
            height: 9,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: step == current ? _scheme.primary : _scheme.outlineVariant,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
      ],
    );
  }

  Widget _stepHeading(String tag, String title) => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _colors.soft,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Text(
          tag,
          style: _text.labelSmall?.copyWith(color: _scheme.primary),
        ),
      ),
      const SizedBox(height: AppSpacing.m),
      Text(title, textAlign: TextAlign.center, style: _text.headlineSmall),
    ],
  );

  Widget _buildRiichiStep() => ListView(
    padding: const EdgeInsets.all(AppSpacing.l),
    children: [
      _stepHeading('立直', '立直しましたか？'),
      const SizedBox(height: AppSpacing.xl),
      _AnswerCard(
        label: 'はい',
        icon: Icons.check,
        primary: true,
        onTap: () => _selectRiichiForWinFlow(true),
      ),
      const SizedBox(height: AppSpacing.m),
      _AnswerCard(
        label: 'いいえ',
        icon: Icons.remove,
        primary: false,
        onTap: () => _selectRiichiForWinFlow(false),
      ),
      const SizedBox(height: AppSpacing.xl),
      Text(
        '枠と牌の認識結果は、計算結果を表示する前に確認・訂正できます',
        textAlign: TextAlign.center,
        style: _text.bodySmall,
      ),
    ],
  );

  Widget _buildDoraStep({required bool ura}) {
    final selected = ura ? _context.uraDoraIndicators : _context.doraIndicators;
    final slots = ura
        ? math.max(1, _context.doraIndicators.length)
        : _doraSlotCount;
    final label = ura ? '裏ドラ表示牌' : '表ドラ表示牌';
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        _stepHeading(ura ? '裏ドラ' : '表ドラ', ura ? '裏ドラを選択' : '表ドラを選択'),
        const SizedBox(height: AppSpacing.l),
        Row(
          children: [
            Expanded(child: Text(label, style: _text.titleSmall)),
            if (ura && _context.doraIndicators.isNotEmpty)
              _buildReferenceDora()
            else
              Text('最大4枚', style: _text.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _scheme.surface,
            border: Border.all(color: _scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              for (var index = 0; index < slots; index++)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s),
                  child: GestureDetector(
                    onTap: index < selected.length
                        ? () => _removeConditionTile(index, ura: ura)
                        : null,
                    child: Container(
                      width: 48,
                      height: 62,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: _scheme.surface,
                        border: Border.all(
                          color: index == selected.length
                              ? _scheme.primary
                              : _scheme.outlineVariant,
                          width: index == selected.length ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: index < selected.length
                          ? TileGlyph(tileCode: selected[index])
                          : Icon(Icons.add, color: _scheme.outline),
                    ),
                  ),
                ),
              if (!ura && slots < 4)
                IconButton(
                  onPressed: () => setState(() => _doraSlotCount += 1),
                  style: IconButton.styleFrom(
                    backgroundColor: _colors.soft,
                    foregroundColor: _scheme.primary,
                  ),
                  icon: const Icon(Icons.add),
                  tooltip: 'ドラ表示牌を追加',
                ),
              const Spacer(),
              TextButton(
                onPressed: () => _skipDoraStep(ura: ura),
                child: const Text('あとで'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        SizedBox(
          height: 300,
          child: TileImagePicker(
            showHeader: false,
            onTileSelected: (tile) => _selectConditionTile(tile, ura: ura),
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceDora() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('表ドラ', style: _text.bodySmall),
      const SizedBox(width: 6),
      for (final tile in _context.doraIndicators)
        SizedBox(width: 22, height: 30, child: TileGlyph(tileCode: tile)),
    ],
  );

  Widget _buildRecognitionWaiting() => ListView(
    padding: const EdgeInsets.all(AppSpacing.l),
    children: [
      _recognitionStatusCard(
        title: '牌を識別しています',
        subtitle: '入力は完了しています。完了すると結果を自動で表示します',
      ),
    ],
  );

  // ════════════════════════════════════════
  // Phase 1: Camera
  // ════════════════════════════════════════

  Widget _buildCameraPhase() {
    if (kIsWeb) {
      return SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: _purpose.label,
              subtitle: '手牌の写真から確認',
              trailing: HeaderHomeButton(
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            Expanded(
              child: PhotoInput(busy: _isCapturing, onPick: _pickPhoto),
            ),
          ],
        ),
      );
    }
    if (_cameraInitError != null) return _buildCameraError();
    final ready = _controller != null && _controller!.value.isInitialized;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: _purpose.label,
            subtitle: '手牌を読み取り',
            trailing: HeaderHomeButton(
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                _photoFrame(
                  child: AspectRatio(
                    aspectRatio:
                        captureFrameAspectRatio *
                        captureGuideWidthFactor /
                        captureGuideHeightFactor,
                    child: ready
                        ? _buildCaptureAreaPreview()
                        : Center(
                            child: Text(
                              'カメラ初期化中...',
                              style: _text.bodyMedium?.copyWith(
                                color: _colors.onDark,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  '手牌が枠に収まるように撮影してください',
                  textAlign: TextAlign.center,
                  style: _text.bodyMedium?.copyWith(
                    color: _scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.l),
                Row(
                  children: [
                    Expanded(child: Text('槓子の数', style: _text.titleSmall)),
                    Text('槓子があるときだけ選択', style: _text.bodySmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                _buildExpectedTileCountSelector(),
                const SizedBox(height: AppSpacing.s),
                Text(
                  '${_purpose.label}は手牌${_purpose.defaultTileCount}枚＋槓子1つにつき1枚で読み取ります',
                  style: _text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.l),
                Center(child: _shutterButton(enabled: ready && !_isCapturing)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _isCapturing ? '撮影中...' : '撮影',
                  textAlign: TextAlign.center,
                  style: _text.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shutterButton({required bool enabled}) => Semantics(
    button: true,
    enabled: enabled,
    label: '撮影',
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('shutter-button'),
      onTap: enabled ? _capture : null,
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _scheme.primary, width: 3),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? _scheme.primary : _scheme.surfaceContainerHigh,
          ),
          child: _isCapturing
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _scheme.onPrimary,
                  ),
                )
              : null,
        ),
      ),
    ),
  );

  Widget _buildCameraError() => SafeArea(
    child: Column(
      children: [
        ScreenHeader(
          title: 'カメラを開始できません',
          trailing: HeaderHomeButton(
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.no_photography_outlined,
                    color: _scheme.onSurfaceVariant,
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Text(
                    _cameraInitError!,
                    textAlign: TextAlign.center,
                    style: _text.bodyMedium,
                  ),
                  if (widget.cameras.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.l),
                    FilledButton.icon(
                      onPressed: _initCamera,
                      icon: const Icon(Icons.refresh),
                      label: const Text('再試行'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildWideCameraPreview() {
    final previewSize = _controller!.value.previewSize;
    if (previewSize == null) return CameraPreview(_controller!);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }

  /// Shows only the same sub-region persisted by [prepareCapturedFrame].
  /// The source preview remains 16:9, while the viewport expands the guide
  /// crop to fill the available width. This keeps off-frame reflections out
  /// of both what the user sees and what final recognition receives.
  Widget _buildCaptureAreaPreview() => LayoutBuilder(
    builder: (context, constraints) {
      final sourceWidth = constraints.maxWidth / captureGuideWidthFactor;
      final sourceHeight = constraints.maxHeight / captureGuideHeightFactor;
      return ClipRect(
        child: OverflowBox(
          alignment: const Alignment(0, 0.5),
          minWidth: sourceWidth,
          maxWidth: sourceWidth,
          minHeight: sourceHeight,
          maxHeight: sourceHeight,
          child: _buildWideCameraPreview(),
        ),
      );
    },
  );

  /// The tile-count choice, asked as the number of 槓子 (0-4, default 0):
  /// the expected tiles are the purpose's 13 or 14 plus one per 槓子. 3 and 4
  /// are rare, so they may sit past the edge (decided 2026-10-08).
  Widget _buildExpectedTileCountSelector({bool redetectOnChange = false}) {
    final base = _purpose.defaultTileCount;
    return TileCountSelector(
      selectedCount: _expectedTileCount,
      counts: [for (var kans = 0; kans <= _maxKans; kans++) base + kans],
      includeAuto: false,
      labelOf: (count) => '${count - base}',
      semanticsOf: (count) => '槓子${count - base}つ（$count枚）',
      onChanged: (selected) async {
        setState(() => _expectedTileCount = selected);
        if (redetectOnChange && _capturedImage != null) {
          await _redetectInRegion(_cropRegion);
        }
      },
    );
  }

  // ════════════════════════════════════════
  // Phase 3: Results
  // ════════════════════════════════════════

  /// The results screen's photo preview shows whatever detection actually
  /// ran on — the full photo normally, or just `_cropRegion` after the
  /// FEZ-93 recovery flow — rather than always the uncropped original, so
  /// the displayed framing matches what the boxes below were found in.
  /// Box editing (`_openBoxEditor`, via `onTap`) still always operates in
  /// `_capturedImage`'s own full pixel space regardless of this preview, so
  /// boxes here are shifted by the crop's own top-left to match.
  Widget _buildTileMarkerOverlay() {
    final region = _cropRegion;
    final displayBytes = region != null ? _cropDisplayBytes : null;
    if (region == null || displayBytes == null) {
      return TileMarkerOverlay(
        imageBytes: _capturedBytes!,
        imageWidth: _capturedImage!.width,
        imageHeight: _capturedImage!.height,
        boxes: _tileQuads.map((q) => q?.boundingRect).toList(),
        tiles: _tiles,
        onTap: _openBoxEditor,
      );
    }
    return TileMarkerOverlay(
      imageBytes: displayBytes,
      imageWidth: region.width.round(),
      imageHeight: region.height.round(),
      boxes: _tileQuads
          .map((q) => q?.boundingRect.shift(-region.topLeft))
          .toList(),
      tiles: _tiles,
      onTap: _openBoxEditor,
    );
  }

  /// Aspect ratio of whatever `_buildTileMarkerOverlay` is currently
  /// showing — must track it exactly, or the preview would be stretched to
  /// the wrong shape.
  double get _displayAspectRatio {
    final region = _cropRegion;
    if (region != null && _cropDisplayBytes != null) {
      return region.width / region.height;
    }
    return _capturedImage!.width / _capturedImage!.height;
  }

  String get _resultsTitle => switch (_purpose) {
    ScanPurpose.score => '点数計算結果',
    ScanPurpose.wait => '待ち確認結果',
    ScanPurpose.discard => '何を切る',
    ScanPurpose.callAdvice => '鳴き判断',
  };

  bool get _hasResult =>
      _analysisResult != null ||
      _isNotWinning ||
      _tsumoScoreResult != null ||
      _ronScoreResult != null;

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(AppSpacing.l),
    decoration: BoxDecoration(
      color: _scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: _scheme.outlineVariant),
    ),
    child: child,
  );

  Widget _busyCard(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.m,
      vertical: AppSpacing.l,
    ),
    decoration: BoxDecoration(
      color: _scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.s),
        Text(message, style: _text.bodyMedium),
      ],
    ),
  );

  Widget _trainingDataButton() {
    final busy = _isSendingTraining || _isUndoingTraining;
    final color = _colors.developer.color;
    return TextButton.icon(
      onPressed: busy
          ? null
          : _trainingDataSent
          ? _undoTrainingData
          : _sendTrainingData,
      icon: busy
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(
              _trainingDataSent ? Icons.undo : Icons.school,
              size: 18,
              color: color,
            ),
      label: Text(
        _isSendingTraining
            ? '送信中...'
            : _isUndoingTraining
            ? '取り消し中...'
            : _trainingDataSent
            ? '取り消す'
            : '学習データ送信',
        style: TextStyle(color: color),
      ),
    );
  }

  /// Whether the photo, tile count and trimming are shown in the
  /// recognition card. Null follows [_recognitionNeedsAttention]; a tap on
  /// the toggle fixes it until the next photo.
  bool? _recognitionDetailsExpanded;

  /// Recognition went wrong enough that the photo-side controls are needed:
  /// nothing detected, a count other than the expected one, or tiles left
  /// unidentified after classification finished.
  bool get _recognitionNeedsAttention {
    final detected = _tileQuads.where((quad) => quad != null).length;
    if (detected == 0) return true;
    final expected = _expectedTileCount;
    if (expected != null
        ? detected != expected
        : detected < 13 || detected > 18) {
      return true;
    }
    final classifying =
        _isRunningFullClassification || _isClassifying.any((value) => value);
    return !classifying &&
        _tiles.any((tile) => tile != null) &&
        !_allDetectedTilesReady;
  }

  /// 「認識結果を確認」: the identified tile row and the あがり牌/副露
  /// controls, with the photo, tile count and trimming folded behind a
  /// toggle (opened automatically when recognition needs attention).
  Widget _recognitionCard() {
    final media = MediaQuery.sizeOf(context);
    final expanded = _recognitionDetailsExpanded ?? _recognitionNeedsAttention;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('認識結果を確認', style: _text.titleMedium)),
              TextButton.icon(
                key: const ValueKey('recognition-details-toggle'),
                onPressed: () =>
                    setState(() => _recognitionDetailsExpanded = !expanded),
                iconAlignment: IconAlignment.end,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                label: const Text('写真・枚数'),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.s),
            // Tapping a marker opens the full-screen box editor for that
            // tile (`_openBoxEditor`). The photo is capped in both width and
            // height so a landscape shot doesn't eat the whole screen.
            if (_capturedBytes != null) ...[
              Center(
                child: RepaintBoundary(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: media.width,
                      maxHeight: media.height * 0.4,
                    ),
                    child: _photoFrame(
                      radius: AppRadius.card,
                      child: AspectRatio(
                        aspectRatio: _displayAspectRatio,
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: _buildTileMarkerOverlay(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
            ],
            _buildExpectedTileCountSelector(redetectOnChange: true),
            const SizedBox(height: AppSpacing.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('add-tile-box'),
                  onPressed: _slotCount < _maxPhysicalTiles
                      ? _addTileBox
                      : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSizes.tapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('枠を追加'),
                ),
                const SizedBox(width: AppSpacing.s),
                if (_cropRegion != null)
                  IconButton(
                    onPressed: () => _redetectInRegion(null),
                    icon: const Icon(Icons.undo),
                    tooltip: '元の範囲に戻す',
                  ),
                OutlinedButton(
                  onPressed: _cropAndRedetect,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSizes.tapTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                    ),
                  ),
                  child: const Text('トリミング'),
                ),
              ],
            ),
            Divider(height: AppSpacing.xl, color: _scheme.outlineVariant),
          ] else
            const SizedBox(height: AppSpacing.s),
          // Each crop paired with its identified tile directly below (or
          // "?" until classification finishes), in one row that scrolls
          // sideways. Tapping the crop opens the box editor; tapping the
          // tile opens the tile picker.
          SingleChildScrollView(
            key: const ValueKey('recognized-tile-row'),
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < _visibleSlotCount; index++) ...[
                  if (index > 0) const SizedBox(width: 3),
                  _buildResultTile(index, 40),
                ],
              ],
            ),
          ),
          // Gated on every detected box having a tile — before that there's
          // nothing yet to mark as 副露 or あがり牌.
          if (_allDetectedTilesReady) ...[
            const SizedBox(height: AppSpacing.s),
            _buildTileControlsRow(),
          ],
          // Every tile is read but the check hasn't run yet: say what to do
          // next, since the 実行 button sits apart at the bottom.
          if (_allDetectedTilesReady &&
              !_hasResult &&
              !_isScoring &&
              !_isInterpreting) ...[
            const SizedBox(height: AppSpacing.s),
            const StatusBanner(
              kind: StatusKind.info,
              message: '読み取り結果が合っていれば、下の「実行」を押してください。違う牌はタップして直せます。',
            ),
          ],
          if (widget.showTrainingDataActions && _trainingTilesReady)
            Align(
              alignment: Alignment.centerRight,
              child: _trainingDataButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsPhase() {
    final isScore = _operation == HandOperation.score;
    final asksAi =
        _purpose == ScanPurpose.discard || _purpose == ScanPurpose.callAdvice;
    return SafeArea(
      child: Column(
        children: [
          ScreenHeader(
            title: _resultsTitle,
            subtitle: isScore ? '認識・条件を変更可能' : '認識結果を変更可能',
            onBack: _backToCamera,
            trailing: HeaderHomeButton(
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _recognitionCard(),
                  const SizedBox(height: AppSpacing.m),

                  if (widget.winnerOptions.isNotEmpty) ...[
                    _buildWinnerSelector(),
                    const SizedBox(height: AppSpacing.m),
                  ],

                  // Winds and 表ドラ for every check (the analysis API uses the
                  // context); 裏ドラ and the win-time chips only for scoring.
                  GameStatePanel(
                    context_: _context,
                    onChanged: (c) => setState(() => _updateContext(c)),
                    conditionChips: isScore ? _conditionChips() : const [],
                    showUraDora: isScore,
                  ),
                  const SizedBox(height: AppSpacing.l),

                  if (_runError case final message?) ...[
                    StatusBanner(kind: StatusKind.error, message: message),
                    const SizedBox(height: AppSpacing.m),
                  ],
                  _buildInlineScoreResult(),
                  if (!isScore && _isScoring) _busyCard('結果を更新中...'),
                  if (!isScore && _analysisResult != null)
                    AnalysisResultPanel(
                      result: _analysisResult!,
                      onAskAiAboutCall: _purpose == ScanPurpose.callAdvice
                          ? (candidate) => _openAiChat(selectedCall: candidate)
                          : null,
                      onAskAiWithDiscardFocus: _purpose == ScanPurpose.discard
                          ? (focus) => _openAiChat(discardFocus: focus)
                          : null,
                    ),
                  if (_isScoring || _hasResult)
                    const SizedBox(height: AppSpacing.l),

                  if (asksAi && _analysisResult != null) ...[
                    FilledButton.icon(
                      onPressed: () => _openAiChat(),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                        _chatMessages.isEmpty ? 'AIに質問' : 'AIとの会話を続ける',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                  ],

                  // 「別の確認へ」 (UC-01 結果後). Not offered in the match win
                  // flow, whose result is recorded into the round state.
                  if (widget.onScoreConfirmed == null &&
                      !_isScoring &&
                      _hasResult) ...[
                    OutlinedButton(
                      key: const ValueKey('switch-purpose-button'),
                      onPressed: _switchPurpose,
                      child: const Text('同じ牌で別の確認をする'),
                    ),
                    const SizedBox(height: AppSpacing.m),
                  ],

                  if (_interpretation != null) ...[
                    _buildInterpretationConfirmation(),
                    const SizedBox(height: AppSpacing.m),
                  ],
                ],
              ),
            ),
          ),

          // Fixed action bar, only until there is a result: "識別実行" until
          // every detected tile has a type, then "実行", which runs
          // `_runInterpretationAndAnalyze` (interpretation + confirm+analyze in
          // one tap). Score results then recalculate automatically on edits.
          if (!_hasResult)
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.l,
                AppSpacing.s,
                AppSpacing.l,
                AppSpacing.s,
              ),
              decoration: BoxDecoration(
                color: _scheme.surface,
                border: Border(top: BorderSide(color: _scheme.outlineVariant)),
              ),
              child: !_allDetectedTilesReady
                  ? FilledButton.icon(
                      onPressed:
                          _croppedImages.any((c) => c != null) &&
                              !_isRunningFullClassification &&
                              !_isClassifying.any((value) => value)
                          ? _runClassification
                          : null,
                      icon: _isRunningFullClassification
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        _isRunningFullClassification ? '識別中...' : '識別実行',
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: !_isScoring && !_isInterpreting
                          ? _runInterpretationAndAnalyze
                          : null,
                      icon: _isScoring || _isInterpreting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow, size: 20),
                      label: const Text('実行'),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Large yes/no answer card of the condition-entry steps.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final foreground = primary ? colors.onDark : scheme.onSurface;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.modal),
          side: primary
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        color: primary ? null : scheme.surface,
        child: Ink(
          decoration: primary
              ? BoxDecoration(
                  gradient: LinearGradient(colors: colors.sessionGradient),
                )
              : null,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 96,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: primary
                            ? colors.onDark.withValues(alpha: 0.18)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Icon(icon, color: foreground),
                    ),
                    const SizedBox(width: AppSpacing.l),
                    Expanded(
                      child: Text(
                        label,
                        style: text.headlineSmall?.copyWith(color: foreground),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: foreground),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
