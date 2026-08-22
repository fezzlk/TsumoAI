import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../services/tile_classifier.dart';
import '../services/api_client.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';
import '../widgets/tile_slot_row.dart';
import '../widgets/tile_keyboard.dart';
import '../widgets/context_input_panel.dart';
import '../widgets/score_result_panel.dart';
import '../widgets/tile_marker_overlay.dart';
import '../services/training_data_client.dart';
import '../services/tile_segmenter.dart';

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

  // Captured image
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
  final List<bool> _isClassifying = List.filled(14, false);
  final List<img.Image?> _croppedImages = List.filled(14, null);
  final List<Rect?> _tileBoxes = List.filled(14, null);

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
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);

    bool capturedOk = false;
    try {
      final xFile = await _controller!.takePicture();
      final rawBytes = await File(xFile.path).readAsBytes();
      final rawDecoded = img.decodeImage(rawBytes);
      if (rawDecoded == null) throw Exception('画像のデコードに失敗');
      // The `camera` plugin here writes no EXIF orientation tag at all
      // (confirmed empirically: hasOrientation=false), so bakeOrientation is
      // a no-op — it always delivers a fixed-shape portrait buffer
      // regardless of how the phone is actually held. The UI is locked to
      // portrait (see main.dart) and the user always physically turns the
      // phone sideways to shoot a tile row along its long edge, so correct
      // for that with a fixed rotation instead of relying on (absent)
      // metadata. Re-encoding (rather than keeping the original file's
      // bytes) keeps every downstream consumer (display, detection,
      // per-tile crop/classify) working from the same already-rotated
      // pixels.
      final decoded = img.copyRotate(rawDecoded, angle: -90);
      final bytes = Uint8List.fromList(img.encodeJpg(decoded));
      capturedOk = true;

      setState(() {
        _capturedBytes = bytes;
        _capturedImage = decoded;
        _phase = _ScanPhase.detecting;
        _imageTransform = Matrix4.identity();
        _errorMessage = null;
        for (int i = 0; i < 14; i++) {
          _tiles[i] = null;
          _isClassifying[i] = false;
          _croppedImages[i] = null;
          _tileBoxes[i] = null;
        }
      });

      // Try automatic tile detection first; the manual grid-alignment phase
      // is a fallback for when detection doesn't find a clean 13/14-tile
      // hand (not the primary mechanism).
      final detectedBoxes = await compute(segmentTilesFromBytes, bytes);
      if (!mounted) return;

      if (detectedBoxes.length == 13 || detectedBoxes.length == 14) {
        await _classifyBoxesAndFinish(detectedBoxes);
      } else {
        setState(() => _phase = _ScanPhase.align);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '撮影エラー: $e';
        // If capture/decode itself failed, stay on the camera phase; if it
        // was detection that failed after a successful capture, fall back
        // to manual alignment rather than getting stuck on the spinner.
        if (capturedOk) _phase = _ScanPhase.align;
      });
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  // ── Phase 2: Align grid & classify ──

  Future<void> _classifyFromGrid(
      Rect gridScreenRect, double baseLeft, double baseTop,
      double baseW, double baseH) async {
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
      final minX = [tl.dx, tr.dx, bl.dx, br.dx].reduce(math.min).round().clamp(0, srcImage.width - 1);
      final minY = [tl.dy, tr.dy, bl.dy, br.dy].reduce(math.min).round().clamp(0, srcImage.height - 1);
      final maxX = [tl.dx, tr.dx, bl.dx, br.dx].reduce(math.max).round().clamp(0, srcImage.width - 1);
      final maxY = [tl.dy, tr.dy, bl.dy, br.dy].reduce(math.max).round().clamp(0, srcImage.height - 1);

      final cropW = (maxX - minX).clamp(1, srcImage.width - minX);
      final cropH = (maxY - minY).clamp(1, srcImage.height - minY);
      boxes.add(Rect.fromLTWH(minX.toDouble(), minY.toDouble(), cropW.toDouble(), cropH.toDouble()));
    }

    await _classifyBoxesAndFinish(boxes);
  }

  /// Crop and on-device-classify each of [boxes] (in `_capturedImage`'s pixel
  /// coordinate space), populating `_tiles`/`_croppedImages`/`_tileBoxes`,
  /// then move to the results phase. Shared by both the automatic-detection
  /// path and the manual grid-alignment fallback.
  Future<void> _classifyBoxesAndFinish(List<Rect> boxes) async {
    final srcImage = _capturedImage;
    if (srcImage == null || !_classifier.isReady) {
      setState(() => _errorMessage = '牌識別モデルが読み込まれていません');
      return;
    }

    setState(() {
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = true; _croppedImages[i] = null; _tileBoxes[i] = null; }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });

    // TEMPORARY DEBUG: dump the source photo and each naive/refined crop to
    // Documents so they can be pulled off-device for direct inspection
    // (`xcrun devicectl device copy from ... /Documents/debug_crops`).
    Directory? debugDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      debugDir = Directory('${docs.path}/debug_crops');
      if (debugDir.existsSync()) debugDir.deleteSync(recursive: true);
      debugDir.createSync(recursive: true);
      File('${debugDir.path}/full.jpg').writeAsBytesSync(img.encodeJpg(srcImage));
    } catch (_) {
      debugDir = null;
    }

    for (int i = 0; i < boxes.length && i < 14; i++) {
      final box = boxes[i];
      final x = box.left.round().clamp(0, srcImage.width - 1);
      final y = box.top.round().clamp(0, srcImage.height - 1);
      final w = box.width.round().clamp(1, srcImage.width - x);
      final h = box.height.round().clamp(1, srcImage.height - y);

      final cropped = refineTileCrop(srcImage, box);
      if (debugDir != null) {
        final naive = img.copyCrop(srcImage, x: x, y: y, width: w, height: h);
        final idxStr = i.toString().padLeft(2, '0');
        File('${debugDir.path}/tile${idxStr}_naive.jpg').writeAsBytesSync(img.encodeJpg(naive));
        File('${debugDir.path}/tile${idxStr}_refined.jpg').writeAsBytesSync(img.encodeJpg(cropped));
      }
      _croppedImages[i] = cropped;
      _tileBoxes[i] = Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());

      final idx = i;
      final results = _classifier.classify(cropped, topK: 1);
      setState(() {
        _tiles[idx] = results.isNotEmpty ? results.first.tileCode : null;
        _isClassifying[idx] = false;
      });
    }

    setState(() => _phase = _ScanPhase.results);
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
      final hand = HandInput(closedTiles: tiles, melds: [], winTile: tiles.last);
      final request = ScoreRequest(hand: hand, context: _context, rules: RuleSet());
      final result = await _api.calculateScore(request);
      setState(() {
        if (result == null) { _isNotWinning = true; } else { _scoreResult = result; }
      });
    } catch (e) {
      setState(() => _errorMessage = 'スコア計算エラー: $e');
    } finally {
      setState(() => _isScoring = false);
    }
  }

  void _onSlotTap(int index) async {
    final selected = await TileKeyboard.show(context, currentTile: _tiles[index]);
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
        _isClassifying[i] = false;
        _croppedImages[i] = null;
        _tileBoxes[i] = null;
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
    if (images.length != 14 || tiles.length != 14) {
      setState(() => _errorMessage = '14枚すべての識別結果が必要です');
      return;
    }

    setState(() { _isSendingTraining = true; _errorMessage = null; });
    try {
      final count = await _trainingClient.uploadBatch(images: images, tileCodes: tiles);
      if (mounted) {
        setState(() { _trainingDataSent = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count枚の学習データを送信しました')),
        );
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
                child: Image.memory(_capturedBytes!, fit: BoxFit.contain, gaplessPlayback: true),
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
        body: Center(child: Text('カメラ初期化中...', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_controller!),
            // Simple instruction
            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _isCapturing ? null : _capture,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isCapturing ? Colors.grey : Colors.white.withValues(alpha: 0.3),
                    ),
                    child: _isCapturing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          )
                        : const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
            if (_errorMessage != null)
              Positioned(
                bottom: 130, left: 20, right: 20,
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
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
            final gridRect = Rect.fromLTWH(gridLeft, gridTop, gridTotalW, slotH);

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
                  left: baseLeft, top: baseTop,
                  width: baseW, height: baseH,
                  child: Transform(
                    transform: _imageTransform,
                    child: Image.memory(_capturedBytes!, fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                ),

                // Fixed overlay with grid cutouts
                ClipRect(
                  child: CustomPaint(
                    size: Size(viewW, viewH),
                    painter: _SlotOverlayPainter(slotRect: gridRect, slotCount: 14),
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
                      _gestureStartFocalPoint = details.localFocalPoint - origin;
                      _gestureStartScale = _gestureStartTransform!.getMaxScaleOnAxis();
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
                  child: const Text('和了牌',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),

                // Instructions
                Positioned(
                  top: 12, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  top: 12, right: 12,
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
                      _imageTransform = _imageTransform.multiplied(rotateAboutCenter);
                    }),
                    icon: const Icon(Icons.rotate_right, color: Colors.white70, size: 28),
                    tooltip: '90°回転',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ),

                // Bottom buttons
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Row(
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
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => _classifyFromGrid(
                              gridRect, baseLeft, baseTop, baseW, baseH,
                            ),
                            icon: const Icon(Icons.search, size: 20),
                            label: const Text('識別開始'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.withValues(alpha: 0.7),
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

  Widget _buildResultsPhase() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tile results row
              TileSlotRow(tiles: _tiles, isClassifying: _isClassifying, onSlotTap: _onSlotTap),
              const SizedBox(height: 8),

              // Full photo with detected-tile markers. Sized by the photo's
              // own aspect ratio (not a fixed screen fraction) so a portrait
              // capture gets a tall box and a landscape capture a short one
              // — the scrolling column below absorbs whichever it is.
              if (_capturedBytes != null && _capturedImage != null) ...[
                AspectRatio(
                  aspectRatio: _capturedImage!.width / _capturedImage!.height,
                  child: TileMarkerOverlay(
                    imageBytes: _capturedBytes!,
                    imageWidth: _capturedImage!.width,
                    imageHeight: _capturedImage!.height,
                    boxes: _tileBoxes,
                    tiles: _tiles,
                    onTap: _onSlotTap,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Cropped images preview
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 14,
                  itemBuilder: (_, i) {
                    final cropped = _croppedImages[i];
                    if (cropped == null) return const SizedBox(width: 40);
                    return Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Image.memory(
                        Uint8List.fromList(img.encodeJpg(cropped)),
                        width: 40, height: 56, fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Context input
              ContextInputPanel(context_: _context, onChanged: (c) => setState(() => _context = c)),
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
                      onPressed: _allTilesReady && !_isScoring ? _calculateScore : null,
                      icon: _isScoring
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],

              if (_isNotWinning) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('上がりの形になっていません',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
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
                    onPressed: _isSendingTraining || _trainingDataSent ? null : _sendTrainingData,
                    icon: _isSendingTraining
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_trainingDataSent ? Icons.check : Icons.school, size: 18),
                    label: Text(_isSendingTraining ? '送信中...'
                        : _trainingDataSent ? '送信済み' : '学習データとして送信'),
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
        Rect.fromLTWH(slotRect.left + i * slotW, slotRect.top, slotW, slotRect.height),
        clearPaint,
      );
    }

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < slotCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(slotRect.left + i * slotW, slotRect.top, slotW, slotRect.height),
        borderPaint,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(slotRect.left + (slotCount - 1) * slotW, slotRect.top, slotW, slotRect.height),
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
  final targetScale = (startScale * scaleFactorSinceStart).clamp(minScale, maxScale);
  final relativeScale = targetScale / startScale;
  final delta = Matrix4.identity()
    ..translateByDouble(currentFocalLocal.dx, currentFocalLocal.dy, 0, 1)
    ..rotateZ(rotationSinceStart)
    ..scaleByDouble(relativeScale, relativeScale, relativeScale, 1)
    ..translateByDouble(-startFocalLocal.dx, -startFocalLocal.dy, 0, 1);
  return delta.multiplied(startTransform);
}
