import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart' show yBorderStrong;
import '../../widgets/color_palette_picker.dart';

class NewLabSpaceDialog extends ConsumerStatefulWidget {
  const NewLabSpaceDialog({super.key});

  @override
  ConsumerState<NewLabSpaceDialog> createState() => _NewLabSpaceDialogState();
}

class _NewLabSpaceDialogState extends ConsumerState<NewLabSpaceDialog> {
  final _nameController = TextEditingController();
  Color _selectedColor = accentFlight; // azul pizarra default

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final hex =
        '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    await ref.read(labSpaceRepositoryProvider).create(name, hex);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: paperColor(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: borderWidth),
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nuevo space', style: displayM.copyWith(color: ink)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: bodyL.copyWith(color: ink),
              decoration: InputDecoration(
                hintText: 'Nombre del proyecto',
                hintStyle: bodyL.copyWith(color: inkGray),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: yBorderStrong,
                    width: borderWidth,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: yBorderStrong,
                    width: borderWidth,
                  ),
                ),
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 20),
            Text('Color de acento', style: labelBold.copyWith(color: inkGray)),
            const SizedBox(height: 8),
            ColorPalettePicker(
              selected: _selectedColor,
              onChanged: (c) => setState(() => _selectedColor = c),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      'Cancelar',
                      style: labelBold.copyWith(color: inkGray),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _create,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: ink,
                      border: Border.all(
                        color: yBorderStrong,
                        width: borderWidth,
                      ),
                    ),
                    child: Text(
                      'Crear',
                      style: labelBold.copyWith(color: paperColor(context)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
