import 'package:flutter/material.dart';
import '../../../domain/models/note.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

class FlightNotePreview extends StatelessWidget {
  final NoteKind kind;
  final Color color;
  final String title;
  final String excerpt;

  const FlightNotePreview({
    super.key,
    required this.kind,
    required this.color,
    required this.title,
    this.excerpt = '',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 300,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 10,
            top: 12,
            child: CustomPaint(
              size: const Size(172, 288),
              painter: _PreviewShadowPainter(kind: kind),
            ),
          ),
          Positioned.fill(
            right: 8,
            bottom: 8,
            child: CustomPaint(
              painter: _PreviewShapePainter(kind: kind, color: color),
            ),
          ),
          Positioned.fill(
            right: 8,
            bottom: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 16, 16),
              child: _PreviewContent(
                kind: kind,
                color: color,
                title: title,
                excerpt: excerpt,
              ),
            ),
          ),
          if (kind == NoteKind.notebook)
            for (var i = 0; i < 7; i++)
              Positioned(
                left: -2,
                top: 34 + i * 28,
                child: Container(
                  width: 26,
                  height: 11,
                  decoration: BoxDecoration(
                    color: yBorderStrong,
                    border: Border.all(color: yBorderStrong, width: 1),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  final NoteKind kind;
  final Color color;
  final String title;
  final String excerpt;

  const _PreviewContent({
    required this.kind,
    required this.color,
    required this.title,
    required this.excerpt,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      NoteKind.notebook => 'CUADERNO',
      NoteKind.whiteboard => 'PIZARRA',
      NoteKind.block => 'NOTA',
    };
    final icon = switch (kind) {
      NoteKind.notebook => YuLiIcons.notebook,
      NoteKind.whiteboard => YuLiIcons.pencil,
      NoteKind.block => YuLiIcons.fileText,
    };
    final hex =
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: yCream, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: yCream),
              const SizedBox(width: 5),
              Text(
                label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yCream,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ySans(
            size: 21,
            weight: FontWeight.w800,
            letterSpacing: -0.2,
            color: yCream,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        if (kind == NoteKind.notebook) ...[
          _PreviewLine(label: 'Paginas', value: '01'),
          _PreviewRule(),
          _PreviewLine(label: 'Color', value: hex),
          _PreviewRule(),
          const _PreviewLine(label: 'Patron', value: 'Blanco'),
        ] else if (kind == NoteKind.whiteboard) ...[
          Text(
            'Lienzo infinito',
            style: yMono(
              size: 12,
              weight: FontWeight.w700,
              color: yCream,
            ).copyWith(height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            'Pan + zoom',
            style: yMono(
              size: 12,
              weight: FontWeight.w700,
              color: yCream,
            ).copyWith(height: 1.35),
          ),
        ] else ...[
          Text(
            excerpt.isEmpty
                ? 'Texto y bloques para capturar ideas, listas y apuntes.'
                : excerpt,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: yMono(
              size: 12,
              weight: FontWeight.w700,
              color: yCream,
            ).copyWith(height: 1.45),
          ),
        ],
        const Spacer(),
        Container(height: 1, color: yCream.withValues(alpha: 0.45)),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'HACE 0M',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.5,
                color: yCream,
              ),
            ),
            const Spacer(),
            Text(
              kind == NoteKind.notebook
                  ? '01 P'
                  : kind == NoteKind.whiteboard
                  ? '00 EL'
                  : '0B',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.5,
                color: yCream,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label\n$value',
      style: yMono(
        size: 10,
        weight: FontWeight.w700,
        tracking: 1.5,
        color: yCream.withValues(alpha: 0.84),
      ).copyWith(height: 1.22),
    );
  }
}

class _PreviewRule extends StatelessWidget {
  const _PreviewRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      height: 1,
      color: yCream.withValues(alpha: 0.26),
    );
  }
}

class _PreviewShapePainter extends CustomPainter {
  final NoteKind kind;
  final Color color;

  const _PreviewShapePainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final borderPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineMid
          ..color = yBorderStrong;
    final fillPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color;

    final path = switch (kind) {
      NoteKind.block => _notePath(size),
      _ => Path()..addRect(Offset.zero & size),
    };
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);

    if (kind == NoteKind.block) _paintFold(canvas, size, borderPaint);
    if (kind == NoteKind.whiteboard) _paintWhiteboardMarks(canvas, size);
    if (kind == NoteKind.notebook) _paintNotebookLines(canvas, size);
    canvas.restore();
  }

  Path _notePath(Size size) {
    const fold = 36.0;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  void _paintFold(Canvas canvas, Size size, Paint borderPaint) {
    const fold = 36.0;
    final foldPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = yCream;
    final foldPath =
        Path()
          ..moveTo(size.width - fold, 0)
          ..lineTo(size.width - fold, fold)
          ..lineTo(size.width, fold)
          ..close();
    canvas.drawPath(foldPath, foldPaint);
    canvas.drawPath(
      Path()
        ..moveTo(size.width - fold, 0)
        ..lineTo(size.width - fold, fold)
        ..lineTo(size.width, fold),
      borderPaint,
    );
  }

  void _paintNotebookLines(Canvas canvas, Size size) {
    final linePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = yCream.withValues(alpha: 0.2);
    for (var y = 126.0; y < size.height - 58; y += 18) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 18, y), linePaint);
    }
    canvas.drawLine(
      const Offset(34, 104),
      Offset(34, size.height - 62),
      linePaint,
    );
  }

  void _paintWhiteboardMarks(Canvas canvas, Size size) {
    final dotPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = yCream.withValues(alpha: 0.12);
    for (var x = 20.0; x < size.width - 18; x += 16) {
      for (var y = 20.0; y < size.height - 48; y += 16) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }

    final markPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.square
          ..color = yCream.withValues(alpha: 0.72);
    canvas.drawRect(Rect.fromLTWH(42, 160, 40, 36), markPaint);
    canvas.drawLine(const Offset(90, 178), const Offset(116, 178), markPaint);
    canvas.drawCircle(const Offset(140, 178), 20, markPaint);
    canvas.drawLine(const Offset(130, 166), const Offset(150, 190), markPaint);
    canvas.drawLine(const Offset(150, 166), const Offset(130, 190), markPaint);
  }

  @override
  bool shouldRepaint(covariant _PreviewShapePainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

class _PreviewShadowPainter extends CustomPainter {
  final NoteKind kind;

  const _PreviewShadowPainter({required this.kind});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = yBorderStrong;
    final path = switch (kind) {
      NoteKind.block => _notePath(size),
      _ => Path()..addRect(Offset.zero & size),
    };
    canvas.drawPath(path, paint);
  }

  Path _notePath(Size size) {
    const fold = 36.0;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _PreviewShadowPainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}
