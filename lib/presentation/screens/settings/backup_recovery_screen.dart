import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart';
import '../flight/pin_dialog.dart';

class BackupRecoveryScreen extends StatelessWidget {
  const BackupRecoveryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paperColor(context),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RESTAURACIÓN PENDIENTE',
                  style: ySans(
                    color: inkColor(context),
                    size: 24,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No se pudo completar la restauración. YuLi conservó los archivos anteriores y no abrirá una base parcialmente restaurada. Comprueba el espacio libre, cierra la aplicación y vuelve a abrirla para reintentar.',
                  style: yBody(color: inkColor(context), size: 16),
                ),
                const SizedBox(height: 24),
                PinPrimaryButton(
                  label: 'Cerrar YuLi',
                  accent: accentJournal,
                  onTap: () => SystemNavigator.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
