String rebaseBackupPaths(
  String text,
  String previousRoot,
  String destinationRoot,
) {
  final roots = {previousRoot, previousRoot.replaceAll('\\', '/')};
  final pattern = RegExp(
    '(?:${roots.map(RegExp.escape).join('|')})'
        r'[/\\]+((?:note_images|floating_pins)[/\\]\d+[/\\][a-zA-Z0-9_.-]+|notebook_cameras[/\\]\d+\.json)',
  );
  return text.replaceAllMapped(
    pattern,
    (m) =>
        '${destinationRoot.replaceAll('\\', '/')}/${m.group(1)!.replaceAll('\\', '/')}',
  );
}

Object? rebaseBackupJson(
  Object? value,
  String previousRoot,
  String destinationRoot,
) {
  if (value is String) {
    return rebaseBackupPaths(value, previousRoot, destinationRoot);
  }
  if (value is List) {
    return value
        .map((v) => rebaseBackupJson(v, previousRoot, destinationRoot))
        .toList();
  }
  if (value is Map<String, dynamic>) {
    return value.map(
      (k, v) => MapEntry(k, rebaseBackupJson(v, previousRoot, destinationRoot)),
    );
  }
  return value;
}
