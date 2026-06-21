import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/services/ai_memory_store.dart';
import '../../providers/ai_providers.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';

class AiMemoryScreen extends ConsumerStatefulWidget {
  const AiMemoryScreen({super.key});

  @override
  ConsumerState<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends ConsumerState<AiMemoryScreen> {
  late Future<List<AiMemoryRecord>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(aiMemoryStoreProvider).load();
  }

  Future<void> _delete(AiMemoryRecord memory) async {
    await ref.read(aiMemoryStoreProvider).delete(memory);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: ink,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        YuLiIcons.arrowLeft,
                        size: 20,
                        color: paperColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MEMORIA IA',
                    style: labelBold.copyWith(
                      color: paperColor(context),
                      fontSize: 14,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: borderWidthHeavy, color: ink),
            Expanded(
              child: FutureBuilder<List<AiMemoryRecord>>(
                future: _future,
                builder: (context, snap) {
                  final memories = snap.data ?? const <AiMemoryRecord>[];
                  if (snap.connectionState != ConnectionState.done) {
                    return Center(
                      child: Text(
                        'Cargando memorias',
                        style: bodyM.copyWith(color: inkGray),
                      ),
                    );
                  }
                  if (memories.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Aún no hay memorias guardadas.',
                          textAlign: TextAlign.center,
                          style: bodyM.copyWith(color: inkGray),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: memories.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder:
                        (context, i) => _MemoryTile(
                          memory: memories[i],
                          onDelete: () => _delete(memories[i]),
                        ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  final AiMemoryRecord memory;
  final VoidCallback onDelete;

  const _MemoryTile({required this.memory, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    final temporary =
        memory.expiresAt != null || memory.scope.startsWith('temp');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: ink, width: borderWidth),
        boxShadow: const [
          BoxShadow(
            color: inkBlack,
            offset: shadowOffset,
            blurRadius: shadowBlurRadius,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: temporary ? accentJournal : accentLab,
              border: Border.all(color: ink, width: borderWidth),
            ),
            child: Icon(YuLiIcons.brain, size: 17, color: paperLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(label: _scopeLabel(memory.scope), color: accentLab),
                    if (temporary)
                      _Chip(
                        label: _expiresLabel(memory.expiresAt),
                        color: accentJournal,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  memory.label,
                  style: labelBold.copyWith(
                    color: ink,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(memory.value, style: bodyM.copyWith(color: ink)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: paperColor(context),
                border: Border.all(color: ink, width: borderWidth),
              ),
              child: Icon(YuLiIcons.trash, size: 16, color: ink),
            ),
          ),
        ],
      ),
    );
  }

  String _scopeLabel(String scope) {
    if (scope == 'global') return 'Global';
    if (scope.startsWith('folder:')) return 'Folder ${scope.substring(7)}';
    if (scope.startsWith('note:')) return 'Nota ${scope.substring(5)}';
    if (scope.startsWith('temp')) return 'Temporal';
    return scope.isEmpty ? 'Global' : scope;
  }

  String _expiresLabel(DateTime? expiresAt) {
    if (expiresAt == null) return 'Temporal';
    return 'Hasta ${DateFormat('d MMM').format(expiresAt)}';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: inkColor(context), width: 1),
      ),
      child: Text(
        label,
        style: labelBold.copyWith(
          color: paperLight,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
