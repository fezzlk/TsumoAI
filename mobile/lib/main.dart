import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'models/match_state.dart';
import 'models/scan_purpose.dart';
import 'models/score_request.dart';
import 'screens/history_screen.dart';
import 'screens/match_home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/training_data_screen.dart';
import 'services/app_preferences.dart';
import 'services/auth_service.dart';
import 'services/question_template_service.dart';
import 'services/rule_settings_service.dart';
import 'services/official_ai_chat_template_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/home_cards.dart';
import 'widgets/screen_header.dart';
import 'widgets/section_list.dart';
import 'widgets/status_banner.dart';

List<CameraDescription> cameras = const [];

const _startupSyncBudget = Duration(seconds: 2);

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
    if (!kIsWeb) cameras = await availableCameras();
  } catch (_) {
    cameras = [];
  }

  final showTrainingDataActions =
      await AppPreferences.showTrainingDataActions();
  // Startup must not wait on the network: on a slow connection, start with
  // the device copy and let the synchronization finish in the background.
  final ruleSettingsService = RuleSettingsService();
  final initialRuleSettings = await ruleSettingsService.synchronize().timeout(
    _startupSyncBudget,
    onTimeout: ruleSettingsService.loadLocal,
  );
  unawaited(QuestionTemplateService().synchronize());
  unawaited(OfficialAIChatTemplateService().load());
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
      theme: AppTheme.light(),
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
    final colors = context.appColors;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.s,
            AppSpacing.l,
            AppSpacing.xl,
          ),
          children: [
            _buildHeader(context),
            if (startupError != null) ...[
              const SizedBox(height: AppSpacing.s),
              _buildStartupError(),
            ],
            const SizedBox(height: AppSpacing.s),
            _featureRow([
              FeatureCard(
                colors: colors.score,
                icon: Icons.calculate_outlined,
                title: '点数計算',
                subtitle: '役・翻・符・支払い',
                onTap: () => _openScan(context, ScanPurpose.score),
              ),
              FeatureCard(
                colors: colors.wait,
                icon: Icons.hourglass_bottom,
                title: '待ち確認',
                subtitle: '待ち牌を確認',
                onTap: () => _openScan(context, ScanPurpose.wait),
              ),
            ]),
            const SizedBox(height: 10),
            _featureRow([
              FeatureCard(
                colors: colors.discard,
                icon: Icons.swap_horiz,
                title: '何切る',
                subtitle: '打牌候補・受け入れ',
                onTap: () => _openScan(context, ScanPurpose.discard),
              ),
              FeatureCard(
                colors: colors.call,
                icon: Icons.call_split,
                title: '鳴き判断',
                subtitle: '候補牌・おすすめ度',
                onTap: () => _openScan(context, ScanPurpose.callAdvice),
              ),
            ]),
            const SizedBox(height: AppSpacing.m),
            SessionCard(
              playing: matchActive,
              eyebrow: matchActive
                  ? '対局中 · ${matchState.current.roundLabel}'
                  : '半荘を通して使う',
              title: matchActive ? '対局を再開する' : '実際の対局進行に合わせて\n点数計算を行う',
              description: matchActive
                  ? '局情報と登録済みの表ドラを引き継いで続けます'
                  : '点数計算できる人がいない場合に\n1半荘分の点数計算をサポート',
              action: matchActive ? '対局ホームへ' : '対局を始める',
              onTap: () => _openMatch(context),
            ),
            // History moved here from settings (device check 2026-10-04).
            const SizedBox(height: AppSpacing.m),
            SectionGroup(
              children: [
                SectionTile(
                  mark: '履',
                  title: '利用履歴',
                  subtitle: '過去の確認結果とAIとの会話',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HistoryScreen(),
                    ),
                  ),
                ),
              ],
            ),
            _buildTrainingAction(context),
          ],
        ),
      ),
    );
  }

  /// Two feature cards side by side, sharing the taller one's height.
  Widget _featureRow(List<Widget> cards) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 10),
        Expanded(child: cards[1]),
      ],
    ),
  );

  Widget _buildStartupError() =>
      StatusBanner(kind: StatusKind.error, message: startupError!);

  Widget _buildHeader(BuildContext context) => StreamBuilder<User?>(
    stream: AuthService.authStateChanges(),
    initialData: AuthService.currentUser,
    builder: (context, snapshot) {
      final user = snapshot.data;
      final text = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      return SizedBox(
        height: 70,
        child: Row(
          children: [
            const BrandMark(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TsumoAI',
                    maxLines: 1,
                    style: text.headlineSmall?.copyWith(
                      color: context.appColors.primaryDark,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '実卓麻雀アシスタント',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            if (user == null)
              OutlinedButton(
                onPressed: () => _signIn(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(74, AppSizes.tapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                child: const Text('ログイン'),
              )
            else
              IconButton(
                onPressed: () => _showAccountMenu(context, user),
                tooltip: 'アカウント',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  fixedSize: const Size(AppSizes.tapTarget, AppSizes.tapTarget),
                ),
                icon: Text(
                  (user.email ?? 'U').characters.first.toUpperCase(),
                  style: text.titleSmall?.copyWith(color: scheme.onPrimary),
                ),
              ),
            const SizedBox(width: 5),
            HeaderIconButton(
              icon: Icons.settings_outlined,
              tooltip: '設定',
              onPressed: () => _openSettings(context),
            ),
          ],
        ),
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
          padding: const EdgeInsets.only(top: 10),
          child: DeveloperShortcutCard(
            icon: Icons.photo_camera_outlined,
            title: '学習用の牌を1枚撮影',
            subtitle: '開発者設定で表示中',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TrainingDataScreen(cameras: cameras),
              ),
            ),
          ),
        );
      },
    );
  }

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
          onAuthenticationChanged: onAuthenticationChanged,
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
