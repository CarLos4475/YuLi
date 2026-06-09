import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../../data/services/crash_logger.dart';

/// Shows the persisted crash log with Share (to get it off the device — the
/// app folder is private storage) and Clear.
class CrashLogScreen extends StatefulWidget {
  const CrashLogScreen({super.key});

  @override
  State<CrashLogScreen> createState() => _CrashLogScreenState();
}

class _CrashLogScreenState extends State<CrashLogScreen> {
  String? _log;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await CrashLogger.instance.read();
    if (mounted) setState(() => _log = log);
  }

  Future<void> _share() async {
    final path = CrashLogger.instance.path;
    if (path != null && await File(path).exists()) {
      await Share.shareXFiles([XFile(path)], text: 'Crash log YuLi');
    } else if ((_log ?? '').isNotEmpty) {
      await Share.share(_log!);
    }
  }

  Future<void> _clear() async {
    await CrashLogger.instance.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    final paper = paperColor(context);
    final log = _log;
    final empty = log == null || log.trim().isEmpty;

    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: ink,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(YuLiIcons.arrowLeft, size: 20, color: paper),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('CRASH LOGS',
                      style: labelBold.copyWith(
                          color: paper, letterSpacing: 1.5, fontSize: 14)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: empty ? null : _share,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(YuLiIcons.share,
                          size: 20, color: empty ? inkGray : paper),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: empty ? null : _clear,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(YuLiIcons.trash,
                          size: 20, color: empty ? inkGray : paper),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: borderWidthHeavy, color: ink),
            Expanded(
              child: empty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Sin crashes registrados.\nLos errores futuros aparecerán aquí.',
                          textAlign: TextAlign.center,
                          style: bodyM.copyWith(color: inkGray),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        log,
                        style: mono.copyWith(color: ink, fontSize: 11),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
