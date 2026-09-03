import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/presentation/providers/flight_workspace_providers.dart';
import 'package:yuli/presentation/widgets/flight_workspace.dart';

void main() {
  test('workspace target keeps stable note and canvas identity', () {
    const target = FlightWorkspaceTarget(
      noteId: 7,
      folderId: 3,
      canvasBlockId: 42,
      kind: NoteKind.whiteboard,
      label: 'Cálculo · Derivadas',
      folderLabel: 'Universidad',
    );

    final restored = FlightWorkspaceTarget.fromJson(target.toJson());

    expect(restored.key, '7:42');
    expect(restored.label, target.label);
    expect(restored.kind, NoteKind.whiteboard);
    expect(flightWikiLinkLabel(restored), 'Cálculo#Derivadas');
  });

  test('note workspace target emits a readable wiki label', () {
    const target = FlightWorkspaceTarget(
      noteId: 8,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Regla de la cadena',
      folderLabel: 'Universidad',
    );

    expect(target.key, '8:0');
    expect(flightWikiLinkLabel(target), 'Regla de la cadena');
  });

  test('wiki labels cannot break their own delimiter', () {
    const target = FlightWorkspaceTarget(
      noteId: 9,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Tema ]] peligroso\ncontinuación',
      folderLabel: 'Universidad',
    );

    expect(flightWikiLinkLabel(target), 'Tema peligroso continuación');
  });
}
