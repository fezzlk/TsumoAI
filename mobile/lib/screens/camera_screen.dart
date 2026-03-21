import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../services/recognition_service.dart';
import '../services/tile_detector.dart';
import '../models/score_request.dart';
import '../widgets/debug_panel.dart';
import '../widgets/result_overlay.dart';
import '../widgets/tile_overlay.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCapturing = false;

  // Auto-detection state
  bool _autoDetectEnabled = true;
  int _detectedTileCount = 0;
  bool _isAnalyzing = false;
  Timer? _analysisTimer;
  CameraImage? _latestFrame;

  // Debug mode
  bool _debugMode = false;
  TileDetectorParams _detectorParams = const TileDetectorParams();
  TileDetectorResult? _lastDetectorResult;
  TileDetectorResult? _lastHResult;
  TileDetectorResult? _lastVResult;
  int _overlayRotation = 3; // 0=0°, 1=90°CW, 2=180°, 3=90°CCW

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {});
        if (_autoDetectEnabled) _startAutoDetection();
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  bool _isStreamActive = false;

  Future<void> _startAutoDetection() async {
    await _stopAutoDetection();
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      _controller!.startImageStream(_onCameraFrame);
      _isStreamActive = true;
    } catch (_) {
      return;
    }
    _analysisTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _triggerAnalysis(),
    );
  }

  Future<void> _stopAutoDetection() async {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _latestFrame = null;
    if (_isStreamActive) {
      try {
        await _controller?.stopImageStream();
      } catch (_) {}
      _isStreamActive = false;
    }
  }

  void _onCameraFrame(CameraImage image) {
    _latestFrame = image;
  }

  Future<void> _triggerAnalysis() async {
    if (_isAnalyzing || _isCapturing || !_autoDetectEnabled) return;
    final frame = _latestFrame;
    if (frame == null) return;

    _isAnalyzing = true;
    try {
      if (_debugMode) {
        // In debug mode, get both axis results for comparison
        final both = await TileDetector.detectBoth(frame, _detectorParams);
        if (!mounted) return;

        setState(() {
          _detectedTileCount = both.best.tileCount;
          _lastDetectorResult = both.best;
          _lastHResult = both.h;
          _lastVResult = both.v;
        });
      } else {
        final result = await TileDetector.detect(frame, _detectorParams);
        if (!mounted) return;

        setState(() {
          _detectedTileCount = result.tileCount;
          _lastDetectorResult = result;
        });
      }
    } catch (e) {
      debugPrint('Tile detection error: $e');
    } finally {
      _isAnalyzing = false;
    }
  }

  Future<void> _toggleAutoDetect() async {
    setState(() {
      _autoDetectEnabled = !_autoDetectEnabled;
      _detectedTileCount = 0;
      _lastDetectorResult = null;
    });

    final service = context.read<RecognitionService>();
    if (_autoDetectEnabled && service.state == ServiceState.idle) {
      await _startAutoDetection();
    } else {
      await _stopAutoDetection();
    }
  }

  void _toggleDebugMode() {
    setState(() => _debugMode = !_debugMode);
    if (_debugMode && _autoDetectEnabled) {
      final service = context.read<RecognitionService>();
      if (service.state == ServiceState.idle && _analysisTimer == null) {
        _startAutoDetection();
      }
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      // Ensure stream is fully stopped before taking picture.
      // Native camera needs time to fully release the stream before capture.
      await _stopAutoDetection();
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

      final xFile = await _controller!.takePicture();
      final file = File(xFile.path);

      if (!mounted) return;

      final service = context.read<RecognitionService>();
      final ctx = ContextInput(
        winType: 'tsumo',
        isDealer: false,
        roundWind: 'E',
        seatWind: 'S',
        riichi: false,
        ippatsu: false,
        haitei: false,
        houtei: false,
        rinshan: false,
        chankan: false,
      );

      await service.processImage(file, ctx);
    } catch (e) {
      if (mounted) {
        // Show error on screen instead of crashing
        final service = context.read<RecognitionService>();
        if (service.state != ServiceState.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('エラー: $e'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('TsumoAI'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          // Debug mode toggle
          IconButton(
            icon: Icon(
              Icons.bug_report,
              color: _debugMode ? Colors.amberAccent : Colors.white54,
            ),
            tooltip: 'デバッグ',
            onPressed: _toggleDebugMode,
          ),
          // Overlay rotation toggle (debug)
          if (_debugMode)
            IconButton(
              icon: const Icon(Icons.rotate_right, size: 20),
              tooltip: '回転: ${const ['0°', '90°CW', '180°', '90°CCW'][_overlayRotation % 4]}',
              onPressed: () => setState(() => _overlayRotation = (_overlayRotation + 1) % 4),
            ),
          // Auto-detect toggle
          IconButton(
            icon: Icon(
              _autoDetectEnabled
                  ? Icons.auto_awesome
                  : Icons.auto_awesome_outlined,
              color: _autoDetectEnabled ? Colors.amberAccent : Colors.white54,
            ),
            tooltip: '自動検出',
            onPressed: _toggleAutoDetect,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: Text(
          'カメラを初期化中...',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return Consumer<RecognitionService>(
      builder: (context, service, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview
            CameraPreview(_controller!),

            // Tile detection overlay (bounding boxes)
            if (_autoDetectEnabled &&
                _lastDetectorResult != null &&
                service.state == ServiceState.idle)
              TileOverlay(
                result: _lastDetectorResult!,
                rotationIndex: _overlayRotation,
              ),

            // Scan region guides (debug mode)
            if (_debugMode && _autoDetectEnabled)
              _buildScanRegionOverlay(),

            // Auto-detection tile count indicator
            if (_autoDetectEnabled && service.state == ServiceState.idle)
              _buildTileCountIndicator(),

            // Status indicator
            if (service.state == ServiceState.recognizing)
              _buildStatusBanner('牌を認識中...', Colors.blue),
            if (service.state == ServiceState.scoring)
              _buildStatusBanner('点数計算中...', Colors.orange),
            if (service.state == ServiceState.error)
              _buildStatusBanner(
                service.errorMessage ?? 'エラー',
                Colors.red,
              ),

            // Result overlay
            if (service.recognition != null)
              ResultOverlay(
                recognition: service.recognition!,
                score: service.score,
              ),

            // Capture button (pushed up when debug panel is open)
            Positioned(
              bottom: _debugMode
                  ? 380
                  : service.recognition != null
                      ? 200
                      : 40,
              left: 0,
              right: 0,
              child: Center(child: _buildCaptureButton(service)),
            ),

            // Debug panel
            if (_debugMode)
              DebugPanel(
                params: _detectorParams,
                lastResult: _lastDetectorResult,
                hResult: _lastHResult,
                vResult: _lastVResult,
                onParamsChanged: (newParams) {
                  setState(() => _detectorParams = newParams);
                },
              ),
          ],
        );
      },
    );
  }

  /// Shows horizontal guide lines indicating the scan region.
  Widget _buildScanRegionOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = constraints.maxHeight * _detectorParams.scanRegionTop;
        final bottom = constraints.maxHeight * _detectorParams.scanRegionBottom;

        return Stack(
          children: [
            // Top line
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: Colors.amberAccent.withValues(alpha: 0.6),
              ),
            ),
            // Bottom line
            Positioned(
              top: bottom,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: Colors.amberAccent.withValues(alpha: 0.6),
              ),
            ),
            // Label
            Positioned(
              top: top - 16,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.black54,
                child: const Text(
                  'スキャン範囲',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTileCountIndicator() {
    final isReady = _detectedTileCount == TileDetector.targetTileCount;
    final color = isReady ? Colors.white : Colors.white70;

    return Positioned(
      top: 8,
      right: 12,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (isReady ? Colors.green : Colors.black54)
              .withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReady ? Icons.check_circle : Icons.search,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              '$_detectedTileCount / ${TileDetector.targetTileCount} 牌',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: isReady ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String text, Color color) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: color.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButton(RecognitionService service) {
    final isProcessing =
        service.state == ServiceState.recognizing ||
        service.state == ServiceState.scoring;

    if (service.state == ServiceState.done ||
        service.state == ServiceState.error) {
      return FloatingActionButton.extended(
        onPressed: () {
          service.reset();
          if (_autoDetectEnabled) _startAutoDetection();
        },
        backgroundColor: Colors.white,
        icon: const Icon(Icons.refresh, color: Colors.black87),
        label: const Text('もう一度', style: TextStyle(color: Colors.black87)),
      );
    }

    return GestureDetector(
      onTap: isProcessing
          ? null
          : () async {
              await _stopAutoDetection();
              await _captureAndProcess();
            },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: isProcessing
              ? Colors.grey
              : Colors.white.withValues(alpha: 0.3),
        ),
        child: isProcessing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.camera_alt, color: Colors.white, size: 32),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final urlController = TextEditingController(
      text: AppConfig.apiBaseUrl,
    );
    var selectedEnv = AppConfig.environment;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('設定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<Environment>(
                segments: const [
                  ButtonSegment(
                    value: Environment.production,
                    label: Text('本番'),
                    icon: Icon(Icons.cloud),
                  ),
                  ButtonSegment(
                    value: Environment.local,
                    label: Text('ローカル'),
                    icon: Icon(Icons.computer),
                  ),
                ],
                selected: {selectedEnv},
                onSelectionChanged: (set) {
                  setDialogState(() {
                    selectedEnv = set.first;
                    if (selectedEnv == Environment.production) {
                      urlController.text = 'https://tsumoai.fezzlk.com';
                    } else {
                      urlController.text = 'http://localhost:8000';
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'https://tsumoai.fezzlk.com',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '現在: ${AppConfig.apiBaseUrl}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                AppConfig.setEnvironment(selectedEnv);
                final customUrl = urlController.text.trim();
                if (customUrl.isNotEmpty) {
                  final defaultUrl = selectedEnv == Environment.production
                      ? 'https://tsumoai.fezzlk.com'
                      : 'http://localhost:8000';
                  if (customUrl != defaultUrl) {
                    AppConfig.setApiBaseUrl(customUrl);
                  }
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('API: ${AppConfig.apiBaseUrl}')),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
