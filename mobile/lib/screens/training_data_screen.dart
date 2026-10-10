import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/photo_input.dart';
import '../services/photo_import.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/training_data_client.dart';
import '../services/gesture_transform.dart';
import '../widgets/screen_header.dart';
import '../widgets/tile_glyph.dart';
import '../widgets/tile_image_picker.dart';
import '../services/tile_assets.dart';
import '../services/camera_lifecycle.dart';

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
  late final CameraLifecycle _cameraLifecycle;
  String? _cameraError;
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
    _cameraLifecycle = CameraLifecycle(
      open: () async {
        if (_cameraError == null) await _initCamera();
      },
      close: _releaseCamera,
      onError: (error, stack) =>
          debugPrint('Training camera lifecycle error: $error'),
    );
    if (!kIsWeb) unawaited(_cameraLifecycle.start());
  }

  Future<void> _initCamera() async {
    if (!mounted || !_cameraLifecycle.isActive) return;
    if (widget.cameras.isEmpty) {
      setState(() => _cameraError = '利用できるカメラが見つかりませんでした');
      return;
    }
    setState(() => _cameraError = null);
    final controller = CameraController(
      widget.cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      ),
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || !_cameraLifecycle.isActive) return;
      await _syncCaptureOrientation();
      if (mounted) setState(() {});
    } catch (error) {
      await controller.dispose();
      _controller = null;
      if (mounted) {
        setState(
          () => _cameraError = 'カメラを開始できませんでした。端末の設定でカメラへのアクセスを確認してください。',
        );
      }
    }
  }

  Future<void> _releaseCamera() async {
    final controller = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await controller?.dispose();
  }

  Future<void> _retryCamera() {
    setState(() => _cameraError = null);
    return _cameraLifecycle.retry();
  }

  Future<void> _syncCaptureOrientation() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
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
    unawaited(_cameraLifecycle.dispose());
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        !_cameraLifecycle.isActive) {
      return;
    }
    try {
      final xFile = await controller.takePicture();
      final bytes = await xFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted || decoded == null) return;

      setState(() {
        _capturedBytes = Uint8List.fromList(
          img.encodeJpg(decoded, quality: 90),
        );
        _capturedImage = decoded;
        _phase = _TDPhase.align;
        _imageTransform = Matrix4.identity();
      });
    } catch (error) {
      if (!mounted || !_cameraLifecycle.isActive) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('撮影できませんでした。もう一度お試しください。')));
    }
  }

  bool _isImporting = false;
  Future<void> _pickPhoto(ImageSource source) async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
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
      setState(() {
        _capturedBytes = prepared.bytes;
        _capturedImage = prepared.image;
        _phase = _TDPhase.align;
        _imageTransform = Matrix4.identity();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('画像読込エラー: $error')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
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

  AppColors get _colors => context.appColors;

  ColorScheme get _scheme => Theme.of(context).colorScheme;
  TextTheme get _text => Theme.of(context).textTheme;

  @override
  Widget build(BuildContext context) {
    // Light screen with the photo in a deep-green frame (training-capture
    // mockup): step 1 撮影 covers capture and alignment, step 2 正解確認.
    final subtitle = switch (_phase) {
      _TDPhase.camera => '牌を1枚撮影',
      _TDPhase.align => '枠に合わせて切り出し',
      _TDPhase.label => '正解の牌を選択',
    };
    final sent = _pendingSends > 0
        ? '$_sentCount枚送信済み・送信中$_pendingSends件'
        : '$_sentCount枚送信済み';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '学習データ作成',
              subtitle: '$subtitle・$sent',
              trailing: const HeaderHomeButton(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.l,
                AppSpacing.m,
                AppSpacing.l,
                AppSpacing.m,
              ),
              child: _stepPills(),
            ),
            Expanded(
              child: switch (_phase) {
                _TDPhase.camera => _buildCamera(),
                _TDPhase.align => _buildAlign(),
                _TDPhase.label => _buildLabel(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepPills() {
    Widget pill(int number, String label, bool active) => Expanded(
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _scheme.primary : _scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '$number  $label',
          style: _text.labelMedium?.copyWith(
            color: active ? _scheme.onPrimary : _scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    final labeling = _phase == _TDPhase.label;
    return Row(
      children: [
        pill(1, '撮影', !labeling),
        SizedBox(
          width: AppSpacing.xl,
          child: Divider(color: _scheme.outlineVariant),
        ),
        pill(2, '正解確認', labeling),
      ],
    );
  }

  /// Deep-green rounded frame holding the camera preview or photo.
  Widget _photoFrame(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.hero),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _colors.photoGradient,
          ),
        ),
        child: child,
      ),
    ),
  );

  Widget _buildCamera() {
    if (kIsWeb) return PhotoInput(busy: _isImporting, onPick: _pickPhoto);
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_cameraError!, textAlign: TextAlign.center),
              if (widget.cameras.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.l),
                FilledButton.icon(
                  onPressed: _retryCamera,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final ready = _controller != null && _controller!.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: _photoFrame(
            Stack(
              fit: StackFit.expand,
              children: [
                if (!ready)
                  Center(
                    child: CircularProgressIndicator(color: _colors.onDark),
                  )
                else
                  // Centered so CameraPreview keeps its own aspect ratio.
                  Center(child: CameraPreview(_controller!)),
                IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.38,
                      child: AspectRatio(
                        aspectRatio: 0.72,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _colors.cameraGuide,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.l,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.m,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _colors.cameraScrim,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '牌を中央に置いてください',
                        style: _text.labelMedium?.copyWith(
                          color: _colors.cameraOnSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.m,
            AppSpacing.l,
            AppSpacing.l,
          ),
          child: Column(
            children: [
              Text(
                '学習に使う牌を1枚だけ、正面から大きく写します。',
                textAlign: TextAlign.center,
                style: _text.bodySmall?.copyWith(
                  color: _scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              Semantics(
                button: true,
                label: '撮影',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: ready ? _capture : null,
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _scheme.primary, width: 3),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ready
                            ? _scheme.primary
                            : _scheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('撮影', style: _text.labelMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAlign() {
    // Geometry of the last layout, read by the buttons below the frame.
    late Rect slotRect;
    late double baseLeft, baseTop, baseW, baseH;
    final editor = LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;

        // Single tile slot: centered, reasonable size
        final slotW = viewW * 0.3;
        final slotH = slotW / 0.75;
        slotRect = Rect.fromLTWH(
          (viewW - slotW) / 2,
          (viewH - slotH) / 2,
          slotW,
          slotH,
        );

        final imgW = _capturedImage!.width.toDouble();
        final imgH = _capturedImage!.height.toDouble();
        final imgAspect = imgW / imgH;
        if (imgAspect > viewW / viewH) {
          baseW = viewW;
          baseH = viewW / imgAspect;
        } else {
          baseH = viewH;
          baseW = viewH * imgAspect;
        }
        baseLeft = (viewW - baseW) / 2;
        baseTop = (viewH - baseH) / 2;
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
                icon: Icon(
                  Icons.rotate_right,
                  color: _colors.cameraOnSurfaceVariant,
                  size: 28,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: _colors.cameraScrim,
                ),
              ),
            ),
          ],
        );
      },
    );
    return Column(
      children: [
        Expanded(child: _photoFrame(editor)),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _phase = _TDPhase.camera;
                    _capturedBytes = null;
                  }),
                  child: const Text('撮り直す'),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _cropAndSelectLabel(
                    slotRect,
                    baseLeft,
                    baseTop,
                    baseW,
                    baseH,
                  ),
                  icon: const Icon(Icons.crop, size: 20),
                  label: const Text('切り出し'),
                ),
              ),
            ],
          ),
        ),
      ],
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
                color: _colors.cameraBackground,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
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
                color: _scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: _selectedTileCode != null
                      ? _scheme.primary
                      : _scheme.outlineVariant,
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _selectedTileCode != null
                          ? _scheme.primary
                          : _scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.touch_app,
                    color: _scheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Send button
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _phase = _TDPhase.align;
                    _selectedTileCode = null;
                  }),
                  child: const Text('戻る'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _selectedTileCode != null ? _send : null,
                  icon: const Icon(Icons.send, size: 20),
                  label: const Text('送信'),
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
      Paint()..color = AppColors.light.cameraScrim,
    );
    canvas.drawRect(slotRect, Paint()..blendMode = BlendMode.clear);
    canvas.drawRect(
      slotRect,
      Paint()
        ..color = AppColors.light.detectionBox
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SingleSlotPainter old) =>
      slotRect != old.slotRect;
}
