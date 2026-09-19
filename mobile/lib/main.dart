import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'screens/scan_screen.dart';
import 'screens/training_data_screen.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the whole app to landscape: every screen assumes the phone is
  // held sideways (the tile-row photography this app exists for is
  // inherently wide, not tall), so there's no portrait-shaped screen to
  // fall back to. This avoids depending on whatever rotation state the OS
  // happens to be in.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  // These used to run unguarded: an exception here (network hiccup, stale
  // Keychain state after a reinstall, etc.) meant runApp() was never
  // reached and the app showed nothing at all — indistinguishable from a
  // crash right at launch (FEZ-197). Neither failure should be fatal: the
  // scan flow itself doesn't need Firebase/auth, only the training-data
  // upload path does, and that path already has its own error handling.
  String? startupError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('main: Firebase.initializeApp failed: $e');
    startupError = 'Firebase初期化に失敗しました: $e';
  }
  try {
    await AuthService.initialize();
  } catch (e) {
    debugPrint('main: AuthService.initialize failed: $e');
    startupError ??= 'ログイン機能の初期化に失敗しました: $e';
  }

  try {
    cameras = await availableCameras();
  } catch (e) {
    cameras = [];
  }

  runApp(TsumoAIApp(startupError: startupError));
}

class TsumoAIApp extends StatefulWidget {
  final String? startupError;
  const TsumoAIApp({super.key, this.startupError});

  @override
  State<TsumoAIApp> createState() => _TsumoAIAppState();
}

class _TsumoAIAppState extends State<TsumoAIApp> {
  bool _autoClassify = false;
  String _roundWind = 'E';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TsumoAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        cameras: cameras,
        startupError: widget.startupError,
        autoClassify: _autoClassify,
        roundWind: _roundWind,
        onAutoClassifyChanged: (value) => setState(() => _autoClassify = value),
        onRoundWindChanged: (value) => setState(() => _roundWind = value),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final String? startupError;
  final bool autoClassify;
  final String roundWind;
  final ValueChanged<bool> onAutoClassifyChanged;
  final ValueChanged<String> onRoundWindChanged;

  const HomeScreen({
    super.key,
    required this.cameras,
    this.startupError,
    required this.autoClassify,
    required this.roundWind,
    required this.onAutoClassifyChanged,
    required this.onRoundWindChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('TsumoAI', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              if (startupError != null) ...[
                const SizedBox(height: 16),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Text(
                    startupError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildScanSettings(),
              const SizedBox(height: 24),
              _menuButton(context, Icons.camera_alt, '牌スキャン', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanScreen(
                      cameras: cameras,
                      autoClassify: autoClassify,
                      initialRoundWind: roundWind,
                      onRoundWindChanged: onRoundWindChanged,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              _menuButton(context, Icons.school, '学習データ作成（1枚）', () {
                _openTrainingData(context);
              }),
              const SizedBox(height: 32),
              StreamBuilder<User?>(
                stream: AuthService.authStateChanges(),
                initialData: AuthService.currentUser,
                builder: (context, snapshot) {
                  final user = snapshot.data;
                  if (user == null) {
                    return const Text(
                      'ログインしていません',
                      style: TextStyle(color: Colors.white54),
                    );
                  }

                  return Column(
                    children: [
                      Text(
                        user.email ?? 'Googleアカウントでログイン中',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _signOut(context),
                        icon: const Icon(Icons.logout),
                        label: const Text('ログアウト'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanSettings() {
    const windLabels = {'E': '東', 'S': '南', 'W': '西', 'N': '北'};
    return Container(
      width: 520,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text(
            '場風',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            segments: [
              for (final entry in windLabels.entries)
                ButtonSegment<String>(
                  value: entry.key,
                  label: Text(entry.value),
                ),
            ],
            selected: {roundWind},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (selection) {
              onRoundWindChanged(selection.single);
            },
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Text(
              '撮影後に自動識別',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Switch(
            value: autoClassify,
            onChanged: onAutoClassifyChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _openTrainingData(BuildContext context) async {
    try {
      await AuthService.ensureSignedIn();
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingDataScreen(cameras: cameras)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Googleログインが必要です: $error')),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService.signOut();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログアウトしました')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ログアウトに失敗しました: $error')),
      );
    }
  }

  Widget _menuButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: 280,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 24),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
