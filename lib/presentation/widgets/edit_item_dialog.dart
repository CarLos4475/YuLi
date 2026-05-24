import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class EditItemDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final Color initialColor;
  final Future<void> Function(String name, Color color) onSave;
  final VoidCallback onDelete;

  const EditItemDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  late final TextEditingController _controller;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: paperColor(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: ink, width: borderWidthHeavy),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: displayM.copyWith(color: ink)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              style: bodyL.copyWith(color: ink),
              decoration: InputDecoration(
                hintText: 'Nombre',
                hintStyle: bodyL.copyWith(color: inkGray),
              ),
            ),
            const SizedBox(height: 20),
            Text('Color', style: labelBold.copyWith(color: inkGray)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: folderPalette.map((color) {
                final isSelected = color == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: isSelected ? ink : Colors.transparent,
                        width: borderWidthHeavy,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: accentFight.withAlpha(30),
                      border: Border.all(color: accentFight, width: borderWidth),
                    ),
                    child: Text(
                      'Eliminar',
                      style: labelBold.copyWith(color: accentFight),
                    ),
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Text('Cancelar',
                            style: labelBold.copyWith(color: inkGray)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final name = _controller.text.trim();
                        if (name.isEmpty) return;
                        await widget.onSave(name, _selectedColor);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: ink,
                          border: Border.all(color: ink, width: borderWidth),
                        ),
                        child: Text(
                          'Guardar',
                          style: labelBold.copyWith(color: paperColor(context)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
