import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/tile_classifier.dart';
import '../services/api_client.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';
import '../widgets/tile_slot_row.dart';
import '../widgets/tile_keyboard.dart';
import '../widgets/context_input_panel.dart';
import '../widgets/score_result_panel.dart';
import '../services/training_data_client.dart';

class ScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ScanScreen({super.key, required this.cameras});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanPhase { camera, align, results }

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  final TileClassifier _classifier = TileClassifier();
  final ApiClient _api = ApiClient();
  final TrainingDataClient _trainingClient = TrainingDataClient();

  _ScanPhase _phase = _ScanPhase.camera;

  // Captured image
  img.Image? _capturedImage; // decoded for cropping
  Uint8List? _displayBytes;  // rotated JPEG for display (matches _classifyFromGrid)
  double _displayRotation = 0.0; // rotation baked into _displayBytes

  // Image transform (user drags/pinches/rotates the image to align with fixed grid)
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  double _imageRotation = 0.0; // radians
  double _lastScaleValue = 1.0;
  double _lastRotationValue = 0.0;

  // Tile results
  final List<String?> _tiles = List.filled(14, null);
  final List<bool> _isClassifying = List.filled(14, false);
  final List<img.Image?> _croppedImages = List.filled(14, null);

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

    try {
      final xFile = await _controller!.takePicture();
      final bytes = await File(xFile.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('画像のデコードに失敗');

      setState(() {
        _capturedImage = decoded;
        _displayBytes = bytes; // initially no rotation, use original
        _displayRotation = 0.0;
        _phase = _ScanPhase.align;
        _imageOffset = Offset.zero;
        _imageScale = 1.0;
        _imageRotation = 0.0;
        _lastScaleValue = 1.0;
        _lastRotationValue = 0.0;
        _errorMessage = null;
        for (int i = 0; i < 14; i++) {
          _tiles[i] = null;
          _isClassifying[i] = false;
          _croppedImages[i] = null;
        }
      });
    } catch (e) {
      setState(() => _errorMessage = '撮影エラー: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  // ── Phase 2: Align grid & classify ──

  /// Render exactly what the user sees into a pixel buffer, then crop
  /// each grid slot from it. No coordinate transformation needed.
  Future<void> _classifyFromGrid(Size viewSize, Rect gridScreenRect,
      double imgLeft, double imgTop, double scaledW, double scaledH) async {
    final srcImage = _capturedImage;
    if (srcImage == null || !_classifier.isReady) {
      setState(() => _errorMessage = '牌識別モデルが読み込まれていません');
      return;
    }

    setState(() {
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = true; _croppedImages[i] = null; }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });

    // Render the image as the user sees it:
    // 1. Rotate the source image
    var rendered = img.Image.from(srcImage);
    if (_imageRotation.abs() > 0.01) {
      final degrees = _imageRotation * 180 / math.pi;
      rendered = img.copyRotate(rendered, angle: -degrees);
    }

    // 2. Scale to the displayed size
    // The UI uses OverflowBox + Transform.rotate on the ORIGINAL image,
    // where the Positioned box is the rotated bounding box size.
    // But img.copyRotate already produces the rotated bounding box,
    // so we resize to fill that box.
    rendered = img.copyResize(rendered,
        width: scaledW.round().clamp(1, 4000),
        height: scaledH.round().clamp(1, 4000));

    // 3. Place on a canvas matching the view size
    final canvasW = viewSize.width.round();
    final canvasH = viewSize.height.round();
    final canvas = img.Image(width: canvasW, height: canvasH);

    debugPrint('DEBUG classify: canvas=${canvasW}x$canvasH rendered=${rendered.width}x${rendered.height} pos=($imgLeft,$imgTop) grid=$gridScreenRect');

    img.compositeImage(canvas, rendered,
        dstX: imgLeft.round(), dstY: imgTop.round());

    // 4. Crop each grid slot directly from the canvas (screen coordinates)
    final slotW = gridScreenRect.width / 14;
    final padX = slotW * 0.1;
    final padY = gridScreenRect.height * 0.1;

    for (int i = 0; i < 14; i++) {
      final sx = (gridScreenRect.left + i * slotW - padX).round().clamp(0, canvasW - 1);
      final sy = (gridScreenRect.top - padY).round().clamp(0, canvasH - 1);
      final sw = (slotW + padX * 2).round().clamp(1, canvasW - sx);
      final sh = (gridScreenRect.height + padY * 2).round().clamp(1, canvasH - sy);

      final cropped = img.copyCrop(canvas, x: sx, y: sy, width: sw, height: sh);
      _croppedImages[i] = cropped;

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
      _capturedImage = null;
      _displayBytes = null;
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = false; _croppedImages[i] = null; }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
      _isSendingTraining = false;
      _trainingDataSent = false;
    });
  }

  void _rebuildDisplayBytes() {
    if (_capturedImage == null) return;
    if ((_displayRotation - _imageRotation).abs() < 0.01 && _displayBytes != null) return;

    var preview = img.Image.from(_capturedImage!);
    if (_imageRotation.abs() > 0.01) {
      final degrees = _imageRotation * 180 / math.pi;
      preview = img.copyRotate(preview, angle: -degrees);
    }
    _displayBytes = Uint8List.fromList(img.encodeJpg(preview, quality: 92));
    _displayRotation = _imageRotation;
    if (mounted) setState(() {});
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
      case _ScanPhase.align:
        return _buildAlignPhase();
      case _ScanPhase.results:
        return _buildResultsPhase();
    }
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

            // Use the BAKED rotation (_displayRotation) for layout sizing.
            // Live rotation delta is handled by Transform.rotate only.
            final srcW = _capturedImage!.width.toDouble();
            final srcH = _capturedImage!.height.toDouble();
            final cosA = math.cos(_displayRotation).abs();
            final sinA = math.sin(_displayRotation).abs();
            final rotW = srcW * cosA + srcH * sinA;
            final rotH = srcW * sinA + srcH * cosA;
            final rotAspect = rotW / rotH;
            final viewAspect = viewW / viewH;

            // Base size for the rotated image (contain)
            late final double baseW, baseH;
            if (rotAspect > viewAspect) {
              baseW = viewW;
              baseH = viewW / rotAspect;
            } else {
              baseH = viewH;
              baseW = viewH * rotAspect;
            }

            final scaledW = baseW * _imageScale;
            final scaledH = baseH * _imageScale;
            final imgLeft = (viewW - scaledW) / 2 + _imageOffset.dx;
            final imgTop = (viewH - scaledH) / 2 + _imageOffset.dy;

            return Stack(
              children: [
                // Image: baked rotation + live Transform.rotate for gesture delta
                Positioned(
                  left: imgLeft, top: imgTop,
                  width: scaledW, height: scaledH,
                  child: _displayBytes != null
                      ? Transform.rotate(
                          // Show live rotation delta on top of baked rotation
                          angle: _imageRotation - _displayRotation,
                          child: Image.memory(_displayBytes!, fit: BoxFit.fill, gaplessPlayback: true),
                        )
                      : const SizedBox(),
                ),

                // Fixed overlay with grid cutouts
                ClipRect(
                  child: CustomPaint(
                    size: Size(viewW, viewH),
                    painter: _SlotOverlayPainter(slotRect: gridRect, slotCount: 14),
                  ),
                ),

                // Gesture: drag/pinch/rotate the IMAGE
                Positioned.fill(
                  child: GestureDetector(
                    onScaleStart: (_) {
                      _lastScaleValue = _imageScale;
                      _lastRotationValue = _imageRotation;
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        _imageOffset += details.focalPointDelta;
                        if (details.pointerCount >= 2) {
                          _imageScale = (_lastScaleValue * details.scale).clamp(0.5, 5.0);
                          _imageRotation = _lastRotationValue + details.rotation;
                        }
                      });
                    },
                    onScaleEnd: (_) => _rebuildDisplayBytes(),
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
                    onPressed: () {
                      setState(() => _imageRotation += math.pi / 2);
                      _rebuildDisplayBytes();
                    },
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
                              Size(viewW, viewH), gridRect,
                              imgLeft, imgTop, scaledW, scaledH,
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
