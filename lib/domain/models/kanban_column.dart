class KanbanColumn {
  final int id;
  final int labSpaceId;
  final String name;
  final int position;
  final bool isDefault;
  final bool isTerminal;

  const KanbanColumn({
    required this.id,
    required this.labSpaceId,
    required this.name,
    required this.position,
    required this.isDefault,
    this.isTerminal = false,
  });

  KanbanColumn copyWith({
    int? id,
    int? labSpaceId,
    String? name,
    int? position,
    bool? isDefault,
    bool? isTerminal,
  }) {
    return KanbanColumn(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      name: name ?? this.name,
      position: position ?? this.position,
      isDefault: isDefault ?? this.isDefault,
      isTerminal: isTerminal ?? this.isTerminal,
    );
  }
}
