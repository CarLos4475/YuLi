import 'dart:ui';

String normalizeCanvasSearch(String value) {
  var text = value.toLowerCase();
  const from = 'áéíóúü';
  const to = 'aeiouu';
  for (var i = 0; i < from.length; i++) {
    text = text.replaceAll(from[i], to[i]);
  }
  return text;
}

class OcrSpellingSuggestion {
  final int start;
  final int end;
  final List<String> alternatives;

  const OcrSpellingSuggestion(this.start, this.end, this.alternatives);

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'alternatives': alternatives,
  };

  factory OcrSpellingSuggestion.fromJson(Map<String, dynamic> json) =>
      OcrSpellingSuggestion(
        json['start'] as int,
        json['end'] as int,
        (json['alternatives'] as List).cast<String>(),
      );
}

class CanvasOcrSegment {
  final String hash;
  final Rect bounds;
  final String text;
  final String? correctedText;
  final List<OcrSpellingSuggestion> spelling;
  final bool spellingChecked;
  final int alignmentVersion;
  final List<CanvasOcrWord> words;

  const CanvasOcrSegment({
    required this.hash,
    required this.bounds,
    required this.text,
    this.correctedText,
    this.spelling = const [],
    this.spellingChecked = false,
    this.alignmentVersion = 0,
    this.words = const [],
  });

  String get effectiveText => correctedText ?? text;

  CanvasOcrSegment corrected(
    String value, {
    List<OcrSpellingSuggestion> suggestions = const [],
  }) => CanvasOcrSegment(
    hash: hash,
    bounds: bounds,
    text: text,
    correctedText: value,
    spelling: suggestions,
    spellingChecked: true,
    alignmentVersion: alignmentVersion,
  );

  CanvasOcrSegment reviewed(List<OcrSpellingSuggestion>? suggestions) =>
      CanvasOcrSegment(
        hash: hash,
        bounds: bounds,
        text: text,
        correctedText: correctedText,
        words: words,
        alignmentVersion: alignmentVersion,
        spelling: suggestions ?? spelling,
        spellingChecked: suggestions != null,
      );

  Rect? wordBoundsFor(OcrSpellingSuggestion suggestion) {
    for (final word in words) {
      if (word.start == suggestion.start && word.end == suggestion.end) {
        return word.bounds;
      }
    }
    return null;
  }

  Rect? boundsForRange(int start, int end) {
    final matches = words.where((w) => w.start < end && w.end > start).toList();
    if (matches.isEmpty ||
        matches.first.start > start ||
        matches.last.end < end) {
      return null;
    }
    return matches.map((w) => w.bounds).reduce((a, b) => a.expandToInclude(b));
  }

  Map<String, dynamic> toJson() => {
    'hash': hash,
    'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
    'text': text,
    if (correctedText != null) 'corrected': correctedText,
    'spelling': spelling.map((s) => s.toJson()).toList(),
    'spellingChecked': spellingChecked,
    'alignmentVersion': alignmentVersion,
    'words': words.map((w) => w.toJson()).toList(),
  };

  factory CanvasOcrSegment.fromJson(Map<String, dynamic> json) {
    final b = (json['bounds'] as List).cast<num>();
    return CanvasOcrSegment(
      hash: json['hash'] as String,
      bounds: Rect.fromLTRB(
        b[0].toDouble(),
        b[1].toDouble(),
        b[2].toDouble(),
        b[3].toDouble(),
      ),
      text: json['text'] as String,
      correctedText: json['corrected'] as String?,
      spellingChecked: json['spellingChecked'] == true,
      alignmentVersion: (json['alignmentVersion'] as int?) ?? 0,
      words:
          [
                for (final raw in json['words'] as List? ?? [])
                  CanvasOcrWord.fromJson(Map<String, dynamic>.from(raw as Map)),
              ]
              .where(
                (w) =>
                    w.start >= 0 &&
                    w.end > w.start &&
                    w.end <=
                        ((json['corrected'] as String?) ??
                                (json['text'] as String))
                            .length &&
                    w.bounds.isFinite &&
                    !w.bounds.isEmpty,
              )
              .toList(),
      spelling:
          (json['spelling'] as List? ?? [])
              .map(
                (s) => OcrSpellingSuggestion.fromJson(
                  Map<String, dynamic>.from(s as Map),
                ),
              )
              .where(
                (s) =>
                    s.start >= 0 &&
                    s.end > s.start &&
                    s.end <=
                        ((json['corrected'] as String?) ??
                                (json['text'] as String))
                            .length,
              )
              .toList(),
    );
  }
}

class CanvasOcrWord {
  final int start;
  final int end;
  final Rect bounds;
  const CanvasOcrWord(this.start, this.end, this.bounds);

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
  };
  factory CanvasOcrWord.fromJson(Map<String, dynamic> json) {
    final b = (json['bounds'] as List).cast<num>();
    return CanvasOcrWord(
      json['start'] as int,
      json['end'] as int,
      Rect.fromLTRB(
        b[0].toDouble(),
        b[1].toDouble(),
        b[2].toDouble(),
        b[3].toDouble(),
      ),
    );
  }
}

class CanvasOcrPage {
  final int blockId;
  final int revision;
  final bool isCurrent;
  final List<CanvasOcrSegment> segments;

  const CanvasOcrPage(
    this.blockId,
    this.revision,
    this.isCurrent,
    this.segments,
  );
}

class CanvasOcrHit {
  final int noteId;
  final int blockId;
  final CanvasOcrSegment segment;

  const CanvasOcrHit(this.noteId, this.blockId, this.segment);
}
