enum PageBackground {
  blank,
  lined,
  grid,
  dotted;

  String toDbString() => name;

  static PageBackground fromString(String s) =>
      PageBackground.values.firstWhere(
        (e) => e.name == s,
        orElse: () => PageBackground.blank,
      );
}
