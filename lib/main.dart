import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/theme/app_tokens.dart';
import 'presentation/providers/database_providers.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/widgets/mode_switch.dart';
import 'presentation/widgets/app_banner.dart';
import 'presentation/screens/fight/fight_screen.dart';
import 'presentation/screens/flight/flight_screen.dart';
import 'presentation/screens/lab/lab_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/providers/navigation_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeOverride = await initThemeModeOverride();
  runApp(
    ProviderScope(
      overrides: [themeOverride],
      child: const YuLiApp(),
    ),
  );
}

class YuLiApp extends ConsumerWidget {
  const YuLiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'YuLi',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: themeMode,
      home: const _AppInit(),
    );
  }
}

/// Runs expiry queries before rendering the main shell.
class _AppInit extends ConsumerWidget {
  const _AppInit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiryAsync = ref.watch(expiryResultProvider);

    return expiryAsync.when(
      loading: () => Scaffold(
        backgroundColor: paperColor(context),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('YuLi', style: displayXL.copyWith(color: inkColor(context))),
              const SizedBox(height: 24),
              Container(
                width: 24,
                height: borderWidthHeavy,
                color: inkColor(context),
              ),
              const SizedBox(height: 8),
              Container(
                width: 16,
                height: borderWidth,
                color: inkGray.withAlpha(80),
              ),
            ],
          ),
        ),
      ),
      error: (_, _) => const AppShell(archivedTaskCount: 0),
      data: (archivedCount) => AppShell(archivedTaskCount: archivedCount),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  final int archivedTaskCount;

  const AppShell({super.key, required this.archivedTaskCount});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    // Listen for cross-mode note navigation requests
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(pendingNoteNavigationProvider, (_, noteId) {
        if (noteId != null) {
          ref.read(currentModeProvider.notifier).state = AppMode.flight;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(currentModeProvider);
    final showBanner = widget.archivedTaskCount > 0 &&
        !_bannerDismissed &&
        currentMode == AppMode.fight;

    return Scaffold(
      backgroundColor: paperColor(context),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showBanner)
              AppBanner(
                message:
                    '${widget.archivedTaskCount} tarea${widget.archivedTaskCount == 1 ? '' : 's'} archivada${widget.archivedTaskCount == 1 ? '' : 's'}',
                accentColor: accentFight,
                actionLabel: 'ver',
                onAction: () {},
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            Expanded(
              child: _ModeContent(currentMode: currentMode),
            ),
          ],
        ),
      ),
      bottomNavigationBar: currentMode != AppMode.home
          ? Container(
              decoration: BoxDecoration(
                color: paperColor(context),
                border: Border(
                  top: BorderSide(color: inkColor(context), width: borderWidth),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.home,
                      child: Container(
                        width: 48,
                        height: 56,
                        alignment: Alignment.center,
                        child: Icon(Icons.arrow_back, size: 20, color: inkColor(context)),
                      ),
                    ),
                    const Expanded(child: ModeSwitch()),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _ModeContent extends StatefulWidget {
  final AppMode currentMode;

  const _ModeContent({required this.currentMode});

  @override
  State<_ModeContent> createState() => _ModeContentState();
}

class _ModeContentState extends State<_ModeContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<Offset> _enterAnim = const AlwaysStoppedAnimation<Offset>(Offset.zero);
  Animation<Offset> _leaveAnim = const AlwaysStoppedAnimation<Offset>(Offset.zero);
  Widget _enteringChild = const SizedBox.shrink();
  Widget? _leavingChild;
  int _prevIndex = 0;

  int _modeIndex(AppMode m) => switch (m) {
        AppMode.home => 0,
        AppMode.fight => 1,
        AppMode.flight => 2,
        AppMode.lab => 3,
      };

  Widget _buildChild(AppMode m) => switch (m) {
        AppMode.home => const HomeScreen(),
        AppMode.fight => const FightScreen(),
        AppMode.flight => const FlightScreen(),
        AppMode.lab => const LabScreen(),
      };

  @override
  void initState() {
    super.initState();
    _prevIndex = _modeIndex(widget.currentMode);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => _leavingChild = null);
      });
    _enteringChild = _buildChild(widget.currentMode);
    _enterAnim = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
    _leaveAnim = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void didUpdateWidget(_ModeContent old) {
    super.didUpdateWidget(old);
    if (old.currentMode != widget.currentMode) {
      final newIndex = _modeIndex(widget.currentMode);
      final dir = newIndex > _prevIndex ? 1.0 : -1.0;
      _prevIndex = newIndex;
      _leavingChild = _enteringChild;
      _enteringChild = _buildChild(widget.currentMode);
      _enterAnim = Tween<Offset>(
        begin: Offset(dir, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
      _leaveAnim = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(-dir, 0.0),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_leavingChild != null)
          SlideTransition(position: _leaveAnim, child: _leavingChild!),
        SlideTransition(position: _enterAnim, child: _enteringChild),
      ],
    );
  }
}
