import 'dart:io';
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

  _ScanPhase _phase = _ScanPhase.camera;

  // Captured image
  Uint8List? _capturedBytes;
  img.Image? _capturedImage;

  // Grid position on the displayed image (user-adjustable)
  Offset _gridOffset = Offset.zero;
  double _gridScale = 1.0;

  // Tile results
  final List<String?> _tiles = List.filled(14, null);
  final List<bool> _isClassifying = List.filled(14, false);
  final List<img.Image?> _croppedImages = List.filled(14, null);

  bool _isCapturing = false;
  bool _isScoring = false;
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
        _capturedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
        _capturedImage = decoded;
        _phase = _ScanPhase.align;
        _gridOffset = Offset.zero;
        _gridScale = 1.0;
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

  Future<void> _classifyFromGrid(Size imageDisplaySize, Rect gridRect) async {
    final fullImage = _capturedImage;
    if (fullImage == null || !_classifier.isReady) {
      setState(() => _errorMessage = '牌識別モデルが読み込まれていません');
      return;
    }

    setState(() {
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = true; _croppedImages[i] = null; }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });

    // Simple 1:1 mapping: displayed image fills the widget via BoxFit.contain
    final scaleX = fullImage.width / imageDisplaySize.width;
    final scaleY = fullImage.height / imageDisplaySize.height;

    final slotW = gridRect.width / 14;
    // Add 15% padding for better capture
    final padX = slotW * 0.15;
    final padY = gridRect.height * 0.15;

    for (int i = 0; i < 14; i++) {
      final slotLeft = gridRect.left + i * slotW;
      final slotTop = gridRect.top;

      final cropX = ((slotLeft - padX) * scaleX).round().clamp(0, fullImage.width - 1);
      final cropY = ((slotTop - padY) * scaleY).round().clamp(0, fullImage.height - 1);
      final cropW = ((slotW + padX * 2) * scaleX).round().clamp(1, fullImage.width - cropX);
      final cropH = ((gridRect.height + padY * 2) * scaleY).round().clamp(1, fullImage.height - cropY);

      final cropped = img.copyCrop(fullImage, x: cropX, y: cropY, width: cropW, height: cropH);
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
      _capturedBytes = null;
      _capturedImage = null;
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = false; _croppedImages[i] = null; }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });
  }

  bool get _allTilesReady => _tiles.every((t) => t != null);

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

            // Display captured image with BoxFit.contain
            // Calculate the actual displayed image size
            final imgW = _capturedImage!.width.toDouble();
            final imgH = _capturedImage!.height.toDouble();
            final imgAspect = imgW / imgH;
            final viewAspect = viewW / viewH;

            late final double dispW, dispH, dispLeft, dispTop;
            if (imgAspect > viewAspect) {
              dispW = viewW;
              dispH = viewW / imgAspect;
              dispLeft = 0;
              dispTop = (viewH - dispH) / 2;
            } else {
              dispH = viewH;
              dispW = viewH * imgAspect;
              dispLeft = (viewW - dispW) / 2;
              dispTop = 0;
            }

            // Default grid: 14 tiles across the displayed image width
            final defaultSlotW = dispW * 0.9 / 14;
            final defaultSlotH = defaultSlotW / 0.75;
            final defaultGridW = defaultSlotW * 14;
            final defaultGridH = defaultSlotH;
            final defaultGridLeft = dispLeft + (dispW - defaultGridW) / 2;
            final defaultGridTop = dispTop + (dispH - defaultGridH) / 2;

            final gridW = defaultGridW * _gridScale;
            final gridH = defaultGridH * _gridScale;
            final gridLeft = defaultGridLeft + _gridOffset.dx;
            final gridTop = defaultGridTop + _gridOffset.dy;

            // Grid rect in the displayed image coordinate system (relative to dispLeft, dispTop)
            final gridRectInImage = Rect.fromLTWH(
              (gridLeft - dispLeft),
              (gridTop - dispTop),
              gridW,
              gridH,
            );
            // Scale to actual image display size for cropping
            final imageDisplaySize = Size(dispW, dispH);

            return Stack(
              children: [
                // Captured image
                Positioned(
                  left: dispLeft, top: dispTop,
                  width: dispW, height: dispH,
                  child: Image.memory(_capturedBytes!, fit: BoxFit.fill),
                ),

                // Overlay with grid cutouts
                ClipRect(
                  child: CustomPaint(
                    size: Size(viewW, viewH),
                    painter: _SlotOverlayPainter(
                      slotRect: Rect.fromLTWH(gridLeft, gridTop, gridW, gridH),
                      slotCount: 14,
                    ),
                  ),
                ),

                // Drag gesture for grid
                Positioned.fill(
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _gridOffset += details.delta;
                      });
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount >= 2) {
                        setState(() {
                          _gridScale = (_gridScale * details.scale).clamp(0.3, 3.0);
                        });
                      }
                    },
                  ),
                ),

                // "和了牌" label
                Positioned(
                  left: gridLeft + gridW - gridW / 14 / 2 - 20,
                  top: gridTop - 18,
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
                        'ドラッグで枠を移動、ピンチでサイズ調整',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
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
                            onPressed: () => _classifyFromGrid(imageDisplaySize, gridRectInImage),
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
