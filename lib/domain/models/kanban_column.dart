class KanbanColumn {
  final int id;
  final int labSpaceId;
  final String name;
  final int position;
  final bool isDefault;

  const KanbanColumn({
    required this.id,
    required this.labSpaceId,
    required this.name,
    required this.position,
    required this.isDefault,
  });

  KanbanColumn copyWith({
    int? id,
    int? labSpaceId,
    String? name,
    int? position,
    bool? isDefault,
  }) {
    return KanbanColumn(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      name: name ?? this.name,
      position: position ?? this.position,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
