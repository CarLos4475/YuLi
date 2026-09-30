import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/services/ai_assistant.dart';
import '../../../domain/services/fast_typing.dart';
import 'yuli_markdown_document.dart';

class YuliCorrectionChange {
  final Node node;
  final String before;
  final String after;
  final List<dynamic> originalDelta;

  YuliCorrectionChange(this.node, this.before, this.after, this.originalDelta);
}

class _FastTypingFragment {
  final Node node;
  final int start;
  final String text;

  const _FastTypingFragment(this.node, this.start, this.text);
}

class YuliBlockActions extends ChangeNotifier {
  final EditorState editor;
  final selected = <Node>{};
  bool busy = false;
  bool moving = false;
  String? notice;
  List<YuliCorrectionChange> changes = [];
  String? correctionBefore;
  String? correctionAfter;
  int _generation = 0;
  bool _disposed = false;

  YuliBlockActions(this.editor);

  List<Node> get ordered =>
      editor.document.root.children.where(selected.contains).toList();

  void toggle(Node node) {
    if (!selected.remove(node)) selected.add(node);
    moving = false;
    notifyListeners();
  }

  void clear() {
    selected.clear();
    moving = false;
    notice = null;
    changes = [];
    correctionBefore = null;
    correctionAfter = null;
    notifyListeners();
  }

  void selectWholeBlock() {
    selected
      ..clear()
      ..addAll(editor.document.root.children);
    moving = false;
    notice = null;
    changes = [];
    correctionBefore = null;
    correctionAfter = null;
    notifyListeners();
  }

  void cancel() {
    _generation++;
    busy = false;
    notice = 'Corrección cancelada. El texto sigue intacto.';
    notifyListeners();
  }

  String copyMarkdown() => YuliMarkdownDocument.encode(
    Document(
      root: pageNode(children: ordered.map((n) => n.deepCopy()).toList()),
    ),
  );

  void startMove() {
    moving = !moving;
    notifyListeners();
  }

  Future<void> moveBefore(Node? target) async {
    final nodes = ordered;
    if (nodes.isEmpty || nodes.contains(target)) return;
    final index = target?.path.first ?? editor.document.root.children.length;
    final transaction = editor.transaction;
    for (final node in nodes.reversed) {
      transaction.deleteNode(node);
    }
    transaction.insertNodes([index], nodes, deepCopy: false);
    transaction.afterSelection = null;
    await applyIsolated(transaction);
    moving = false;
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final nodes = ordered;
    if (nodes.isEmpty) return;
    final transaction = editor.transaction;
    for (final node in nodes.reversed) {
      transaction.deleteNode(node);
    }
    if (nodes.length == editor.document.root.children.length) {
      transaction.insertNode([0], paragraphNode());
    }
    transaction.afterSelection = null;
    await applyIsolated(transaction);
    selected.clear();
    moving = false;
    notice = 'Bloques eliminados. Puedes deshacer desde el editor.';
    notifyListeners();
  }

  List<Node> get eligible {
    final nodes = <Node>[];
    void visit(Node node) {
      if (node.type == yuliCodeBlockType ||
          node.type == yuliLatexBlockType ||
          node.type == ImageBlockKeys.type) {
        return;
      }
      if (node.delta != null && node.delta!.toPlainText().trim().isNotEmpty) {
        nodes.add(node);
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in ordered) {
      visit(node);
    }
    return nodes;
  }

  Future<void> correct(
    AiAssistant assistant,
    Future<bool> Function() reserve,
  ) async {
    if (busy) return;
    final leaves = eligible;
    if (leaves.isEmpty) return;
    final fragments = <_FastTypingFragment>[];
    final source = StringBuffer();
    for (final node in leaves) {
      if (source.isNotEmpty) source.write('\n\n');
      final text = node.delta!.toPlainText();
      fragments.add(_FastTypingFragment(node, source.length, text));
      source.write(text);
    }
    final original = source.toString();
    if (leaves.length > FastTyping.maxBlocks ||
        original.length > FastTyping.maxCharacters) {
      notice =
          'Selecciona menos texto: hasta 10 000 caracteres por corrección.';
      notifyListeners();
      return;
    }
    final roots = ordered;
    final fingerprints = {for (final node in roots) node: _fingerprint(node)};
    final owners = {for (final node in leaves) node: _rootOf(node)};
    final generation = ++_generation;
    busy = true;
    changes = [];
    correctionBefore = YuliMarkdownDocument.encode(editor.document);
    correctionAfter = null;
    notice = null;
    notifyListeners();
    try {
      if (!await reserve()) {
        throw const AiException(
          'No hay solicitudes disponibles. Revisa los ajustes de YuLi AI.',
        );
      }
      if (_disposed || generation != _generation) return;
      final result = await FastTyping(assistant).correct([original]);
      if (_disposed || generation != _generation) return;
      final stable =
          roots
              .where(
                (n) =>
                    editor.document.root.children.contains(n) &&
                    _fingerprint(n) == fingerprints[n],
              )
              .toSet();
      final transaction = editor.transaction;
      var skipped = result.rejected;
      final applied = <YuliCorrectionChange>[];
      final editsByNode = <Node, List<FastTypingEdit>>{};
      for (final edit in result.edits.single) {
        final end = edit.start + edit.before.length;
        final fragment = fragments.cast<_FastTypingFragment?>().firstWhere(
          (item) =>
              item != null &&
              edit.start >= item.start &&
              end <= item.start + item.text.length,
          orElse: () => null,
        );
        if (fragment == null) {
          skipped++;
          continue;
        }
        editsByNode
            .putIfAbsent(fragment.node, () => [])
            .add(
              FastTypingEdit(
                edit.start - fragment.start,
                edit.before,
                edit.after,
              ),
            );
      }
      for (final fragment in fragments) {
        final node = fragment.node;
        final originals = fragment.text;
        if (!stable.contains(owners[node]) ||
            !_attached(node) ||
            node.delta?.toPlainText() != originals) {
          skipped += editsByNode[node]?.length ?? 0;
          continue;
        }
        var after = originals;
        var edited = false;
        final originalDelta = node.delta!.toJson();
        final nodeEdits = [...?editsByNode[node]];
        nodeEdits.sort((left, right) => right.start.compareTo(left.start));
        for (final edit in nodeEdits) {
          final attributes = node.delta!.sliceAttributes(edit.start) ?? {};
          final protected = node.delta!
              .slice(edit.start, edit.start + edit.before.length)
              .toJson()
              .any((op) {
                final attrs = op['attributes'] as Map? ?? {};
                return attrs[AppFlowyRichTextKeys.code] == true ||
                    attrs[AppFlowyRichTextKeys.href] != null ||
                    attrs['yuli_latex'] == true ||
                    attrs['yuli_wiki_link'] == true;
              });
          if (protected) {
            skipped++;
            continue;
          }
          transaction.deleteText(node, edit.start, edit.before.length);
          transaction.insertText(
            node,
            edit.start,
            edit.after,
            attributes: attributes,
          );
          after = after.replaceRange(
            edit.start,
            edit.start + edit.before.length,
            edit.after,
          );
          edited = true;
        }
        if (edited) {
          applied.add(
            YuliCorrectionChange(node, originals, after, originalDelta),
          );
        }
      }
      if (applied.isNotEmpty) {
        transaction.afterSelection = editor.selection;
        await applyIsolated(transaction);
      }
      if (_disposed || generation != _generation) return;
      changes = applied;
      correctionAfter = YuliMarkdownDocument.encode(editor.document);
      notice =
          applied.isNotEmpty
              ? 'Texto corregido.'
              : skipped > 0
              ? 'YuLi propuso cambios que no pasaron la revisión segura.'
              : 'YuLi no detectó errores de tecleo claros.';
      if (skipped > 0 && applied.isNotEmpty) {
        notice = '$notice Se omitieron cambios dudosos o texto modificado.';
      }
    } on AiException catch (e) {
      if (!_disposed && generation == _generation) notice = e.message;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        notice = 'No se pudo completar la corrección. El texto sigue intacto.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> undoCorrection() async {
    final transaction = editor.transaction;
    var restored = 0;
    for (final change in changes) {
      if (_attached(change.node) &&
          change.node.delta?.toPlainText() == change.after) {
        transaction.updateNode(change.node, {'delta': change.originalDelta});
        restored++;
      }
    }
    transaction.afterSelection = editor.selection;
    if (restored > 0) await applyIsolated(transaction);
    notice =
        restored == changes.length
            ? 'Corrección deshecha.'
            : 'Se deshizo la corrección del texto que no has modificado.';
    changes = [];
    correctionBefore = null;
    correctionAfter = null;
    notifyListeners();
  }

  Future<void> applyIsolated(Transaction transaction) async {
    final stack = editor.undoManager.undoStack;
    if (stack.isNonEmpty) stack.last.seal();
    await editor.apply(transaction);
    if (stack.isNonEmpty) stack.last.seal();
  }

  bool _attached(Node node) => editor.getNodeAtPath(node.path) == node;
  Node _rootOf(Node node) {
    while (node.parent != null && node.parent != editor.document.root) {
      node = node.parent!;
    }
    return node;
  }

  String _fingerprint(Node node) => jsonEncode(node.toJson());

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
