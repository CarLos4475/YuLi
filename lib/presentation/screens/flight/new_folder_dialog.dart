import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart' show yBorderStrong;

class NewFolderDialog extends ConsumerStatefulWidget {
  const NewFolderDialog({super.key});

  @override
  ConsumerState<NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends ConsumerState<NewFolderDialog> {
  final _nameController = TextEditingController();
  Color _selectedColor = folderPalette.first;

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
    await ref.read(folderRepositoryProvider).create(name, hex);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nueva carpeta', style: displayM.copyWith(color: ink)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: bodyL.copyWith(color: ink),
              decoration: InputDecoration(
                hintText: 'Nombre',
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
            Text('Color', style: labelBold.copyWith(color: inkGray)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  folderPalette.map((color) {
                    final isSelected = color == _selectedColor;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color:
                                isSelected ? yBorderStrong : Colors.transparent,
                            width: borderWidth,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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
    );
  }
}
