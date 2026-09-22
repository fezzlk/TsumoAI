import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/training_data_client.dart';
import '../services/gesture_transform.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/tile_image_picker.dart';
import '../services/tile_assets.dart';

/// Screen for collecting single-tile training data.
/// Flow: Camera → Capture → Align → Select label → Send → Repeat
class TrainingDataScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const TrainingDataScreen({super.key, required this.cameras});

  @override
  State<TrainingDataScreen> createState() => _TrainingDataScreenState();
}

enum _TDPhase { camera, align, label }

class _TrainingDataScreenState extends State<TrainingDataScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final TrainingDataClient _client = TrainingDataClient();

  _TDPhase _phase = _TDPhase.camera;
  Uint8List? _capturedBytes;
  img.Image? _capturedImage;

  // Single source of truth for the display transform applied to the
  // captured photo during alignment (pan/zoom/rotate) — see
  // `services/gesture_transform.dart` for why this replaced separate
  // offset/scale/rotation fields (same fix already applied in
  // `scan_screen.dart`: a naive per-axis composition pivoted zoom on the
  // image center instead of the pinch point, and made post-rotation drags
  // feel reversed).
  Matrix4 _imageTransform = Matrix4.identity();
  Matrix4? _gestureStartTransform;
  Offset? _gestureStartFocalPoint;
  double _gestureStartScale = 1.0;

  // Result
  img.Image? _croppedTile;
  String? _selectedTileCode;
  int _sentCount = 0;
  // Uploads run detached from the capture flow (see `_send`) so the user
  // can keep photographing the next tile immediately instead of waiting
  // on each upload's network round-trip; this just tracks how many are
  // still in flight, for a small status indicator.
  int _pendingSends = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
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
      await _syncCaptureOrientation();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // The phone is held nearly flat, pointed down at the tile — the
  // accelerometer can't reliably tell landscape from portrait in that
  // position, so the camera plugin's own ambient-orientation fallback
  // (what both the live preview and the captured photo would otherwise
  // rely on) is unusable here, same reasoning as `scan_screen.dart`'s
  // capture flow. Since this screen (unlike the always-landscape scan
  // screen) now allows the user to hold it either way, a single fixed
  // lock doesn't work either — instead, re-derive the lock from Flutter's
  // own settled orientation (from `PlatformDispatcher`'s reported view
  // size, which only flips when the OS actually commits to a rotation,
  // not the raw jittery accelerometer) every time the device's reported
  // orientation changes, via `didChangeMetrics` below.
  DeviceOrientation _bestGuessOrientation() {
    final size =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    return size.width < size.height
        ? DeviceOrientation.portraitUp
        : DeviceOrientation.landscapeLeft;
  }

  Future<void> _syncCaptureOrientation() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.lockCaptureOrientation(_bestGuessOrientation());
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void didChangeMetrics() {
    _syncCaptureOrientation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      _imageTransform = Matrix4.identity();
    });
  }

  void _cropAndSelectLabel(
    Rect slotScreenRect,
    double baseLeft,
    double baseTop,
    double baseW,
    double baseH,
  ) {
    final image = _capturedImage!;
    final origin = Offset(baseLeft, baseTop);
    final origW = image.width.toDouble();
    final origH = image.height.toDouble();
    final inverse = Matrix4.inverted(_imageTransform);

    // Map a screen point back through the (pan/zoom/rotate) display
    // transform to a pixel coordinate in the original captured image —
    // same approach as `scan_screen.dart`'s `_classifyFromGrid`, applied to
    // a single fixed slot instead of 14.
    Offset toImagePixel(Offset screenPoint) {
      final content = MatrixUtils.transformPoint(inverse, screenPoint - origin);
      return Offset(content.dx * (origW / baseW), content.dy * (origH / baseH));
    }

    final tl = toImagePixel(slotScreenRect.topLeft);
    final tr = toImagePixel(slotScreenRect.topRight);
    final bl = toImagePixel(slotScreenRect.bottomLeft);
    final br = toImagePixel(slotScreenRect.bottomRight);

    final minX = [
      tl.dx,
      tr.dx,
      bl.dx,
      br.dx,
    ].reduce(math.min).round().clamp(0, image.width - 1);
    final minY = [
      tl.dy,
      tr.dy,
      bl.dy,
      br.dy,
    ].reduce(math.min).round().clamp(0, image.height - 1);
    final maxX = [
      tl.dx,
      tr.dx,
      bl.dx,
      br.dx,
    ].reduce(math.max).round().clamp(0, image.width - 1);
    final maxY = [
      tl.dy,
      tr.dy,
      bl.dy,
      br.dy,
    ].reduce(math.max).round().clamp(0, image.height - 1);
    final cropW = (maxX - minX).clamp(1, image.width - minX);
    final cropH = (maxY - minY).clamp(1, image.height - minY);

    setState(() {
      _croppedTile = img.copyCrop(
        image,
        x: minX,
        y: minY,
        width: cropW,
        height: cropH,
      );
      _selectedTileCode = null;
      _phase = _TDPhase.label;
    });
  }

  void _send() {
    if (_croppedTile == null || _selectedTileCode == null) return;
    // Capture this tile's data now, then immediately hand the screen back
    // to the camera for the next shot — the upload itself continues
    // independently in the background (`_uploadInBackground`), so the
    // user isn't blocked waiting on a network round-trip between tiles.
    final tileImage = _croppedTile!;
    final tileCode = _selectedTileCode!;
    setState(() {
      _phase = _TDPhase.camera;
      _capturedBytes = null;
      _capturedImage = null;
      _croppedTile = null;
      _selectedTileCode = null;
      _pendingSends++;
    });
    _uploadInBackground(tileImage, tileCode);
  }

  Future<void> _uploadInBackground(img.Image tileImage, String tileCode) async {
    try {
      await _client.uploadTile(tileImage: tileImage, tileCode: tileCode);
      if (mounted) {
        setState(() {
          _sentCount++;
          _pendingSends--;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('送信完了 ($_sentCount枚目: ${tileDisplayName(tileCode)})'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pendingSends--);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信エラー (${tileDisplayName(tileCode)}): $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _pendingSends > 0
              ? '学習データ作成 ($_sentCount枚送信済み・送信中$_pendingSends件)'
              : '学習データ作成 ($_sentCount枚送信済み)',
        ),
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
        // Centered rather than a direct Stack.expand child, so
        // CameraPreview's own internal AspectRatio determines its size
        // instead of being force-stretched to fill — matches
        // `scan_screen.dart`'s `_buildCameraPhase`.
        Center(child: CameraPreview(_controller!)),
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '牌1枚を撮影してください',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _capture,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlign() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;

        // Single tile slot: centered, reasonable size
        final slotW = viewW * 0.3;
        final slotH = slotW / 0.75;
        final slotRect = Rect.fromLTWH(
          (viewW - slotW) / 2,
          (viewH - slotH) / 2,
          slotW,
          slotH,
        );

        final imgW = _capturedImage!.width.toDouble();
        final imgH = _capturedImage!.height.toDouble();
        final imgAspect = imgW / imgH;
        late final double baseW, baseH;
        if (imgAspect > viewW / viewH) {
          baseW = viewW;
          baseH = viewW / imgAspect;
        } else {
          baseH = viewH;
          baseW = viewH * imgAspect;
        }
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

            // Overlay with single slot cutout
            ClipRect(
              child: CustomPaint(
                size: Size(viewW, viewH),
                painter: _SingleSlotPainter(slotRect: slotRect),
              ),
            ),

            // Gesture: drag/pinch/rotate the IMAGE, pivoting correctly around
            // the actual gesture focal point (see `gesture_transform.dart`).
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: (details) {
                  _gestureStartTransform = _imageTransform.clone();
                  _gestureStartFocalPoint = details.localFocalPoint - origin;
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

            // 90° button
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: () => setState(() {
                  _imageTransform = Matrix4.rotationZ(
                    math.pi / 2,
                  ).multiplied(_imageTransform);
                }),
                icon: const Icon(
                  Icons.rotate_right,
                  color: Colors.white70,
                  size: 28,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),

            // Bottom buttons
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black87,
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() {
                          _phase = _TDPhase.camera;
                          _capturedBytes = null;
                        }),
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
                        onPressed: () => _cropAndSelectLabel(
                          slotRect,
                          baseLeft,
                          baseTop,
                          baseW,
                          baseH,
                        ),
                        icon: const Icon(Icons.crop, size: 20),
                        label: const Text('切り出し'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
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
    );
  }

  Widget _buildLabel() {
    final jpgBytes = _croppedTile != null
        ? Uint8List.fromList(img.encodeJpg(_croppedTile!))
        : null;

    // Whole content scrolls: this screen is locked to landscape (short
    // screen height), and an un-scrollable fixed Column here previously
    // overflowed past the visible area — the tile keyboard and even the
    // send button could render below the screen with no way to reach them.
    // Also replaced the always-visible text `TileKeyboard` with a button
    // that opens `TileImagePicker` (a bottom sheet, already sized safely
    // for this exact landscape constraint), matching how tile selection
    // works everywhere else in the app now.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Cropped tile preview
          if (jpgBytes != null)
            Container(
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(jpgBytes, fit: BoxFit.contain),
              ),
            ),
          const SizedBox(height: 16),

          // Tap to open the image-based tile picker.
          GestureDetector(
            onTap: () async {
              final tile = await TileImagePicker.show(
                context,
                currentTile: _selectedTileCode,
              );
              if (tile != null) setState(() => _selectedTileCode = tile);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedTileCode != null
                      ? Colors.greenAccent
                      : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shows the tile's illustration alongside its name (not
                  // image-only, unlike most other tile displays in the app)
                  // — this screen labels training data, so misreading a
                  // similar-looking tile here is more costly than elsewhere.
                  if (_selectedTileCode != null) ...[
                    SizedBox(
                      width: 32,
                      height: 44,
                      child: TileGlyph(tileCode: _selectedTileCode!),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _selectedTileCode == null
                        ? '牌を選択してください'
                        : tileDisplayName(_selectedTileCode!),
                    style: TextStyle(
                      color: _selectedTileCode != null
                          ? Colors.greenAccent
                          : Colors.white54,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.touch_app, color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Send button
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() {
                    _phase = _TDPhase.align;
                    _selectedTileCode = null;
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('戻る'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _selectedTileCode != null ? _send : null,
                  icon: const Icon(Icons.send, size: 20),
                  label: const Text('送信'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedTileCode != null
                        ? Colors.orange.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
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
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawRect(slotRect, Paint()..blendMode = BlendMode.clear);
    canvas.drawRect(
      slotRect,
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SingleSlotPainter old) =>
      slotRect != old.slotRect;
}
