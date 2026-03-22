import 'dart:io';
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

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  final TileClassifier _classifier = TileClassifier();
  final ApiClient _api = ApiClient();

  final List<String?> _tiles = List.filled(14, null);
  final List<bool> _isClassifying = List.filled(14, false);

  bool _isCapturing = false;
  bool _isScoring = false;
  ScoreResponse? _scoreResult;
  bool _isNotWinning = false;
  String? _errorMessage;

  ContextInput _context = ContextInput();
  Rect _slotAreaRect = Rect.zero;

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

    final viewSize = context.size;
    if (viewSize == null) return;

    final scaleX = fullImage.width / viewSize.width;
    final scaleY = fullImage.height / viewSize.height;
    final slotWidth = _slotAreaRect.width / 14;
    final slotHeight = _slotAreaRect.height;

    final futures = <Future<void>>[];
    for (int i = 0; i < 14; i++) {
      final slotLeft = _slotAreaRect.left + i * slotWidth;
      final slotTop = _slotAreaRect.top;

      final cropX = (slotLeft * scaleX).round().clamp(0, fullImage.width - 1);
      final cropY = (slotTop * scaleY).round().clamp(0, fullImage.height - 1);
      final cropW = (slotWidth * scaleX).round().clamp(1, fullImage.width - cropX);
      final cropH = (slotHeight * scaleY).round().clamp(1, fullImage.height - cropY);

      final cropped = img.copyCrop(fullImage, x: cropX, y: cropY, width: cropW, height: cropH);
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

  void _reset() {
    setState(() {
      for (int i = 0; i < 14; i++) { _tiles[i] = null; _isClassifying[i] = false; }
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

            // Always lay out 14 slots along the LONGER axis
            final longerAxis = viewW >= viewH ? viewW : viewH;
            final isLandscape = viewW >= viewH;

            // Slot dimensions: 14 tiles along the longer axis
            final padding = 16.0;
            final slotTotalLength = longerAxis - padding * 2;
            final tileW = slotTotalLength / 14;
            final tileH = tileW / 0.75;

            // Position slots centered on screen
            late final Rect slotRect;
            if (isLandscape) {
              // Landscape: slots horizontal, centered vertically at ~35%
              final slotTop = (viewH * 0.35) - (tileH / 2);
              slotRect = Rect.fromLTWH(padding, slotTop, slotTotalLength, tileH);
            } else {
              // Portrait: slots still horizontal along the long axis? No.
              // In portrait, longer axis is height.
              // But user wants slots along the longer axis.
              // However "枠の並び方向自体は今のやり方であっている" means horizontal.
              // In portrait, we keep horizontal but use full width.
              final slotTotalW = viewW - padding * 2;
              final tw = slotTotalW / 14;
              final th = tw / 0.75;
              final slotTop = (viewH * 0.35) - (th / 2);
              slotRect = Rect.fromLTWH(padding, slotTop, slotTotalW, th);
            }

            _slotAreaRect = slotRect;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Camera preview - fill screen
                SizedBox.expand(
                  child: CameraPreview(_controller!),
                ),

                // Semi-transparent overlay with transparent slot cutouts
                ClipRect(
                  child: CustomPaint(
                    size: Size(viewW, viewH),
                    painter: _SlotOverlayPainter(
                      slotRect: slotRect,
                      slotCount: 14,
                    ),
                  ),
                ),

                // "和了牌" label next to last slot
                Positioned(
                  left: slotRect.right - (slotRect.width / 14) / 2 - 20,
                  top: slotRect.top - 20,
                  child: const Text(
                    '和了牌',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Bottom controls
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: _buildBottomControls(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tile results
          TileSlotRow(tiles: _tiles, isClassifying: _isClassifying, onSlotTap: _onSlotTap),
          const SizedBox(height: 8),

          // Context input
          ContextInputPanel(context_: _context, onChanged: (c) => setState(() => _context = c)),
          const SizedBox(height: 8),

          // Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _capture,
                  icon: _isCapturing
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.camera_alt, size: 20),
                  label: Text(_isCapturing ? '撮影中...' : '撮影'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
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

          if (_errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],

          if (_isNotWinning) ...[
            const SizedBox(height: 6),
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
            const SizedBox(height: 6),
            ScoreResultPanel(scoreResponse: _scoreResult!),
          ],
        ],
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
    // Save layer so BlendMode.clear works
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Draw full semi-transparent overlay
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    // Cut out transparent windows
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final slotW = slotRect.width / slotCount;
    for (int i = 0; i < slotCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(slotRect.left + i * slotW, slotRect.top, slotW, slotRect.height),
        clearPaint,
      );
    }

    // Draw slot borders (white, thin)
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

    // Green border on last slot (win tile)
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
