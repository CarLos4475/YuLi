import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/services/backup/backup_manager.dart';
import '../../../data/services/image_storage.dart';
import '../../providers/database_providers.dart';
import '../../providers/image_storage_providers.dart';
import '../../providers/floating_pin_providers.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../flight/pin_dialog.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String? _message;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _action((manager) => manager.refresh());
      });
    }
  }

  Future<void> _action(Future<void> Function(BackupManager) run) async {
    try {
      final manager = await ref.read(backupManagerProvider.future);
      await ref.read(expiryResultProvider.future);
      await ref.read(imageCleanupProvider.future);
      await ref.read(floatingPinCleanupProvider.future);
      await run(manager);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message =
                  'No se completó la operación. Revisa el estado del respaldo.',
        );
      }
    }
  }

  Future<void> _confirmRestore(BackupManager manager, Directory stage) async {
    final info =
        jsonDecode(await File('${stage.path}/restore_info.json').readAsString())
            as Map;
    final counts = info['counts'] as Map;
    final summary =
        'Copia del ${_date(DateTime.parse(info['createdAt'] as String))}: ${counts['notes']} documentos, ${counts['tasks']} tareas y ${counts['lab_spaces']} espacios Lab. ';
    if (!mounted) {
      await stage.delete(recursive: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => PinDialogShell(
            icon: YuLiIcons.rotateCcw,
            title: 'RESTAURAR RESPALDO',
            accent: accentJournal,
            footer: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                PinPrimaryButton(
                  label: 'Cancelar',
                  accent: accentJournal,
                  onTap: () => Navigator.pop(context, false),
                ),
                PinPrimaryButton(
                  label: 'Restaurar al reiniciar',
                  accent: accentJournal,
                  onTap: () => Navigator.pop(context, true),
                ),
              ],
            ),
            child: Text(
              '${summary}El archivo pasó la verificación. Al volver a abrir YuLi, sus datos reemplazarán los actuales. Conservaremos una copia local del estado anterior. La conexión automática a Drive quedará desactivada.',
              style: yBody(color: yInk, size: 14),
            ),
          ),
    );
    if (confirmed == true) {
      await manager.restore(stage);
    } else {
      await stage.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupManagerProvider);
    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: state.when(
          loading:
              () => const Center(
                child: CircularProgressIndicator(color: accentJournal),
              ),
          error:
              (_, _) => Center(
                child: Text(
                  'No se pudo abrir Respaldos.',
                  style: yBody(color: inkColor(context), size: 16),
                ),
              ),
          data:
              (manager) => AnimatedBuilder(
                animation: manager,
                builder:
                    (context, _) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(YuLiIcons.arrowLeft),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                Expanded(
                                  child: Text(
                                    'RESPALDOS',
                                    style: ySans(
                                      color: inkColor(context),
                                      size: 24,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Recupera tus apuntes al reinstalar YuLi o cambiar de tablet.',
                              style: yBody(color: inkColor(context), size: 16),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              manager.email == null
                                  ? 'Google Drive desconectado'
                                  : 'Cuenta: ${manager.email}',
                              style: yBody(color: inkColor(context), size: 14),
                            ),
                            if (manager.lastSuccess != null)
                              Text(
                                'Último respaldo confirmado: ${_date(DateTime.parse(manager.lastSuccess!))}',
                                style: yBody(
                                  color: inkColor(context),
                                  size: 14,
                                ),
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                PinPrimaryButton(
                                  label:
                                      manager.email == null
                                          ? 'Conectar Google Drive'
                                          : 'Cambiar cuenta',
                                  accent: accentJournal,
                                  onTap:
                                      () => _action((m) async {
                                        if (m.email != null) {
                                          await m.disconnect();
                                        }
                                        await m.connect();
                                      }),
                                ),
                                if (manager.email != null) ...[
                                  PinPrimaryButton(
                                    label: 'Respaldar ahora',
                                    accent: accentJournal,
                                    onTap: () => _action((m) => m.backupNow()),
                                  ),
                                  PinPrimaryButton(
                                    label: 'Buscar respaldos',
                                    accent: accentJournal,
                                    onTap: () => _action((m) => m.refresh()),
                                  ),
                                  PinPrimaryButton(
                                    label: 'Desconectar',
                                    accent: accentJournal,
                                    onTap: () => _action((m) => m.disconnect()),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 24),
                            if (manager.email != null) ...[
                              Row(
                                children: [
                                  Checkbox(
                                    value: manager.automatic,
                                    activeColor: accentJournal,
                                    shape: const RoundedRectangleBorder(),
                                    onChanged:
                                        (v) => _action(
                                          (m) => m.setAutomatic(v ?? false),
                                        ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Respaldo automático diario',
                                      style: yBody(
                                        color: inkColor(context),
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Se intenta desde Inicio mientras YuLi está abierta. Requiere conexión y puede usar datos móviles. Conserva las copias anteriores en tu Drive; puedes eliminarlas allí cuando ya no las necesites.',
                                style: yBody(
                                  color: inkColor(context),
                                  size: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            Text(
                              'ARCHIVO DE RESPALDO',
                              style: yMono(
                                color: inkColor(context),
                                size: 14,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                PinPrimaryButton(
                                  label: 'Exportar archivo',
                                  accent: accentJournal,
                                  onTap:
                                      () => _action((m) async {
                                        final file = await m.exportLocal();
                                        await Share.shareXFiles([
                                          XFile(file.path),
                                        ], text: 'Respaldo de YuLi');
                                        if (mounted) {
                                          setState(
                                            () =>
                                                _message =
                                                    'Archivo creado. Guárdalo fuera de YuLi para conservarlo al desinstalar.',
                                          );
                                        }
                                      }),
                                ),
                                PinPrimaryButton(
                                  label: 'Restaurar archivo',
                                  accent: accentJournal,
                                  onTap:
                                      () => _action((m) async {
                                        final picked = await FilePicker.platform
                                            .pickFiles(
                                              type: FileType.any,
                                              allowMultiple: false,
                                            );
                                        final path = picked?.files.single.path;
                                        if (path == null) return;
                                        await _confirmRestore(
                                          m,
                                          await m.prepareLocal(File(path)),
                                        );
                                      }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Incluye datos editables y adjuntos. Las claves de API quedan fuera. El archivo contiene tus apuntes privados: compártelo solo con quien quieras darles acceso.',
                              style: yBody(color: inkColor(context), size: 13),
                            ),
                            if (manager.error != null ||
                                _message != null ||
                                manager.status.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(
                                manager.error ?? _message ?? manager.status,
                                style: yBody(
                                  color: inkColor(context),
                                  size: 14,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            Text(
                              'COPIAS EN GOOGLE DRIVE',
                              style: yMono(
                                color: inkColor(context),
                                size: 14,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (manager.backups.isEmpty)
                              Text(
                                'Conecta tu cuenta y busca tus respaldos.',
                                style: yBody(
                                  color: inkColor(context),
                                  size: 14,
                                ),
                              ),
                            for (final backup in manager.backups)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: inkColor(context),
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Respaldo: ${_date(backup.createdAt)}',
                                      style: yBody(
                                        color: inkColor(context),
                                        size: 15,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Tamaño: ${humanBytes(backup.size)} · Tablet: ${backup.deviceId.isEmpty ? 'Sin identificar' : backup.deviceId.substring(0, backup.deviceId.length.clamp(0, 8))}',
                                      style: yBody(
                                        color: inkColor(context),
                                        size: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    PinPrimaryButton(
                                      label: 'Verificar y restaurar',
                                      accent: accentJournal,
                                      onTap:
                                          () => _action(
                                            (m) async => _confirmRestore(
                                              m,
                                              await m.prepareDrive(backup),
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
              ),
        ),
      ),
    );
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
