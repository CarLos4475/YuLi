import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../widgets/coach_mark.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/task.dart';

class FightInput extends ConsumerStatefulWidget {
  const FightInput({super.key});

  @override
  ConsumerState<FightInput> createState() => _FightInputState();
}

class _FightInputState extends ConsumerState<FightInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Folder> _mentionFolders = [];
  int? _mentionStart; // index of '@' that opened the mention

  static const _maxChars = 280;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _contentLength {
    // @ mentions don't count toward the 280-char limit
    final text = _controller.text.replaceAll(RegExp(r'@\S+'), '');
    return text.length;
  }

  void _onTextChanged() {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0) return;

    // Detect '@' trigger
    final before = cursor > 0 ? text.substring(0, cursor) : '';
    final atIndex = before.lastIndexOf('@');
    final hasSpaceAfterAt = atIndex >= 0 &&
        !before.substring(atIndex).contains(' ') &&
        !before.substring(atIndex).contains('\n');

    if (atIndex >= 0 && hasSpaceAfterAt) {
      final query = before.substring(atIndex + 1).toLowerCase();
      _showMentionPopup(query);
      _mentionStart = atIndex;
    } else {
      _removeOverlay();
      _mentionStart = null;
    }

    setState(() {}); // refresh char counter
  }

  void _showMentionPopup(String query) {
    final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
    final cleanQuery = removeAccents(query.toLowerCase());
    final filtered = folders
        .where((f) => removeAccents(f.name.toLowerCase()).contains(cleanQuery))
        .toList();

    if (filtered.isEmpty) {
      _removeOverlay();
      return;
    }

    setState(() => _mentionFolders = filtered);

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 240,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 56),
          child: Material(
            color: Colors.transparent,
            child: CoachMark(
              flagKey: 'fight_at_mention',
              message: 'El @ asigna la carpeta. No cuenta para los 280 chars.',
              child: _MentionPopup(
                folders: _mentionFolders,
                onSelect: _onMentionSelect,
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onMentionSelect(Folder folder) {
    _removeOverlay();
    if (_mentionStart == null) return;

    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final replacement = '@${folder.name}';
    final newText =
        text.substring(0, _mentionStart) + replacement + text.substring(cursor);
    _controller.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: _mentionStart! + replacement.length),
    );
    _mentionStart = null;
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    // Resolve @FolderName → folder_id
    final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
    int? folderId;
    String content = raw;

    final mentionMatch = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)').firstMatch(raw);
    if (mentionMatch != null) {
      final name = mentionMatch.group(1)!;
      final cleanName = removeAccents(name.toLowerCase());
      final match = folders.where(
        (f) => removeAccents(f.name.toLowerCase()) == cleanName,
      );
      if (match.isNotEmpty) {
        folderId = match.first.id;
        content = raw;
      }
    }

    await ref.read(taskRepositoryProvider).save(
          Task(
            id: 0,
            content: content,
            status: TaskStatus.pending,
            folderId: folderId,
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 48)),
          ),
        );

    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeFoldersProvider);
    final charCount = _contentLength;
    final isNearLimit = charCount > 260;
    final isOverLimit = charCount > _maxChars;
    final isEmpty = _controller.text.trim().isEmpty;
    final isDisable = isOverLimit || isEmpty;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: BoxDecoration(
          color: paperColor(context),
          border: Border.all(
            color: inkColor(context),
            width: borderWidthHeavy,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: null,
                textInputAction: TextInputAction.send,
                style: bodyL.copyWith(color: inkColor(context)),
                decoration: InputDecoration(
                  hintText: 'Captura una tarea',
                  hintStyle: bodyL.copyWith(color: inkGray),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => isDisable ? null : _submit(),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$charCount',
              style: mono.copyWith(
                color: isOverLimit
                    ? accentFight
                    : isNearLimit
                        ? accentFight.withAlpha(180)
                        : inkGray,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isDisable ? null : _submit,
              child: Container(
                decoration: BoxDecoration(
                  color: isDisable ? inkGray.withAlpha(40) : inkColor(context),
                  border: Border.all(
                    color: isDisable ? inkGray.withAlpha(80) : inkColor(context),
                    width: borderWidth,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  'CAPTURAR',
                  style: labelBold.copyWith(
                    color: isDisable ? inkGray : paperColor(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionPopup extends StatelessWidget {
  final List<Folder> folders;
  final void Function(Folder) onSelect;

  const _MentionPopup({required this.folders, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: inkColor(context), width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: inkColor(context),
            offset: shadowOffset,
            blurRadius: shadowBlurRadius,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: folders.map((f) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(f),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    color: f.color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    f.name,
                    style: labelBold.copyWith(color: inkColor(context)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
