import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_providers.dart';
import '../theme/app_tokens.dart';
import '../screens/flight/pin_dialog.dart';
import 'yuli_design.dart';

class BackupActivityGate extends ConsumerWidget {
  final Widget child;
  const BackupActivityGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(backupManagerProvider).valueOrNull;
    if (manager == null) return child;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final blocked = manager.busy || manager.restorePending;
        return Stack(
          children: [
            AbsorbPointer(absorbing: blocked, child: child),
            if (blocked)
              Positioned.fill(
                child: Material(
                  color: paperColor(context),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (manager.busy)
                                const CircularProgressIndicator(
                                  color: accentJournal,
                                ),
                              const SizedBox(height: 20),
                              Text(
                                manager.status,
                                style: yBody(
                                  color: inkColor(context),
                                  size: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (manager.restorePending) ...[
                                const SizedBox(height: 24),
                                PinPrimaryButton(
                                  label: 'Cerrar YuLi',
                                  accent: accentJournal,
                                  onTap: () => SystemNavigator.pop(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
