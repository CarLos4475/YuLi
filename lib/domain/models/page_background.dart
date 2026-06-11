enum PageBackground {
  blank,
  lined,
  grid, // large grid
  gridSmall,
  dotted;

  String toDbString() => name;

  static PageBackground fromString(String s) => PageBackground.values
      .firstWhere((e) => e.name == s, orElse: () => PageBackground.blank);

  String get label => switch (this) {
    PageBackground.blank => 'BLANCO',
    PageBackground.lined => 'LÍNEAS',
    PageBackground.grid => 'CUADRÍCULA',
    PageBackground.gridSmall => 'CUADRÍCULA CHICA',
    PageBackground.dotted => 'PUNTOS',
  };
}
