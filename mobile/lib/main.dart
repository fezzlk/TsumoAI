import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'models/match_state.dart';
import 'models/scan_purpose.dart';
import 'models/score_request.dart';
import 'screens/match_home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/training_data_screen.dart';
import 'services/app_preferences.dart';
import 'services/auth_service.dart';
import 'services/question_template_service.dart';
import 'services/rule_settings_service.dart';

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
  final initialRuleSettings = await RuleSettingsService().synchronize();
  unawaited(QuestionTemplateService().synchronize());
  runApp(
    TsumoAIApp(
      startupError: startupError,
      initialShowTrainingDataActions: showTrainingDataActions,
      initialRuleSettings: initialRuleSettings,
    ),
  );
}

class TsumoAIApp extends StatefulWidget {
  const TsumoAIApp({
    super.key,
    this.startupError,
    this.initialShowTrainingDataActions = false,
    this.initialRuleSettings = const MahjongRuleSettings(),
  });

  final String? startupError;
  final bool initialShowTrainingDataActions;
  final MahjongRuleSettings initialRuleSettings;

  @override
  State<TsumoAIApp> createState() => _TsumoAIAppState();
}

class _TsumoAIAppState extends State<TsumoAIApp> {
  bool _autoClassify = true;
  bool _showTrainingDataActions = false;
  String _roundWind = 'E';
  MatchState _matchState = MatchState();
  bool _matchActive = false;
  late MahjongRuleSettings _ruleSettings;
  final RuleSettingsService _ruleSettingsService = RuleSettingsService();
  final QuestionTemplateService _questionTemplateService =
      QuestionTemplateService();

  @override
  void initState() {
    super.initState();
    _showTrainingDataActions = widget.initialShowTrainingDataActions;
    _ruleSettings = widget.initialRuleSettings;
  }

  void _setShowTrainingDataActions(bool value) {
    setState(() => _showTrainingDataActions = value);
    unawaited(AppPreferences.setShowTrainingDataActions(value));
  }

  void _setRuleSettings(MahjongRuleSettings value) {
    setState(() => _ruleSettings = value);
    unawaited(_ruleSettingsService.save(value));
  }

  Future<void> _synchronizeRuleSettings() async {
    final results = await Future.wait([
      _ruleSettingsService.synchronize(),
      _questionTemplateService.synchronize(),
    ]);
    final value = results.first as MahjongRuleSettings;
    if (mounted) setState(() => _ruleSettings = value);
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
        ruleSettings: _ruleSettings,
        matchState: _matchState,
        matchActive: _matchActive,
        onAutoClassifyChanged: (value) => setState(() => _autoClassify = value),
        onRoundWindChanged: (value) => setState(() => _roundWind = value),
        onShowTrainingDataActionsChanged: _setShowTrainingDataActions,
        onRuleSettingsChanged: _setRuleSettings,
        onAuthenticationChanged: _synchronizeRuleSettings,
        onMatchStarted: () => setState(() => _matchActive = true),
        onMatchReturned: () => setState(() {}),
        onMatchEnded: () => setState(() {
          _matchActive = false;
          _matchState = MatchState();
        }),
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
    required this.ruleSettings,
    required this.matchState,
    required this.matchActive,
    required this.onAutoClassifyChanged,
    required this.onRoundWindChanged,
    required this.onShowTrainingDataActionsChanged,
    required this.onRuleSettingsChanged,
    required this.onAuthenticationChanged,
    required this.onMatchStarted,
    required this.onMatchReturned,
    required this.onMatchEnded,
  });

  final List<CameraDescription> cameras;
  final String? startupError;
  final bool autoClassify;
  final String roundWind;
  final bool showTrainingDataActions;
  final MahjongRuleSettings ruleSettings;
  final MatchState matchState;
  final bool matchActive;
  final ValueChanged<bool> onAutoClassifyChanged;
  final ValueChanged<String> onRoundWindChanged;
  final ValueChanged<bool> onShowTrainingDataActionsChanged;
  final ValueChanged<MahjongRuleSettings> onRuleSettingsChanged;
  final Future<void> Function() onAuthenticationChanged;
  final VoidCallback onMatchStarted;
  final VoidCallback onMatchReturned;
  final VoidCallback onMatchEnded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            if (startupError != null) ...[
              const SizedBox(height: 12),
              _buildStartupError(),
            ],
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
                    subtitle: '待ち牌・有効牌',
                    purpose: ScanPurpose.wait,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _purposeCard(
                    context,
                    icon: Icons.swap_horiz,
                    title: '何切る',
                    subtitle: '切る牌の候補',
                    purpose: ScanPurpose.discard,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _purposeCard(
                    context,
                    icon: Icons.call_split,
                    title: '鳴き判断',
                    subtitle: '鳴ける牌と判断',
                    purpose: ScanPurpose.callAdvice,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 94),
              child: ElevatedButton(
                onPressed: () => _openMatch(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        matchActive
                            ? '対局を再開'
                            : '実際の対局進行に合わせて点数計算を行う',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        matchActive
                            ? '${matchState.current.roundLabel}から続ける'
                            : '点数計算できる人がいない場合に、1半荘分の点数計算をサポート',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildTrainingAction(context),
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

  Widget _buildHeader(BuildContext context) => StreamBuilder<User?>(
    stream: AuthService.authStateChanges(),
    initialData: AuthService.currentUser,
    builder: (context, snapshot) {
      final user = snapshot.data;
      return Row(
        children: [
          const Expanded(
            child: Text(
              'TsumoAI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (user == null)
            TextButton(
              onPressed: () => _signIn(context),
              child: const Text('ログイン'),
            )
          else
            IconButton(
              onPressed: () => _showAccountMenu(context, user),
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'アカウント',
            ),
          IconButton(
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
          ),
        ],
      );
    },
  );

  Widget _buildTrainingAction(BuildContext context) {
    if (!showTrainingDataActions) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: AuthService.isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SizedBox(
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
        );
      },
    );
  }

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

  Future<void> _openScan(BuildContext context, ScanPurpose purpose) async {
    final showDeveloperActions =
        showTrainingDataActions && await AuthService.isAdmin();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          cameras: cameras,
          autoClassify: autoClassify,
          initialRoundWind: roundWind,
          onRoundWindChanged: onRoundWindChanged,
          purpose: purpose,
          showTrainingDataActions: showDeveloperActions,
          ruleSettings: ruleSettings,
        ),
      ),
    );
  }

  Future<void> _openMatch(BuildContext context) async {
    final showDeveloperActions =
        showTrainingDataActions && await AuthService.isAdmin();
    if (!context.mounted) return;
    onMatchStarted();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchHomeScreen(
          cameras: cameras,
          autoClassify: autoClassify,
          showTrainingDataActions: showDeveloperActions,
          ruleSettings: ruleSettings,
          matchState: matchState,
          onMatchEnded: onMatchEnded,
        ),
      ),
    );
    onMatchReturned();
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
          ruleSettings: ruleSettings,
          onRuleSettingsChanged: onRuleSettingsChanged,
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    try {
      await AuthService.ensureSignedIn();
      await onAuthenticationChanged();
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
      await onAuthenticationChanged();
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

  Future<void> _showAccountMenu(BuildContext context, User user) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('アカウント'),
        content: Text(user.email ?? 'Googleアカウントでログイン中'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(dialogContext);
              _signOut(context);
            },
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
  }
}
