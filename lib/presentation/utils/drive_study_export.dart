import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_providers.dart';

Future<void> uploadStudyExport(
  WidgetRef ref,
  BuildContext context,
  File file,
) async {
  final manager = await ref.read(backupManagerProvider.future);
  await manager.uploadStudy(file);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Apunte guardado en Google Drive: YuLi — Apuntes'),
      ),
    );
  }
}
