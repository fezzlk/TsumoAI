import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'models/scan_purpose.dart';
import 'screens/match_home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/training_data_screen.dart';
import 'services/app_preferences.dart';
import 'services/auth_service.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  String? startupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('main: Firebase.initializeApp failed: $error');
    startupError = 'Firebase初期化に失敗しました: $error';
  }
  try {
    await AuthService.initialize();
  } catch (error) {
    debugPrint('main: AuthService.initialize failed: $error');
    startupError ??= 'ログイン機能の初期化に失敗しました: $error';
  }

  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = [];
  }

  final showTrainingDataActions =
      await AppPreferences.showTrainingDataActions();
  runApp(
    TsumoAIApp(
      startupError: startupError,
      initialShowTrainingDataActions: showTrainingDataActions,
    ),
  );
}

class TsumoAIApp extends StatefulWidget {
  const TsumoAIApp({
    super.key,
    this.startupError,
    this.initialShowTrainingDataActions = false,
  });

  final String? startupError;
  final bool initialShowTrainingDataActions;

  @override
  State<TsumoAIApp> createState() => _TsumoAIAppState();
}

class _TsumoAIAppState extends State<TsumoAIApp> {
  bool _autoClassify = false;
  bool _showTrainingDataActions = false;
  String _roundWind = 'E';

  @override
  void initState() {
    super.initState();
    _showTrainingDataActions = widget.initialShowTrainingDataActions;
  }

  void _setShowTrainingDataActions(bool value) {
    setState(() => _showTrainingDataActions = value);
    unawaited(AppPreferences.setShowTrainingDataActions(value));
  }

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
        showTrainingDataActions: _showTrainingDataActions,
        onAutoClassifyChanged: (value) => setState(() => _autoClassify = value),
        onRoundWindChanged: (value) => setState(() => _roundWind = value),
        onShowTrainingDataActionsChanged: _setShowTrainingDataActions,
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.cameras,
    this.startupError,
    required this.autoClassify,
    required this.roundWind,
    required this.showTrainingDataActions,
    required this.onAutoClassifyChanged,
    required this.onRoundWindChanged,
    required this.onShowTrainingDataActionsChanged,
  });

  final List<CameraDescription> cameras;
  final String? startupError;
  final bool autoClassify;
  final String roundWind;
  final bool showTrainingDataActions;
  final ValueChanged<bool> onAutoClassifyChanged;
  final ValueChanged<String> onRoundWindChanged;
  final ValueChanged<bool> onShowTrainingDataActionsChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            const Text(
              'TsumoAI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '実卓の点数・待ちを牌から確認',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            _buildAccountCard(context),
            if (startupError != null) ...[
              const SizedBox(height: 12),
              _buildStartupError(),
            ],
            const SizedBox(height: 24),
            const Text(
              'すぐ確認',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _purposeCard(
                    context,
                    icon: Icons.calculate_outlined,
                    title: '点数計算',
                    subtitle: '役・翻・符・支払い',
                    purpose: ScanPurpose.score,
                    emphasized: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _purposeCard(
                    context,
                    icon: Icons.center_focus_strong,
                    title: '待ち確認',
                    subtitle: '待ち牌・残り枚数',
                    purpose: ScanPurpose.wait,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: OutlinedButton.icon(
                onPressed: () => _showAiPurposePicker(context),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('AI相談　何を切る？・鳴くべき？'),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchHomeScreen(
                      cameras: cameras,
                      autoClassify: autoClassify,
                      showTrainingDataActions: showTrainingDataActions,
                    ),
                  ),
                ),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('対局を始める'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _showComingSoon(context, '利用履歴'),
                icon: const Icon(Icons.history),
                label: const Text('利用履歴'),
              ),
            ),
            if (showTrainingDataActions) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrainingDataScreen(cameras: cameras),
                    ),
                  ),
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('学習用の牌を1枚撮影'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _showComingSoon(context, '使い方'),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('使い方'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _openSettings(context),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('設定・規約'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartupError() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.redAccent),
    ),
    child: Text(
      startupError!,
      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
    ),
  );

  Widget _buildAccountCard(BuildContext context) => StreamBuilder<User?>(
    stream: AuthService.authStateChanges(),
    initialData: AuthService.currentUser,
    builder: (context, snapshot) {
      final user = snapshot.data;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_circle_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                user?.email ?? 'ログインしていません',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: user == null
                  ? () => _signIn(context)
                  : () => _signOut(context),
              child: Text(user == null ? 'ログイン' : 'ログアウト'),
            ),
          ],
        ),
      );
    },
  );

  Widget _purposeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required ScanPurpose purpose,
    bool emphasized = false,
  }) => SizedBox(
    height: 104,
    child: emphasized
        ? ElevatedButton(
            onPressed: () => _openScan(context, purpose),
            child: _purposeCardContent(icon, title, subtitle),
          )
        : OutlinedButton(
            onPressed: () => _openScan(context, purpose),
            child: _purposeCardContent(icon, title, subtitle),
          ),
  );

  Widget _purposeCardContent(IconData icon, String title, String subtitle) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      );

  void _openScan(BuildContext context, ScanPurpose purpose) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          cameras: cameras,
          autoClassify: autoClassify,
          initialRoundWind: roundWind,
          onRoundWindChanged: onRoundWindChanged,
          purpose: purpose,
          showTrainingDataActions: showTrainingDataActions,
        ),
      ),
    );
  }

  Future<void> _showAiPurposePicker(BuildContext context) async {
    final purpose = await showModalBottomSheet<ScanPurpose>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '何を相談しますか？',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('何を切る？'),
                subtitle: const Text('14枚を初期値にして撮影'),
                onTap: () => Navigator.pop(context, ScanPurpose.discard),
              ),
              ListTile(
                leading: const Icon(Icons.call_split),
                title: const Text('鳴くべき？'),
                subtitle: const Text('13枚を初期値にして撮影'),
                onTap: () => Navigator.pop(context, ScanPurpose.callAdvice),
              ),
            ],
          ),
        ),
      ),
    );
    if (purpose != null && context.mounted) _openScan(context, purpose);
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          autoClassify: autoClassify,
          onAutoClassifyChanged: onAutoClassifyChanged,
          showTrainingDataActions: showTrainingDataActions,
          onShowTrainingDataActionsChanged: onShowTrainingDataActionsChanged,
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    try {
      await AuthService.ensureSignedIn();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログインに失敗しました: $error')));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService.signOut();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ログアウトしました')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログアウトに失敗しました: $error')));
    }
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$featureは次の実装バッチで追加します')));
  }
}
