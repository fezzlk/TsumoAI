import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  final TileClassifier _classifier = TileClassifier();
  final ApiClient _api = ApiClient();

  // 14 tile slots
  final List<String?> _tiles = List.filled(14, null);
  final List<bool> _isClassifying = List.filled(14, false);

  bool _isCapturing = false;
  bool _isScoring = false;
  ScoreResponse? _scoreResult;
  bool _isNotWinning = false;
  String? _errorMessage;

  ContextInput _context = ContextInput();

  // Slot overlay rect in preview coordinates (set during build)
  Rect _slotAreaRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    // Force landscape orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    _initCamera();
    _initClassifier();
  }

  Future<void> _initClassifier() async {
    try {
      await _classifier.init();
    } catch (e) {
      debugPrint('Classifier init error: $e');
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
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller?.dispose();
    _classifier.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() {
      _isCapturing = true;
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = true; }
    });

    try {
      final xFile = await _controller!.takePicture();
      final bytes = await File(xFile.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Failed to decode image');

      // Crop each slot and classify
      await _classifySlots(decoded);
    } catch (e) {
      setState(() {
        _errorMessage = 'エラー: $e';
        for (int i = 0; i < 14; i++) { _isClassifying[i] = false; }
      });
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _classifySlots(img.Image fullImage) async {
    if (!_classifier.isReady) {
      setState(() {
        _errorMessage = '牌識別モデルが読み込まれていません';
        for (int i = 0; i < 14; i++) { _isClassifying[i] = false; }
      });
      return;
    }

    // Calculate crop regions based on the slot area
    // The slot area rect is in preview coordinates.
    // We need to map it to camera image coordinates.
    // Get the actual view size (set during build via LayoutBuilder)
    final viewSize = context.size;
    if (viewSize == null) return;

    final scaleX = fullImage.width / viewSize.width;
    final scaleY = fullImage.height / viewSize.height;

    final slotWidth = _slotAreaRect.width / 14;
    final slotHeight = _slotAreaRect.height;

    // Classify each slot
    final futures = <Future<void>>[];
    for (int i = 0; i < 14; i++) {
      final slotLeft = _slotAreaRect.left + i * slotWidth;
      final slotTop = _slotAreaRect.top;

      // Map to image coordinates
      final cropX = (slotLeft * scaleX).round().clamp(0, fullImage.width - 1);
      final cropY = (slotTop * scaleY).round().clamp(0, fullImage.height - 1);
      final cropW = (slotWidth * scaleX).round().clamp(1, fullImage.width - cropX);
      final cropH = (slotHeight * scaleY).round().clamp(1, fullImage.height - cropY);

      final cropped = img.copyCrop(fullImage, x: cropX, y: cropY, width: cropW, height: cropH);

      // Classify asynchronously
      final idx = i;
      futures.add(Future(() {
        final results = _classifier.classify(cropped, topK: 1);
        if (mounted) {
          setState(() {
            _tiles[idx] = results.isNotEmpty ? results.first.tileCode : null;
            _isClassifying[idx] = false;
          });
        }
      }));
    }

    await Future.wait(futures);
  }

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
      final request = ScoreRequest(hand: hand, context: _context, rules: RuleSet());
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
    final selected = await TileKeyboard.show(context, currentTile: _tiles[index]);
    if (selected != null && mounted) {
      setState(() {
        _tiles[index] = selected;
        _scoreResult = null;
        _isNotWinning = false;
      });
    }
  }

  void _reset() {
    setState(() {
      for (int i = 0; i < 14; i++) {
        _tiles[i] = null;
        _isClassifying[i] = false;
      }
      _scoreResult = null;
      _isNotWinning = false;
      _errorMessage = null;
    });
  }

  bool get _allTilesReady => _tiles.every((t) => t != null);
  bool get _anyTileReady => _tiles.any((t) => t != null);

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('カメラ初期化中...', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewW = constraints.maxWidth;
            final viewH = constraints.maxHeight;

            // Tile slot dimensions: 14 tiles across the full width
            final tileW = (viewW - 32) / 14; // 16px padding each side
            final tileH = tileW / 0.75;
            final slotAreaLeft = 16.0;
            final slotAreaTop = (viewH * 0.3) - (tileH / 2); // positioned in upper third

            _slotAreaRect = Rect.fromLTWH(slotAreaLeft, slotAreaTop, viewW - 32, tileH);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Camera preview
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize!.height,
                      height: _controller!.value.previewSize!.width,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),

                // Semi-transparent overlay with transparent slot windows
                CustomPaint(
                  size: Size(viewW, viewH),
                  painter: _SlotOverlayPainter(
                    slotRect: _slotAreaRect,
                    slotCount: 14,
                  ),
                ),

                // Bottom controls area
                Positioned(
                  left: 0, right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tile slot results
                        TileSlotRow(
                          tiles: _tiles,
                          isClassifying: _isClassifying,
                          onSlotTap: _onSlotTap,
                        ),
                        const SizedBox(height: 8),

                        // Context input
                        ContextInputPanel(
                          context_: _context,
                          onChanged: (c) => setState(() => _context = c),
                        ),
                        const SizedBox(height: 8),

                        // Action buttons row
                        Row(
                          children: [
                            // Capture button
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isCapturing ? null : _capture,
                                icon: _isCapturing
                                    ? const SizedBox(
                                        width: 16, height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.camera_alt, size: 20),
                                label: Text(_isCapturing ? '撮影中...' : '撮影'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.2),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Score button
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _allTilesReady && !_isScoring ? _calculateScore : null,
                                icon: _isScoring
                                    ? const SizedBox(
                                        width: 16, height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.calculate, size: 20),
                                label: const Text('点数計算'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _allTilesReady
                                      ? Colors.green.withOpacity(0.6)
                                      : Colors.white.withOpacity(0.1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            if (_anyTileReady) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _reset,
                                icon: const Icon(Icons.refresh, color: Colors.white54),
                                tooltip: 'リセット',
                              ),
                            ],
                          ],
                        ),

                        // Error message
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ],

                        // Not winning
                        if (_isNotWinning) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '上がりの形になっていません',
                              style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],

                        // Score result
                        if (_scoreResult != null) ...[
                          const SizedBox(height: 6),
                          ScoreResultPanel(scoreResponse: _scoreResult!),
                        ],
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
}

/// Paints a semi-transparent overlay with transparent windows for each tile slot.
class _SlotOverlayPainter extends CustomPainter {
  final Rect slotRect;
  final int slotCount;

  _SlotOverlayPainter({required this.slotRect, required this.slotCount});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);

    // Draw full overlay
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);

    // Cut out transparent windows for each slot
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final slotW = slotRect.width / slotCount;

    for (int i = 0; i < slotCount; i++) {
      final rect = Rect.fromLTWH(
        slotRect.left + i * slotW,
        slotRect.top,
        slotW,
        slotRect.height,
      );
      canvas.drawRect(rect, clearPaint);
    }

    // Draw slot borders
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < slotCount; i++) {
      final rect = Rect.fromLTWH(
        slotRect.left + i * slotW,
        slotRect.top,
        slotW,
        slotRect.height,
      );
      canvas.drawRect(rect, borderPaint);
    }

    // Highlight last slot (win tile) with green border
    final winBorder = Paint()
      ..color = Colors.greenAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final winRect = Rect.fromLTWH(
      slotRect.left + (slotCount - 1) * slotW,
      slotRect.top,
      slotW,
      slotRect.height,
    );
    canvas.drawRect(winRect, winBorder);
  }

  @override
  bool shouldRepaint(covariant _SlotOverlayPainter old) =>
      slotRect != old.slotRect || slotCount != old.slotCount;
}
