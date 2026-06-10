import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/yuli_design.dart';
import 'note_cell_model.dart';
import 'stroke_stabilizer.dart';

/// Global (app-wide) drawing preferences, shared across all three editors:
/// per-tool color/width memory plus the stabilizer / palm / fill toggles.
/// These are user preferences, not note content — stored in SharedPreferences.
class DrawingPrefsData {
  StabilizerLevel stabilizer;
  bool palmRejection;
  bool fillShapes;
  EraserMode eraserMode;
  bool snapToGrid;
  Map<DrawTool, Color> toolColors;
  Map<DrawTool, double> toolWidths;

  DrawingPrefsData({
    required this.stabilizer,
    required this.palmRejection,
    required this.fillShapes,
    required this.eraserMode,
    required this.snapToGrid,
    required this.toolColors,
    required this.toolWidths,
  });
}

class DrawingPrefs {
  static const _kStab = 'draw_stabilizer_v1';
  static const _kPalm = 'draw_palm_v1';
  static const _kFill = 'draw_fill_v1';
  static const _kEraser = 'draw_eraser_v1';
  static const _kSnap = 'draw_snap_v1';
  static const _kColor = 'draw_toolcolor_';
  static const _kWidth = 'draw_toolwidth_';

  /// Tools that carry a remembered color + width.
  static const coloredTools = [
    DrawTool.pen,
    DrawTool.pencil,
    DrawTool.fountainPen,
    DrawTool.highlighter,
  ];

  static const Map<DrawTool, Color> defaultColors = {
    DrawTool.pen: yInk,
    DrawTool.pencil: Color(0xFF555555),
    DrawTool.fountainPen: yInk,
    DrawTool.highlighter: yAmber,
  };

  static const Map<DrawTool, double> defaultWidths = {
    DrawTool.pen: 3.0,
    DrawTool.pencil: 3.0,
    DrawTool.fountainPen: 2.0,
    DrawTool.highlighter: 20.0,
  };

  static Future<DrawingPrefsData> load() async {
    final p = await SharedPreferences.getInstance();
    // Default OFF: the geometry pipeline (Catmull-Rom / quadratic) already
    // smooths strokes, so a live position-lag stabilizer only adds the "extra
    // ink" catch-up tail when you decelerate at the end of a fast stroke. Users
    // who want extra stabilization can still turn it on.
    final stabIdx = (p.getInt(_kStab) ?? 0)
        .clamp(0, StabilizerLevel.values.length - 1);
    final colors = <DrawTool, Color>{};
    final widths = <DrawTool, double>{};
    for (final t in coloredTools) {
      final c = p.getInt('$_kColor${t.name}');
      colors[t] = c != null ? Color(c) : defaultColors[t]!;
      widths[t] = p.getDouble('$_kWidth${t.name}') ?? defaultWidths[t]!;
    }
    final eraserIdx =
        (p.getInt(_kEraser) ?? 0).clamp(0, EraserMode.values.length - 1);
    return DrawingPrefsData(
      stabilizer: StabilizerLevel.values[stabIdx],
      palmRejection: p.getBool(_kPalm) ?? true,
      fillShapes: p.getBool(_kFill) ?? false,
      eraserMode: EraserMode.values[eraserIdx],
      snapToGrid: p.getBool(_kSnap) ?? false,
      toolColors: colors,
      toolWidths: widths,
    );
  }

  static Future<void> saveEraserMode(EraserMode m) async {
    (await SharedPreferences.getInstance()).setInt(_kEraser, m.index);
  }

  static Future<void> saveSnapToGrid(bool v) async {
    (await SharedPreferences.getInstance()).setBool(_kSnap, v);
  }

  static Future<void> saveStabilizer(StabilizerLevel l) async {
    (await SharedPreferences.getInstance()).setInt(_kStab, l.index);
  }

  static Future<void> savePalm(bool v) async {
    (await SharedPreferences.getInstance()).setBool(_kPalm, v);
  }

  static Future<void> saveFill(bool v) async {
    (await SharedPreferences.getInstance()).setBool(_kFill, v);
  }

  static Future<void> saveToolColor(DrawTool t, Color c) async {
    (await SharedPreferences.getInstance())
        .setInt('$_kColor${t.name}', c.toARGB32());
  }

  static Future<void> saveToolWidth(DrawTool t, double w) async {
    (await SharedPreferences.getInstance()).setDouble('$_kWidth${t.name}', w);
  }

  static bool isColoredTool(DrawTool t) => coloredTools.contains(t);
}
