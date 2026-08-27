import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/tile_classifier.dart';
import '../services/api_client.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';
import '../widgets/tile_image_picker.dart';
import '../widgets/context_input_panel.dart';
import '../widgets/score_result_panel.dart';
import '../widgets/tile_marker_overlay.dart';
import '../services/training_data_client.dart';
import '../services/tile_segmenter.dart';
import '../services/tile_assets.dart';
import '../models/tile_quad.dart';
import 'tile_box_editor_screen.dart';

class ScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ScanScreen({super.key, required this.cameras});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanPhase { camera, detecting, align, results }

class _ScanScreenState extends State<ScanScreen> {
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

  // Image transform: pan/zoom/rotate combined into a single matrix so that
  // scale and rotation always pivot around the gesture's own focal point
  // instead of the image's center (see _buildAlignPhase for the composition).
  Matrix4 _imageTransform = Matrix4.identity();
  Matrix4? _gestureStartTransform;
  Offset? _gestureStartFocalPoint;
  double _gestureStartScale = 1.0;

  // Tile results
  final List<String?> _tiles = List.filled(14, null);
  // Latest on-device predictions, kept unchanged when the user corrects
  // `_tiles`, so training uploads can measure real-world recognition accuracy.
  final List<String?> _predictedTiles = List.filled(14, null);
  final List<bool> _isClassifying = List.filled(14, false);
  final List<img.Image?> _croppedImages = List.filled(14, null);
  // Cached JPEG encoding of `_croppedImages`, computed once when a crop is
  // set rather than in build() — re-encoding 14 images per rebuild (e.g. on
  // every drag frame of a box edit) was the main source of the "重い"
  // (heavy/laggy) results-screen feedback.
  final List<Uint8List?> _croppedImageThumbnails = List.filled(14, null);
  // Each tile's crop region as 4 independent corners (not just an
  // axis-aligned Rect) — see `TileQuad` for why: a tile photographed at an
  // angle projects as a general quadrilateral, not just a rotated
  // rectangle. In `_capturedImage`'s (corrected) pixel space.
  final List<TileQuad?> _tileQuads = List.filled(14, null);

  bool _isCapturing = false;
  bool _isScoring = false;
  bool _isSendingTraining = false;
  bool _trainingDataSent = false;
  ScoreResponse? _scoreResult;
  bool _isNotWinning = false;
  String? _errorMessage;

  ContextInput _context = ContextInput();

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
      if (mounted) {
        setState(() => _errorMessage = '牌識別モデル読込エラー: $e');
      }
    }
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
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
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  void dispose() {
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
        _imageTransform = Matrix4.identity();
        _errorMessage = null;
        for (int i = 0; i < 14; i++) {
          _tiles[i] = null;
          _predictedTiles[i] = null;
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
      setState(() => _errorMessage = '撮影エラー: $e');
      // If capture/decode itself failed, stay on the camera phase; if it was
      // detection that failed after a successful capture, still move on to
      // the results phase (empty boxes) rather than getting stuck on the
      // spinner — the user can add all 14 boxes manually from there.
      if (capturedOk) await _classifyBoxesAndFinish(const []);
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  // ── Phase 2: Align grid & classify ──

  Future<void> _classifyFromGrid(
    Rect gridScreenRect,
    double baseLeft,
    double baseTop,
    double baseW,
    double baseH,
  ) async {
    final srcImage = _capturedImage;
    if (srcImage == null) return;

    final origin = Offset(baseLeft, baseTop);
    final origW = srcImage.width.toDouble();
    final origH = srcImage.height.toDouble();
    final inverse = Matrix4.inverted(_imageTransform);

    // Map a screen point back through the (pan/zoom/rotate) display transform
    // to a pixel coordinate in the original captured image.
    Offset toImagePixel(Offset screenPoint) {
      final content = MatrixUtils.transformPoint(inverse, screenPoint - origin);
      return Offset(content.dx * (origW / baseW), content.dy * (origH / baseH));
    }

    final slotW = gridScreenRect.width / 14;
    final padX = slotW * 0.2;
    final padY = gridScreenRect.height * 0.2;

    final boxes = <Rect>[];
    for (int i = 0; i < 14; i++) {
      // Grid slot corners in screen space
      final slotLeft = gridScreenRect.left + i * slotW - padX;
      final slotTop = gridScreenRect.top - padY;
      final slotRight = slotLeft + slotW + padX * 2;
      final slotBottom = slotTop + gridScreenRect.height + padY * 2;

      // Map all 4 corners to image pixels
      final tl = toImagePixel(Offset(slotLeft, slotTop));
      final tr = toImagePixel(Offset(slotRight, slotTop));
      final bl = toImagePixel(Offset(slotLeft, slotBottom));
      final br = toImagePixel(Offset(slotRight, slotBottom));

      // Bounding box in image pixels
      final minX = [
        tl.dx,
        tr.dx,
        bl.dx,
        br.dx,
      ].reduce(math.min).round().clamp(0, srcImage.width - 1);
      final minY = [
        tl.dy,
        tr.dy,
        bl.dy,
        br.dy,
      ].reduce(math.min).round().clamp(0, srcImage.height - 1);
      final maxX = [
        tl.dx,
        tr.dx,
        bl.dx,
        br.dx,
      ].reduce(math.max).round().clamp(0, srcImage.width - 1);
      final maxY = [
        tl.dy,
        tr.dy,
        bl.dy,
        br.dy,
      ].reduce(math.max).round().clamp(0, srcImage.height - 1);

      final cropW = (maxX - minX).clamp(1, srcImage.width - minX);
      final cropH = (maxY - minY).clamp(1, srcImage.height - minY);
      boxes.add(
        Rect.fromLTWH(
          minX.toDouble(),
          minY.toDouble(),
          cropW.toDouble(),
          cropH.toDouble(),
        ),
      );
    }

    await _classifyBoxesAndFinish(boxes);
  }

  /// Crop and on-device-classify each of [boxes] (in `_capturedImage`'s pixel
  /// coordinate space), populating `_tiles`/`_croppedImages`/`_tileQuads`,
  /// then move to the results phase. Shared by both the automatic-detection
  /// path (which has [angleHints], one per box — see `segmentTilesWithHints`)
  /// and the manual grid-alignment fallback (which doesn't).
  Future<void> _classifyBoxesAndFinish(
    List<Rect> boxes, {
    List<double>? angleHints,
  }) async {
    final srcImage = _capturedImage;
    if (srcImage == null) return;

    setState(() {
      for (int i = 0; i < 14; i++) {
        _tiles[i] = null;
        _predictedTiles[i] = null;
        _isClassifying[i] = false;
        _croppedImages[i] = null;
        _croppedImageThumbnails[i] = null;
        _tileQuads[i] = null;
      }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });

    for (int i = 0; i < boxes.length && i < 14; i++) {
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
      setState(() => _errorMessage = '牌識別モデルが読み込まれていません');
      return;
    }

    setState(() {
      for (int i = 0; i < 14; i++) {
        if (_croppedImages[i] != null) _isClassifying[i] = true;
      }
      _errorMessage = null;
    });

    for (int i = 0; i < 14; i++) {
      final cropped = _croppedImages[i];
      if (cropped == null) continue;
      final results = _classifier.classify(cropped, topK: 1);
      setState(() {
        final prediction = results.isNotEmpty ? results.first.tileCode : null;
        _tiles[i] = prediction;
        _predictedTiles[i] = prediction;
        _isClassifying[i] = false;
      });
    }

    setState(() {
      _scoreResult = null;
      _isNotWinning = false;
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
  /// immediately.
  Future<void> _openBoxEditor(int index, {TileQuad? initialDecodedQuad}) async {
    final srcImage = _capturedImage;
    final imageBytes = _capturedBytes;
    if (srcImage == null || imageBytes == null) return;

    final quad = _tileQuads[index] ?? initialDecodedQuad;
    if (quad == null) return;

    final newQuad = await Navigator.of(context).push<TileQuad>(
      MaterialPageRoute(
        builder: (_) => TileBoxEditorScreen(
          rawImageBytes: imageBytes,
          rawWidth: srcImage.width,
          rawHeight: srcImage.height,
          initialQuad: quad,
        ),
      ),
    );
    if (newQuad == null || !mounted) return;

    final cropped = _cropQuad(srcImage, newQuad);

    setState(() {
      _tileQuads[index] = newQuad;
      _croppedImages[index] = cropped;
      _croppedImageThumbnails[index] = Uint8List.fromList(
        img.encodeJpg(cropped),
      );
      _tiles[index] = null;
      _predictedTiles[index] = null;
      _scoreResult = null;
      _isNotWinning = false;
    });
  }

  /// Opens the editor for the next empty slot (in practice always index 13,
  /// the 和了牌 slot, since detection only ever falls short by exactly one
  /// tile), seeded with a placeholder box (median size of the other tiles,
  /// centered in the photo) for the user to drag into place.
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

  // ── Phase 3: Score ──

  Future<void> _calculateScore() async {
    final tiles = _tiles.whereType<String>().toList();
    if (tiles.length != 14) return;

    setState(() {
      _isScoring = true;
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });

    try {
      final hand = HandInput(
        closedTiles: tiles,
        melds: [],
        winTile: tiles.last,
      );
      final request = ScoreRequest(
        hand: hand,
        context: _context,
        rules: RuleSet(),
      );
      final result = await _api.calculateScore(request);
      setState(() {
        if (result == null) {
          _isNotWinning = true;
        } else {
          _scoreResult = result;
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'スコア計算エラー: $e');
    } finally {
      setState(() => _isScoring = false);
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
        _scoreResult = null;
        _isNotWinning = false;
      });
    }
  }

  void _backToCamera() {
    setState(() {
      _phase = _ScanPhase.camera;
      _capturedBytes = null;
      _capturedImage = null;
      for (int i = 0; i < 14; i++) {
        _tiles[i] = null;
        _predictedTiles[i] = null;
        _isClassifying[i] = false;
        _croppedImages[i] = null;
        _croppedImageThumbnails[i] = null;
        _tileQuads[i] = null;
      }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
      _isSendingTraining = false;
      _trainingDataSent = false;
    });
  }

  bool get _allTilesReady => _tiles.every((t) => t != null);

  Future<void> _sendTrainingData() async {
    if (_isSendingTraining || _trainingDataSent) return;
    final images = _croppedImages.whereType<img.Image>().toList();
    final tiles = _tiles.whereType<String>().toList();
    final predictedTiles = _predictedTiles.whereType<String>().toList();
    if (images.length != 14 ||
        tiles.length != 14 ||
        predictedTiles.length != 14) {
      setState(() => _errorMessage = '14枚すべての識別結果が必要です');
      return;
    }

    setState(() {
      _isSendingTraining = true;
      _errorMessage = null;
    });
    try {
      final count = await _trainingClient.uploadBatch(
        images: images,
        tileCodes: tiles,
        predictedTileCodes: predictedTiles,
      );
      if (mounted) {
        setState(() {
          _trainingDataSent = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$count枚の学習データを送信しました')));
      }
    } catch (e) {
      setState(() => _errorMessage = '送信エラー: $e');
    } finally {
      if (mounted) setState(() => _isSendingTraining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _ScanPhase.camera:
        return _buildCameraPhase();
      case _ScanPhase.detecting:
        return _buildDetectingPhase();
      case _ScanPhase.align:
        return _buildAlignPhase();
      case _ScanPhase.results:
        return _buildResultsPhase();
    }
  }

  // ════════════════════════════════════════
  // Phase: Detecting (automatic tile detection)
  // ════════════════════════════════════════

  Widget _buildDetectingPhase() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
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
      ),
    );
  }

  // ════════════════════════════════════════
  // Phase 1: Camera
  // ════════════════════════════════════════

  Widget _buildCameraPhase() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('カメラ初期化中...', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
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
                    '牌14枚が映るように撮影してください',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
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
            if (_errorMessage != null)
              Positioned(
                bottom: 130,
                left: 20,
                right: 20,
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════
  // Phase 2: Align grid on captured image
  // ════════════════════════════════════════

  Widget _buildAlignPhase() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewW = constraints.maxWidth;
            final viewH = constraints.maxHeight;

            // Fixed grid: centered, 80% of view width
            final gridTotalW = viewW * 0.85;
            final slotW = gridTotalW / 14;
            final slotH = slotW / 0.75;
            final gridLeft = (viewW - gridTotalW) / 2;
            final gridTop = (viewH - slotH) / 2;
            final gridRect = Rect.fromLTWH(
              gridLeft,
              gridTop,
              gridTotalW,
              slotH,
            );

            // Box size based on ORIGINAL image aspect (no rotation distortion)
            final srcW = _capturedImage!.width.toDouble();
            final srcH = _capturedImage!.height.toDouble();
            final imgAspect = srcW / srcH;
            final viewAspect = viewW / viewH;

            late final double baseW, baseH;
            if (imgAspect > viewAspect) {
              baseW = viewW;
              baseH = viewW / imgAspect;
            } else {
              baseH = viewH;
              baseW = viewH * imgAspect;
            }

            // The image's own box never moves or resizes; all pan/zoom/rotate
            // from user gestures lives entirely in `_imageTransform`, applied
            // below via Transform. This keeps a single source of truth for
            // the display transform instead of separate offset/scale/rotation
            // variables that have to be kept in sync by hand.
            final baseLeft = (viewW - baseW) / 2;
            final baseTop = (viewH - baseH) / 2;
            final origin = Offset(baseLeft, baseTop);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: baseLeft,
                  top: baseTop,
                  width: baseW,
                  height: baseH,
                  child: Transform(
                    transform: _imageTransform,
                    child: Image.memory(
                      _capturedBytes!,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),

                // Fixed overlay with grid cutouts
                ClipRect(
                  child: CustomPaint(
                    size: Size(viewW, viewH),
                    painter: _SlotOverlayPainter(
                      slotRect: gridRect,
                      slotCount: 14,
                    ),
                  ),
                ),

                // Gesture: drag/pinch/rotate the IMAGE. Scale and rotation are
                // cumulative-since-gesture-start values from Flutter's scale
                // recognizer, so the whole current gesture's transform is
                // rebuilt fresh each update, pivoting around the point that
                // was under the fingers when the gesture began — that point
                // stays under the fingers regardless of the image's current
                // rotation, which is what a naive per-axis add of offset/
                // scale/rotation could not guarantee.
                Positioned.fill(
                  child: GestureDetector(
                    onScaleStart: (details) {
                      _gestureStartTransform = _imageTransform.clone();
                      _gestureStartFocalPoint =
                          details.localFocalPoint - origin;
                      _gestureStartScale = _gestureStartTransform!
                          .getMaxScaleOnAxis();
                    },
                    onScaleUpdate: (details) {
                      final startFocal = _gestureStartFocalPoint;
                      final startTransform = _gestureStartTransform;
                      if (startFocal == null || startTransform == null) return;
                      setState(() {
                        _imageTransform = composeGestureTransform(
                          startTransform: startTransform,
                          startFocalLocal: startFocal,
                          startScale: _gestureStartScale,
                          currentFocalLocal: details.localFocalPoint - origin,
                          scaleFactorSinceStart: details.scale,
                          rotationSinceStart: details.rotation,
                        );
                      });
                    },
                    onScaleEnd: (_) {},
                  ),
                ),

                // "和了牌" label
                Positioned(
                  left: gridRect.right - slotW / 2 - 20,
                  top: gridRect.top - 18,
                  child: const Text(
                    '和了牌',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Instructions
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        '画像をドラッグ/ピンチして牌を枠に合わせてください',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ),

                // 90° rotation button
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    onPressed: () => setState(() {
                      // Rotate the image 90° about its own center, then keep
                      // applying whatever pan/zoom/rotation was already
                      // dialed in on top of that.
                      final center = Offset(baseW / 2, baseH / 2);
                      final rotateAboutCenter = Matrix4.identity()
                        ..translateByDouble(center.dx, center.dy, 0, 1)
                        ..rotateZ(math.pi / 2)
                        ..translateByDouble(-center.dx, -center.dy, 0, 1);
                      _imageTransform = _imageTransform.multiplied(
                        rotateAboutCenter,
                      );
                    }),
                    icon: const Icon(
                      Icons.rotate_right,
                      color: Colors.white70,
                      size: 28,
                    ),
                    tooltip: '90°回転',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ),

                // Bottom buttons
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _backToCamera,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.15,
                              ),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('撮り直す'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => _classifyFromGrid(
                              gridRect,
                              baseLeft,
                              baseTop,
                              baseW,
                              baseH,
                            ),
                            icon: const Icon(Icons.search, size: 20),
                            label: const Text('識別開始'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.withValues(
                                alpha: 0.7,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Full photo with detected-tile markers. Sized by the photo's
              // own aspect ratio (not a fixed screen fraction) so a portrait
              // capture gets a tall box and a landscape capture a short one
              // — the scrolling column below absorbs whichever it is.
              // Tapping a marker opens the full-screen box editor for that
              // tile (`_openBoxEditor`); pinch-zoom is safe to leave on
              // here since nothing on this screen does its own dragging
              // anymore (editing happens in `TileBoxEditorScreen`, a
              // separate route with no zoom of its own).
              if (_capturedBytes != null) ...[
                AspectRatio(
                  aspectRatio: _capturedImage!.width / _capturedImage!.height,
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: _buildTileMarkerOverlay(),
                  ),
                ),
                const SizedBox(height: 4),
                if (_tileQuads.any((q) => q == null))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _addMissingTileBox,
                      icon: const Icon(
                        Icons.add_box_outlined,
                        size: 18,
                        color: Colors.greenAccent,
                      ),
                      label: const Text(
                        '枠を追加',
                        style: TextStyle(color: Colors.greenAccent),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
              ],

              // Cropped images preview, each paired with its identified
              // tile's illustration directly below (or "?" until "識別実行"
              // has been run for it). Tapping the crop opens the box editor
              // (`_openBoxEditor`); tapping the illustration opens the
              // image-based picker (`_onSlotTap`) to correct it manually.
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 14,
                  itemBuilder: (_, i) {
                    final thumb = _croppedImageThumbnails[i];
                    if (thumb == null) return const SizedBox(width: 40);
                    final tile = _tiles[i];
                    final tileAsset = tile == null ? null : tileAssetPath(tile);
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => _openBoxEditor(i),
                            child: Image.memory(
                              thumb,
                              width: 40,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _onSlotTap(i),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: _isClassifying[i]
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
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
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // Runs AI classification for every cropped tile at once —
              // separate from cropping itself so the AI only runs when
              // explicitly asked for (see `_runClassification`).
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _croppedImages.any((c) => c != null)
                      ? _runClassification
                      : null,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('識別実行'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Context input
              ContextInputPanel(
                context_: _context,
                onChanged: (c) => setState(() => _context = c),
              ),
              const SizedBox(height: 12),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _backToCamera,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('撮り直す'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _allTilesReady && !_isScoring
                          ? _calculateScore
                          : null,
                      icon: _isScoring
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.calculate, size: 20),
                      label: const Text('点数計算'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _allTilesReady
                            ? Colors.green.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],

              if (_isNotWinning) ...[
                const SizedBox(height: 8),
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
              ],

              if (_scoreResult != null) ...[
                const SizedBox(height: 8),
                ScoreResultPanel(scoreResponse: _scoreResult!),
              ],

              // Training data send button
              if (_allTilesReady) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSendingTraining || _trainingDataSent
                        ? null
                        : _sendTrainingData,
                    icon: _isSendingTraining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _trainingDataSent ? Icons.check : Icons.school,
                            size: 18,
                          ),
                    label: Text(
                      _isSendingTraining
                          ? '送信中...'
                          : _trainingDataSent
                          ? '送信済み'
                          : '学習データとして送信',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _trainingDataSent
                          ? Colors.grey.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints semi-transparent overlay with transparent cutouts for tile slots.
class _SlotOverlayPainter extends CustomPainter {
  final Rect slotRect;
  final int slotCount;

  _SlotOverlayPainter({required this.slotRect, required this.slotCount});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final slotW = slotRect.width / slotCount;
    for (int i = 0; i < slotCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          slotRect.left + i * slotW,
          slotRect.top,
          slotW,
          slotRect.height,
        ),
        clearPaint,
      );
    }

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < slotCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          slotRect.left + i * slotW,
          slotRect.top,
          slotW,
          slotRect.height,
        ),
        borderPaint,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(
        slotRect.left + (slotCount - 1) * slotW,
        slotRect.top,
        slotW,
        slotRect.height,
      ),
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SlotOverlayPainter old) =>
      slotRect != old.slotRect || slotCount != old.slotCount;
}

/// Composes the display transform for one pan/zoom/rotate gesture update.
///
/// [scaleFactorSinceStart] and [rotationSinceStart] are the cumulative values
/// Flutter's scale gesture recognizer reports relative to gesture start (as
/// in [ScaleUpdateDetails.scale]/[.rotation]), not per-frame deltas. The
/// whole current gesture's transform is rebuilt from [startTransform] on
/// every call, pivoting scale and rotation around [startFocalLocal] — the
/// point that was under the fingers when the gesture began — so that point
/// stays under [currentFocalLocal] regardless of any rotation already
/// applied before the gesture started. Coordinates are all in the same
/// "local" space (i.e. relative to the transformed widget's own origin).
Matrix4 composeGestureTransform({
  required Matrix4 startTransform,
  required Offset startFocalLocal,
  required double startScale,
  required Offset currentFocalLocal,
  required double scaleFactorSinceStart,
  required double rotationSinceStart,
  double minScale = 0.5,
  double maxScale = 5.0,
}) {
  final targetScale = (startScale * scaleFactorSinceStart).clamp(
    minScale,
    maxScale,
  );
  final relativeScale = targetScale / startScale;
  final delta = Matrix4.identity()
    ..translateByDouble(currentFocalLocal.dx, currentFocalLocal.dy, 0, 1)
    ..rotateZ(rotationSinceStart)
    ..scaleByDouble(relativeScale, relativeScale, relativeScale, 1)
    ..translateByDouble(-startFocalLocal.dx, -startFocalLocal.dy, 0, 1);
  return delta.multiplied(startTransform);
}
