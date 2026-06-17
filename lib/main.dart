import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/services/crash_logger.dart';
import 'data/services/launcher_icon_lifecycle.dart';
import 'data/services/launcher_icon_service.dart';
import 'presentation/theme/app_tokens.dart';
import 'presentation/providers/database_providers.dart';
import 'presentation/providers/image_storage_providers.dart';
import 'presentation/providers/floating_pin_providers.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/widgets/app_banner.dart';
import 'presentation/widgets/yuli_design.dart';
import 'presentation/widgets/yuli_splash_screen.dart';
import 'presentation/screens/fight/fight_screen.dart';
import 'presentation/screens/flight/ai_modes.dart';
import 'presentation/screens/flight/flight_screen.dart';
import 'presentation/screens/lab/lab_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/trash/trash_screen.dart';
import 'presentation/providers/navigation_provider.dart';

void main() {
  // Guarded zone so uncaught async errors are captured too. ensureInitialized
  // must run INSIDE the zone or runApp/zone mismatch.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Edge-to-edge: the app paints behind the status & nav bars. Content stays
      // put (every shell is wrapped in SafeArea); only the background colour
      // floods into the system bars. The transparent bars + icon brightness are
      // applied per-theme via the MaterialApp builder below.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await CrashLogger.instance.init();

      // Framework (build/layout/paint) errors.
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        CrashLogger.instance.record(
          details.exception,
          details.stack,
          context: 'FlutterError',
        );
        prevOnError?.call(details); // keep default console output in debug
      };
      // Uncaught async / platform errors.
      PlatformDispatcher.instance.onError = (error, stack) {
        CrashLogger.instance.record(
          error,
          stack,
          context: 'PlatformDispatcher',
        );
        return true;
      };

      // Load user-authored chat modes into the module mirror BEFORE runApp so a
      // session restoring a persisted custom mode id resolves it (best-effort).
      await loadCustomModes();

      final themeOverride = await initThemeModeOverride();
      runApp(ProviderScope(overrides: [themeOverride], child: const YuLiApp()));
      LauncherIconLifecycle(LauncherIconService()).attach();
    },
    (error, stack) {
      CrashLogger.instance.record(error, stack, context: 'Zone');
    },
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
      // Transparent system bars so the app background floods them. Icon
      // brightness tracks the active theme (dark icons on cream, light on ink).
      // Wraps the navigator → applies app-wide, across every pushed route.
      builder: (context, child) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
            statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isLight ? Brightness.dark : Brightness.light,
            systemNavigationBarContrastEnforced: false,
          ),
          child: child!,
        );
      },
      home: const _AppInit(),
    );
  }
}

final _splashDelayProvider = FutureProvider<void>((ref) {
  return Future<void>.delayed(const Duration(milliseconds: 800));
});

/// Runs expiry queries before rendering the main shell.
class _AppInit extends ConsumerWidget {
  const _AppInit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiryAsync = ref.watch(expiryResultProvider);
    final splashDelayAsync = ref.watch(_splashDelayProvider);

    if (splashDelayAsync.isLoading) return const YuliSplashScreen();

    return expiryAsync.when(
      loading: () => const YuliSplashScreen(),
      error: (_, _) => const AppShell(archivedTaskCount: 0),
      data: (archivedCount) {
        // Reclaim orphaned image folders once the DB is settled. Fire-and-
        // forget; never blocks the shell.
        ref.read(imageCleanupProvider);
        ref.read(floatingPinCleanupProvider);
        return AppShell(archivedTaskCount: archivedCount);
      },
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
  StreamSubscription<String>? _reminderSub;

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
      ref.listenManual(pendingLabSpaceNavigationProvider, (_, spaceId) {
        if (spaceId != null) {
          ref.read(currentModeProvider.notifier).state = AppMode.lab;
        }
      });
      ref.listenManual(pendingFolderNavigationProvider, (_, folderId) {
        if (folderId != null) {
          ref.read(currentModeProvider.notifier).state = AppMode.flight;
        }
      });
      final reminders = ref.read(reminderCoordinatorProvider);
      reminders.initialize();
      _reminderSub = reminders.taps.listen(_handleReminderPayload);
    });
  }

  void _handleReminderPayload(String payload) {
    if (!mounted) return;
    final parts = payload.split(':');
    if (payload == 'summary' || parts.first == 'task') {
      ref.read(currentModeProvider.notifier).state = AppMode.fight;
      return;
    }
    if (parts.length >= 3 && parts.first == 'card') {
      final spaceId = int.tryParse(parts[1]);
      final cardId = int.tryParse(parts[2]);
      if (spaceId == null || cardId == null) return;
      ref.read(pendingKanbanCardNavigationProvider.notifier).state = cardId;
      ref.read(pendingLabSpaceNavigationProvider.notifier).state = spaceId;
      ref.read(currentModeProvider.notifier).state = AppMode.lab;
    }
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(currentModeProvider);
    final showBanner =
        widget.archivedTaskCount > 0 &&
        !_bannerDismissed &&
        currentMode == AppMode.fight;

    // Colour that floods the status bar (edge-to-edge): the active mode's
    // ModeHeader colour, so the bar continues seamlessly into the header band.
    // Painted as a thin strip (NOT the scaffold background — Fight & co. don't
    // paint their own bg, so a coloured scaffold turned the whole view red).
    // Home has no coloured header → cream.
    final statusBg = switch (currentMode) {
      AppMode.home => paperColor(context),
      AppMode.fight => yFight,
      AppMode.flight => yFlight,
      AppMode.lab => yLab,
    };
    final lightStatusBg = statusBg.computeLuminance() > 0.5;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Status-bar icons must contrast the flooded mode colour: light icons on
      // the dark Fight/Flight/Lab headers, dark on cream Home. Bottom nav is
      // cream → dark icons. Overrides the app-wide default for this route.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            lightStatusBg ? Brightness.dark : Brightness.light,
        statusBarBrightness: lightStatusBg ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: paperColor(context),
        resizeToAvoidBottomInset: currentMode != AppMode.home,
        body: Column(
          children: [
            // Strip that floods ONLY the status-bar inset with the mode colour;
            // the rest of the body stays on the cream scaffold. Continues
            // seamlessly into the ModeHeader band directly below it.
            Container(
              height: MediaQuery.paddingOf(context).top,
              color: statusBg,
            ),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    if (showBanner)
                      AppBanner(
                        message:
                            '${widget.archivedTaskCount} tarea${widget.archivedTaskCount == 1 ? '' : 's'} archivada${widget.archivedTaskCount == 1 ? '' : 's'}',
                        accentColor: accentFight,
                        actionLabel: 'ver',
                        onAction:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TrashScreen(),
                              ),
                            ),
                        onDismiss:
                            () => setState(() => _bannerDismissed = true),
                      ),
                    Expanded(child: _ModeContent(currentMode: currentMode)),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar:
            currentMode != AppMode.home ? const YuliBottomNav() : null,
      ),
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
  Animation<Offset> _enterAnim = const AlwaysStoppedAnimation<Offset>(
    Offset.zero,
  );
  Animation<Offset> _leaveAnim = const AlwaysStoppedAnimation<Offset>(
    Offset.zero,
  );
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
