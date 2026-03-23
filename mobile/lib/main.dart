import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/scan_screen.dart';
import 'screens/training_data_screen.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    cameras = [];
  }

  runApp(const TsumoAIApp());
}

class TsumoAIApp extends StatelessWidget {
  const TsumoAIApp({super.key});

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
      home: HomeScreen(cameras: cameras),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

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
              const SizedBox(height: 40),
              _menuButton(context, Icons.camera_alt, '牌スキャン（14枚）', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ScanScreen(cameras: cameras)));
              }),
              const SizedBox(height: 16),
              _menuButton(context, Icons.school, '学習データ作成（1枚）', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingDataScreen(cameras: cameras)));
              }),
            ],
          ),
        ),
      ),
    );
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
