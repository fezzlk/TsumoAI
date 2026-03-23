import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/training_data_client.dart';
import '../widgets/tile_keyboard.dart';

/// Screen for collecting single-tile training data.
/// Flow: Camera → Capture → Align → Select label → Send → Repeat
class TrainingDataScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const TrainingDataScreen({super.key, required this.cameras});

  @override
  State<TrainingDataScreen> createState() => _TrainingDataScreenState();
}

enum _TDPhase { camera, align, label }

class _TrainingDataScreenState extends State<TrainingDataScreen> {
  CameraController? _controller;
  final TrainingDataClient _client = TrainingDataClient();

  _TDPhase _phase = _TDPhase.camera;
  Uint8List? _capturedBytes;
  img.Image? _capturedImage;

  // Image transform
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  double _imageRotation = 0.0;
  double _lastScaleValue = 1.0;
  double _lastRotationValue = 0.0;

  // Result
  img.Image? _croppedTile;
  String? _selectedTileCode;
  bool _isSending = false;
  int _sentCount = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(widget.cameras.first, ResolutionPreset.high, enableAudio: false);
    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final xFile = await _controller!.takePicture();
    final bytes = await File(xFile.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;

    setState(() {
      _capturedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      _capturedImage = decoded;
      _phase = _TDPhase.align;
      _imageOffset = Offset.zero;
      _imageScale = 1.0;
      _imageRotation = 0.0;
    });
  }

  void _cropAndSelectLabel(Size displaySize, Rect slotRect) {
    var image = _capturedImage!;

    if (_imageRotation.abs() > 0.01) {
      image = img.copyRotate(image, angle: -_imageRotation * 180 / math.pi);
    }

    final scaleX = image.width / displaySize.width;
    final scaleY = image.height / displaySize.height;
    final pad = slotRect.width * 0.1;

    final cropX = ((slotRect.left - pad) * scaleX).round().clamp(0, image.width - 1);
    final cropY = ((slotRect.top - pad) * scaleY).round().clamp(0, image.height - 1);
    final cropW = ((slotRect.width + pad * 2) * scaleX).round().clamp(1, image.width - cropX);
    final cropH = ((slotRect.height + pad * 2) * scaleY).round().clamp(1, image.height - cropY);

    setState(() {
      _croppedTile = img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);
      _selectedTileCode = null;
      _phase = _TDPhase.label;
    });
  }

  Future<void> _send() async {
    if (_croppedTile == null || _selectedTileCode == null) return;
    setState(() => _isSending = true);
    try {
      await _client.uploadTile(tileImage: _croppedTile!, tileCode: _selectedTileCode!);
      setState(() => _sentCount++);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信完了 ($_sentCount枚目)'), duration: const Duration(seconds: 1)),
        );
      }
      // Go back to camera for next tile
      setState(() {
        _phase = _TDPhase.camera;
        _capturedBytes = null;
        _capturedImage = null;
        _croppedTile = null;
        _selectedTileCode = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信エラー: $e')),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('学習データ作成 ($_sentCount枚送信済み)'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: switch (_phase) {
          _TDPhase.camera => _buildCamera(),
          _TDPhase.align => _buildAlign(),
          _TDPhase.label => _buildLabel(),
        },
      ),
    );
  }

  Widget _buildCamera() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        Positioned(
          top: 20, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: const Text('牌1枚を撮影してください', style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
        ),
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _capture,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlign() {
    return LayoutBuilder(builder: (context, constraints) {
      final viewW = constraints.maxWidth;
      final viewH = constraints.maxHeight;

      // Single tile slot: centered, reasonable size
      final slotW = viewW * 0.3;
      final slotH = slotW / 0.75;
      final slotRect = Rect.fromLTWH((viewW - slotW) / 2, (viewH - slotH) / 2, slotW, slotH);

      // Image positioning
      final imgW = _capturedImage!.width.toDouble();
      final imgH = _capturedImage!.height.toDouble();
      final imgAspect = imgW / imgH;
      late final double baseW, baseH;
      if (imgAspect > viewW / viewH) { baseW = viewW; baseH = viewW / imgAspect; }
      else { baseH = viewH; baseW = viewH * imgAspect; }
      final scaledW = baseW * _imageScale;
      final scaledH = baseH * _imageScale;
      final imgLeft = (viewW - scaledW) / 2 + _imageOffset.dx;
      final imgTop = (viewH - scaledH) / 2 + _imageOffset.dy;

      final gridInImgX = (slotRect.left - imgLeft) / _imageScale;
      final gridInImgY = (slotRect.top - imgTop) / _imageScale;
      final slotInImage = Rect.fromLTWH(gridInImgX, gridInImgY, slotW / _imageScale, slotH / _imageScale);
      final displaySize = Size(baseW, baseH);

      return Stack(
        children: [
          Positioned(left: imgLeft, top: imgTop, width: scaledW, height: scaledH,
            child: Transform.rotate(angle: _imageRotation,
              child: Image.memory(_capturedBytes!, fit: BoxFit.fill))),

          // Overlay with single slot cutout
          ClipRect(child: CustomPaint(size: Size(viewW, viewH),
            painter: _SingleSlotPainter(slotRect: slotRect))),

          // Gesture
          Positioned.fill(child: GestureDetector(
            onScaleStart: (_) { _lastScaleValue = _imageScale; _lastRotationValue = _imageRotation; },
            onScaleUpdate: (d) => setState(() {
              _imageOffset += d.focalPointDelta;
              if (d.pointerCount >= 2) {
                _imageScale = (_lastScaleValue * d.scale).clamp(0.5, 5.0);
                _imageRotation = _lastRotationValue + d.rotation;
              }
            }),
          )),

          // 90° button
          Positioned(top: 12, right: 12, child: IconButton(
            onPressed: () => setState(() => _imageRotation += math.pi / 2),
            icon: const Icon(Icons.rotate_right, color: Colors.white70, size: 28),
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
          )),

          // Bottom buttons
          Positioned(left: 0, right: 0, bottom: 0, child: Container(
            padding: const EdgeInsets.all(16), color: Colors.black87,
            child: Row(children: [
              Expanded(child: ElevatedButton(
                onPressed: () => setState(() { _phase = _TDPhase.camera; _capturedBytes = null; }),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.15), foregroundColor: Colors.white),
                child: const Text('撮り直す'),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton.icon(
                onPressed: () => _cropAndSelectLabel(displaySize, slotInImage),
                icon: const Icon(Icons.crop, size: 20),
                label: const Text('切り出し'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withValues(alpha: 0.7), foregroundColor: Colors.white),
              )),
            ]),
          )),
        ],
      );
    });
  }

  Widget _buildLabel() {
    final jpgBytes = _croppedTile != null ? Uint8List.fromList(img.encodeJpg(_croppedTile!)) : null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Cropped tile preview
          if (jpgBytes != null)
            Container(
              height: 200,
              decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(jpgBytes, fit: BoxFit.contain),
              ),
            ),
          const SizedBox(height: 16),

          // Selected tile display
          Text(
            _selectedTileCode ?? '牌を選択してください',
            style: TextStyle(
              color: _selectedTileCode != null ? Colors.greenAccent : Colors.white54,
              fontSize: 24, fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Tile keyboard inline
          TileKeyboard(
            currentTile: _selectedTileCode,
            onTileSelected: (tile) => setState(() => _selectedTileCode = tile),
          ),
          const SizedBox(height: 16),

          // Send button
          Row(
            children: [
              Expanded(child: ElevatedButton(
                onPressed: () => setState(() { _phase = _TDPhase.align; _selectedTileCode = null; }),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.15), foregroundColor: Colors.white),
                child: const Text('戻る'),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton.icon(
                onPressed: _selectedTileCode != null && !_isSending ? _send : null,
                icon: _isSending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 20),
                label: const Text('送信'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTileCode != null ? Colors.orange.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.1),
                  foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _SingleSlotPainter extends CustomPainter {
  final Rect slotRect;
  _SingleSlotPainter({required this.slotRect});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawRect(slotRect, Paint()..blendMode = BlendMode.clear);
    canvas.drawRect(slotRect, Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SingleSlotPainter old) => slotRect != old.slotRect;
}
