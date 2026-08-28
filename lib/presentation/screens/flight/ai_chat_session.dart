import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/ai_usage_limiter.dart';
import '../../../domain/services/ai_assistant.dart';
import 'ai_modes.dart';

// The active system prompt now comes from the selected [AiMode] (ai_modes.dart);
// the chat sends mode.systemPrompt. The context anchor is sent as a SEPARATE
// user message (not concatenated) so the model distinguishes instruction from
// content, and is now OPTIONAL (modes work as pure dialogue without a note).

const _kAnchorMaxChars = 8000;

/// Message text marker for the tool-call indicator bubble. Chat UIs check for
/// this and render a spinning icon + "Consultando…" instead of plain text.
const kConsultingLabel = '⛏ CONSULTING_MARKER';

/// Above this length the context is "largo" → the chat suggests compacting it.
const kAnchorLongChars = 3000;

/// Above this raw-source length, the compactor switches from "compacta" to
/// "sintetiza en detalle" so huge Wikipedia-style articles don't become
/// superficial.
const kLongDocThreshold = 50000;

/// System prompt for compacting the context anchor (token-shielding). Preserves
/// facts/terms; drops web noise (nav, sidebar, footer). Returns ONLY the
/// compacted context.
const kCompactPrompt =
    'Compacta el siguiente contexto. Elimina elementos de navegación, '
    'enlaces del sitio, barras laterales, pies de página, comentarios de '
    'usuarios, reseñas y cabeceras irrelevantes. Preserva TODO el '
    'contenido útil: instrucciones paso a paso, listas, tablas, código, '
    'datos, fechas, nombres propios y términos técnicos. Conserva el '
    'formato markdown. Mantén el idioma original. Responde SOLO con el '
    'contexto compactado, sin comentarios ni encabezados adicionales.';

/// Alternate prompt for very long documents (>[kLongDocThreshold] chars).
/// Instead of "compact", asks for a detailed technical synthesis so the AI
/// doesn't over-compress out of necessity.
const kSynthesizePrompt =
    'Este es un documento extenso. Extrae una síntesis técnica detallada '
    'preservando TODOS los puntos clave, teoremas, fórmulas, datos '
    'numéricos, fechas, nombres propios y términos técnicos. Elimina '
    'navegación, enlaces del sitio, barras laterales, pies de página, '
    'comentarios de usuarios y cabeceras irrelevantes. Conserva el '
    'formato markdown. Mantén el idioma original. Responde SOLO con la '
    'síntesis, sin comentarios ni encabezados adicionales.';

enum AiResponseLength {
  brief(768),
  normal(1536),
  detailed(3072);

  final int maxTokens;
  const AiResponseLength(this.maxTokens);

  String get semanticInstruction => switch (this) {
    brief =>
      'POLÍTICA DE EXTENSIÓN (OBLIGATORIA): responde de forma breve y '
          'directa. Resuelve la petición con lo esencial, normalmente en 1 a 3 '
          'párrafos y unas 80 a 180 palabras. La personalidad puede cambiar el '
          'tono y el formato, pero no alargar esta respuesta. Prioriza antes de '
          'añadir detalles y reserva espacio para cerrar la última idea; nunca '
          'termines voluntariamente a mitad de frase, lista, tabla o bloque.',
    normal =>
      'POLÍTICA DE EXTENSIÓN (OBLIGATORIA): responde con una extensión '
          'equilibrada. Explica lo necesario con estructura clara y ejemplos '
          'solo cuando aporten valor, normalmente en unas 250 a 500 palabras. '
          'La personalidad puede cambiar el tono y el formato, pero no alargar '
          'innecesariamente la respuesta. Reserva espacio para una conclusión '
          'completa; nunca termines voluntariamente a mitad de frase, lista, '
          'tabla o bloque.',
    detailed =>
      'POLÍTICA DE EXTENSIÓN (OBLIGATORIA): desarrolla una respuesta completa '
          'y profunda. Incluye estructura, razonamiento, matices y ejemplos '
          'útiles cuando correspondan, normalmente en unas 700 a 1200 palabras. '
          'No agregues relleno si la petición es simple. La personalidad puede '
          'cambiar el tono y el formato, pero debe conservar esta profundidad. '
          'Reserva espacio para cerrar la respuesta; nunca termines '
          'voluntariamente a mitad de frase, lista, tabla o bloque.',
  };
}

enum AiHistoryDepth {
  recent(4, 1200),
  normal(8, 2400),
  full(null, 4000);

  final int? maxMessages;
  final int foreignTranscriptBudget;
  const AiHistoryDepth(this.maxMessages, this.foreignTranscriptBudget);
}

enum AiChatProfile { savings, balanced, complete, custom }

class AiChatSettings {
  final AiModel model;
  final AiResponseLength responseLength;
  final AiHistoryDepth historyDepth;
  final bool useNoteContext;
  final bool useRelatedSources;
  final bool useTools;
  final bool useInteractiveReplies;
  final bool useMemory;
  final bool useActionDrafts;

  const AiChatSettings({
    required this.model,
    required this.responseLength,
    required this.historyDepth,
    required this.useNoteContext,
    required this.useRelatedSources,
    required this.useTools,
    required this.useInteractiveReplies,
    required this.useMemory,
    required this.useActionDrafts,
  });

  const AiChatSettings.savings()
    : this(
        model: AiModel.flash,
        responseLength: AiResponseLength.brief,
        historyDepth: AiHistoryDepth.recent,
        useNoteContext: true,
        useRelatedSources: false,
        useTools: false,
        useInteractiveReplies: false,
        useMemory: false,
        useActionDrafts: false,
      );

  const AiChatSettings.balanced()
    : this(
        model: AiModel.flash,
        responseLength: AiResponseLength.normal,
        historyDepth: AiHistoryDepth.normal,
        useNoteContext: true,
        useRelatedSources: true,
        useTools: false,
        useInteractiveReplies: true,
        useMemory: false,
        useActionDrafts: false,
      );

  const AiChatSettings.complete()
    : this(
        model: AiModel.pro,
        responseLength: AiResponseLength.detailed,
        historyDepth: AiHistoryDepth.full,
        useNoteContext: true,
        useRelatedSources: true,
        useTools: true,
        useInteractiveReplies: true,
        useMemory: true,
        useActionDrafts: true,
      );

  AiChatProfile get profile {
    if (this == const AiChatSettings.savings()) return AiChatProfile.savings;
    if (this == const AiChatSettings.balanced()) return AiChatProfile.balanced;
    if (this == const AiChatSettings.complete()) return AiChatProfile.complete;
    return AiChatProfile.custom;
  }

  AiChatSettings copyWith({
    AiModel? model,
    AiResponseLength? responseLength,
    AiHistoryDepth? historyDepth,
    bool? useNoteContext,
    bool? useRelatedSources,
    bool? useTools,
    bool? useInteractiveReplies,
    bool? useMemory,
    bool? useActionDrafts,
  }) => AiChatSettings(
    model: model ?? this.model,
    responseLength: responseLength ?? this.responseLength,
    historyDepth: historyDepth ?? this.historyDepth,
    useNoteContext: useNoteContext ?? this.useNoteContext,
    useRelatedSources: useRelatedSources ?? this.useRelatedSources,
    useTools: useTools ?? this.useTools,
    useInteractiveReplies: useInteractiveReplies ?? this.useInteractiveReplies,
    useMemory: useMemory ?? this.useMemory,
    useActionDrafts: useActionDrafts ?? this.useActionDrafts,
  );

  Map<String, dynamic> toJson() => {
    'model': model.name,
    'responseLength': responseLength.name,
    'historyDepth': historyDepth.name,
    'useNoteContext': useNoteContext,
    'useRelatedSources': useRelatedSources,
    'useTools': useTools,
    'useInteractiveReplies': useInteractiveReplies,
    'useMemory': useMemory,
    'useActionDrafts': useActionDrafts,
  };

  factory AiChatSettings.fromJson(Map<String, dynamic> json) {
    const fallback = AiChatSettings.savings();
    T byName<T extends Enum>(List<T> values, Object? raw, T value) =>
        values.where((e) => e.name == raw).firstOrNull ?? value;
    bool flag(String key, bool value) =>
        json[key] is bool ? json[key] as bool : value;
    return AiChatSettings(
      model: byName(AiModel.values, json['model'], fallback.model),
      responseLength: byName(
        AiResponseLength.values,
        json['responseLength'],
        fallback.responseLength,
      ),
      historyDepth: byName(
        AiHistoryDepth.values,
        json['historyDepth'],
        fallback.historyDepth,
      ),
      useNoteContext: flag('useNoteContext', fallback.useNoteContext),
      useRelatedSources: flag('useRelatedSources', fallback.useRelatedSources),
      useTools: flag('useTools', fallback.useTools),
      useInteractiveReplies: flag(
        'useInteractiveReplies',
        fallback.useInteractiveReplies,
      ),
      useMemory: flag('useMemory', fallback.useMemory),
      useActionDrafts: flag('useActionDrafts', fallback.useActionDrafts),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiChatSettings &&
      model == other.model &&
      responseLength == other.responseLength &&
      historyDepth == other.historyDepth &&
      useNoteContext == other.useNoteContext &&
      useRelatedSources == other.useRelatedSources &&
      useTools == other.useTools &&
      useInteractiveReplies == other.useInteractiveReplies &&
      useMemory == other.useMemory &&
      useActionDrafts == other.useActionDrafts;

  @override
  int get hashCode => Object.hash(
    model,
    responseLength,
    historyDepth,
    useNoteContext,
    useRelatedSources,
    useTools,
    useInteractiveReplies,
    useMemory,
    useActionDrafts,
  );
}

class AiChatMsg {
  final AiRole role;
  final String text;
  final List<AiImageInput> images;
  final bool truncated;

  /// For assistant replies: the mode active when this reply was produced. Used
  /// to drop OTHER-mode replies from the sent history so the model doesn't
  /// imitate the old persona after a switch (the mode "trap"). null for user/
  /// system turns and legacy messages.
  final String? modeId;

  const AiChatMsg(
    this.role,
    this.text, {
    this.modeId,
    this.images = const [],
    this.truncated = false,
  });
}

class AiChatSettingsStore extends ChangeNotifier {
  static const _key = 'ai_chat_settings_global_v1';

  AiChatSettings settings = const AiChatSettings.savings();
  bool _loaded = false;
  bool _changed = false;
  Future<void>? _loading;

  Future<void> ensureLoaded({String? legacyKey}) {
    if (_loaded) return Future.value();
    return _loading ??= _load(legacyKey);
  }

  Future<void> _load(String? legacyKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_key) ??
        (legacyKey == null ? null : prefs.getString(legacyKey));
    if (raw != null && !_changed) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          settings = AiChatSettings.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          notifyListeners();
          if (!prefs.containsKey(_key)) {
            await prefs.setString(_key, jsonEncode(settings.toJson()));
          }
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  void setSettings(AiChatSettings value) {
    if (value == settings) return;
    settings = value;
    _changed = true;
    _loaded = true;
    notifyListeners();
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_key, jsonEncode(value.toJson())),
    );
  }
}

/// Per-note chat conversation. Lives in a (non-autoDispose) provider keyed by
/// note id, so it persists for the whole app run. **Messages live in memory for
/// the app session** (kept across leaving/re-entering the view; cleared only on
/// a full app close); the **context anchor persists per note** (SharedPreferences
/// keyed by [noteId]), so it survives even an app restart. The sheet is just a
/// window over this.
class AiChatSession extends ChangeNotifier {
  final int noteId;
  final AiChatSettingsStore? _settingsStore;

  /// Namespace so different entity kinds (notes vs lab spaces) that share the
  /// same int id don't collide in the session family or the persisted anchor
  /// key. 'note' keeps the legacy prefix; other scopes insert `${scope}_`.
  final String scope;

  AiChatSession(
    this.noteId, {
    this.scope = 'note',
    AiChatSettingsStore? settingsStore,
  }) : _settingsStore = settingsStore {
    _loadAnchor();
    _loadMode();
    if (_settingsStore == null) {
      _loadSettings();
    } else {
      settings = _settingsStore.settings;
      _settingsStore.addListener(_onGlobalSettings);
      _settingsStore.ensureLoaded(legacyKey: _settingsKey);
    }
  }

  static const _kAnchorPrefix = 'ai_ctx_v1_';

  String get _prefKey =>
      scope == 'note'
          ? '$_kAnchorPrefix$noteId'
          : '$_kAnchorPrefix${scope}_$noteId';

  String? anchor; // context anchor; null until set
  String? relatedAnchor;
  final List<AiChatMsg> messages = [];
  AiChatSettings settings = const AiChatSettings.savings();
  bool streaming = false;
  double chatScrollOffset = 0;
  bool hasChatScrollOffset = false;
  bool chatScrollAtBottom = true;

  AiModel get model => settings.model;
  int get _maxOutputTokens =>
      scope == 'note' ? settings.responseLength.maxTokens : 2048;
  int? get _maxHistoryMessages =>
      scope == 'note'
          ? settings.historyDepth.maxMessages
          : (model == AiModel.flash ? 8 : 16);
  int get _foreignTranscriptBudget =>
      scope == 'note' ? settings.historyDepth.foreignTranscriptBudget : 4000;

  /// Selected chat mode (skill). Persisted per session like the anchor; switching
  /// keeps the thread — the new system prompt applies from the next turn on.
  AiMode mode = defaultAiMode;

  // Token-shielding: previous anchor kept for a one-step undo after the AI
  // auto-compacts; [_compactTried] avoids re-compacting on every send.
  String? _previousAnchor;
  bool _compactTried = false;

  /// Index in [messages] of the latest compaction notice (for showing UNDO on
  /// just that one).
  int? compactNoticeIndex;

  bool get hasAnchor => (anchor?.trim().isNotEmpty) ?? false;
  bool get hasRelatedAnchor => (relatedAnchor?.trim().isNotEmpty) ?? false;
  bool get hasActiveContext =>
      (settings.useNoteContext && hasAnchor) ||
      (settings.useRelatedSources && hasRelatedAnchor);
  bool get anchorIsLong => (anchor?.length ?? 0) > kAnchorLongChars;
  bool get canUndoCompact => _previousAnchor != null;

  Future<void> _loadAnchor() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_prefKey);
    final related = p.getString(_relatedPrefKey);
    // Don't clobber an anchor that was set meanwhile (e.g. incoming OCR).
    if (saved != null && saved.isNotEmpty && anchor == null) {
      anchor = saved;
    }
    if (related != null && related.isNotEmpty && relatedAnchor == null) {
      relatedAnchor = related;
    }
    notifyListeners();
  }

  Future<void> _saveAnchor() async {
    final p = await SharedPreferences.getInstance();
    if (anchor == null || anchor!.isEmpty) {
      await p.remove(_prefKey);
    } else {
      await p.setString(_prefKey, anchor!);
    }
  }

  void setModel(AiModel m) {
    setSettings(settings.copyWith(model: m));
  }

  static const _kRelatedPrefix = 'ai_related_ctx_v1_';
  static const _kSettingsPrefix = 'ai_chat_settings_v1_';

  String get _relatedPrefKey =>
      scope == 'note'
          ? '$_kRelatedPrefix$noteId'
          : '$_kRelatedPrefix${scope}_$noteId';

  String get _settingsKey =>
      scope == 'note'
          ? '$_kSettingsPrefix$noteId'
          : '$_kSettingsPrefix${scope}_$noteId';

  bool _settingsChanged = false;

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_settingsKey);
    if (raw == null || _settingsChanged) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        settings = AiChatSettings.fromJson(Map<String, dynamic>.from(decoded));
        notifyListeners();
      }
    } catch (_) {}
  }

  void setSettings(AiChatSettings value) {
    if (_settingsStore != null) {
      _settingsStore.setSettings(value);
      return;
    }
    _applySettings(value, persist: true);
  }

  void _onGlobalSettings() {
    _applySettings(_settingsStore!.settings, persist: false);
  }

  void _applySettings(AiChatSettings value, {required bool persist}) {
    if (value == settings) return;
    final contextPolicyChanged =
        value.useNoteContext != settings.useNoteContext ||
        value.useRelatedSources != settings.useRelatedSources;
    settings = value;
    _settingsChanged = true;
    if (contextPolicyChanged && messages.isNotEmpty) {
      messages.clear();
      _previousAnchor = null;
      compactNoticeIndex = null;
      messages.add(
        const AiChatMsg(AiRole.system, '✦ Contexto ajustado — empecé de cero.'),
      );
    }
    notifyListeners();
    if (persist) {
      SharedPreferences.getInstance().then(
        (p) => p.setString(_settingsKey, jsonEncode(value.toJson())),
      );
    }
  }

  void saveChatScroll(double offset, {required bool atBottom}) {
    chatScrollOffset = offset;
    hasChatScrollOffset = true;
    chatScrollAtBottom = atBottom;
  }

  static const _kModePrefix = 'ai_mode_v1_';
  String get _modeKey =>
      scope == 'note'
          ? '$_kModePrefix$noteId'
          : '$_kModePrefix${scope}_$noteId';

  Future<void> _loadMode() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_modeKey);
    // Guard the race: if the user already switched mode before this async load
    // resolved, the mode is no longer the default — don't clobber their choice
    // with the persisted id (same pattern as [_loadAnchor]'s `anchor == null`).
    if (id != null && id != mode.id && mode.id == defaultAiMode.id) {
      mode = aiModeById(id);
      notifyListeners();
    }
  }

  /// Switch the chat mode. Keeps the thread (the new prompt applies going
  /// forward) and posts a clear notice so the user sees where the tone changed.
  void setMode(AiMode m) {
    if (m.id == mode.id) return;
    mode = m;
    messages.add(AiChatMsg(AiRole.system, '✦ Modo ${m.name} — ${m.blurb}'));
    notifyListeners();
    final p = SharedPreferences.getInstance();
    p.then((prefs) => prefs.setString(_modeKey, m.id));
  }

  /// Replace the active mode object in place after it was EDITED (same id, new
  /// persona/name/icon). Unlike [setMode] there's no switch notice and no id
  /// guard — it's the same mode with fresh content, applied from the next turn.
  void refreshMode(AiMode m) {
    if (m.id != mode.id) return;
    mode = m;
    notifyListeners();
  }

  void addLocalAssistant(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    messages.add(AiChatMsg(AiRole.assistant, t, modeId: mode.id));
    notifyListeners();
  }

  void setAnchor(String value) {
    final t = value.trim();
    _applyAnchor(t.isEmpty ? null : t, compactTried: false);
  }

  /// Set the anchor from the assembled multi-source context. The assembler has
  /// already compacted each source (cached), so skip the lazy whole-blob
  /// compaction ([compactTried] = true). Resets the thread if the context
  /// actually changed (see [_applyAnchor]).
  void setSyncedAnchor(String combined) {
    final t = combined.trim();
    _applyAnchor(t.isEmpty ? null : t, compactTried: true);
  }

  void setSyncedContexts({required String primary, required String related}) {
    final nextPrimary = primary.trim();
    final nextRelated = related.trim();
    final primaryChanged = nextPrimary != (anchor ?? '');
    final relatedChanged = nextRelated != (relatedAnchor ?? '');
    anchor = nextPrimary.isEmpty ? null : nextPrimary;
    relatedAnchor = nextRelated.isEmpty ? null : nextRelated;
    _compactTried = true;
    final activeChanged =
        (settings.useNoteContext && primaryChanged) ||
        (settings.useRelatedSources && relatedChanged);
    if (activeChanged && messages.isNotEmpty) {
      messages.clear();
      _previousAnchor = null;
      compactNoticeIndex = null;
      if (hasActiveContext) {
        messages.add(
          const AiChatMsg(
            AiRole.system,
            '✦ Contexto actualizado — empecé de cero.',
          ),
        );
      }
    }
    _saveAnchor();
    _saveRelatedAnchor();
    notifyListeners();
  }

  Future<void> _saveRelatedAnchor() async {
    final p = await SharedPreferences.getInstance();
    if (relatedAnchor == null || relatedAnchor!.isEmpty) {
      await p.remove(_relatedPrefKey);
    } else {
      await p.setString(_relatedPrefKey, relatedAnchor!);
    }
  }

  /// Replace the anchor, resetting the thread if the context actually changed
  /// mid-conversation (the prior turns are about the OLD context and would
  /// mislead the model — it trusts history over the changed anchor; resetting
  /// is the same as leaving + re-entering the view, but automatic).
  void _applyAnchor(String? next, {required bool compactTried}) {
    final changed = next != anchor;
    anchor = next;
    _compactTried = compactTried;
    if (changed && messages.isNotEmpty) {
      messages.clear();
      _previousAnchor = null;
      compactNoticeIndex = null;
      if (next != null) {
        messages.add(
          const AiChatMsg(
            AiRole.system,
            '✦ Contexto actualizado — empecé de cero.',
          ),
        );
      }
    }
    _saveAnchor();
    notifyListeners();
  }

  /// Append [value] to the existing anchor (accumulate context).
  void appendAnchor(String value) {
    final t = value.trim();
    if (t.isEmpty) return;
    anchor = hasAnchor ? '${anchor!}\n\n---\n\n$t' : t;
    _compactTried = false;
    _saveAnchor();
    notifyListeners();
  }

  /// Renders foreign-mode [msgs] (user/assistant turns, system notices already
  /// stripped by the caller) into a compact transcript for the mode-switch
  /// reference block. Capped from the FRONT to a char budget so the most recent
  /// foreign turns survive; the assistant is labelled "YuLi" (never the model).
  static String _foldTranscript(List<AiChatMsg> msgs, {required int budget}) {
    final lines = <String>[];
    for (final m in msgs) {
      final body = m.text.trim();
      if (body.isEmpty) continue;
      lines.add('${m.role == AiRole.assistant ? 'YuLi' : 'Usuario'}: $body');
    }
    // Keep the most recent turns within the budget, at WHOLE-line granularity —
    // accumulating from the end never cuts a line (or a multi-byte char) mid-way.
    final kept = <String>[];
    var used = 0;
    for (var i = lines.length - 1; i >= 0; i--) {
      final cost = lines[i].length + 2; // + the '\n\n' separator
      if (used + cost > budget && kept.isNotEmpty) break;
      kept.add(lines[i]);
      used += cost;
    }
    return kept.reversed.join('\n\n').trim();
  }

  /// The context anchor as a standalone user message (capped for token cost),
  /// kept SEPARATE from the system prompt so the model distinguishes the
  /// instruction (system) from the content (this).
  String _anchorContent(String value, {String kind = 'note'}) {
    final ctx = value;
    final capped =
        ctx.length > _kAnchorMaxChars
            ? ctx.substring(0, _kAnchorMaxChars)
            : ctx;
    if (kind == 'note') {
      return '<context_documents>\n$capped\n</context_documents>';
    }
    return '<related_context_documents>\n$capped\n'
        '</related_context_documents>';
  }

  /// Undo the last AI auto-compaction, restoring the previous context.
  void undoCompact() {
    final p = _previousAnchor;
    if (p == null) return;
    anchor = p;
    _previousAnchor = null;
    _compactTried = true; // don't auto-recompact right away
    _saveAnchor();
    notifyListeners();
  }

  /// If the context is excessively long, the AI compacts it (preserving key
  /// facts) and posts a notice to the chat. Counts as one request. Best-effort:
  /// on failure or no real gain, keeps the original.
  Future<void> _autoCompact(
    AiAssistant assistant,
    AiUsageLimiter limiter,
  ) async {
    _compactTried = true;
    final before = anchor;
    if (before == null) return;
    if (!await limiter.canSend()) return;
    await limiter.record();
    final buf = StringBuffer();
    try {
      await for (final tok in assistant.streamReply([
        const AiMessage(AiRole.system, kCompactPrompt),
        AiMessage(AiRole.user, before),
      ], model: AiModel.flash)) {
        buf.write(tok);
      }
    } catch (_) {
      return; // keep original on failure
    }
    final compacted = buf.toString().trim();
    if (compacted.isEmpty || compacted.length >= before.length) return;
    _previousAnchor = before;
    anchor = compacted;
    _saveAnchor();
    messages.add(
      AiChatMsg(
        AiRole.system,
        '✦ Compacté el contexto para ahorrar tokens '
        '(${before.length} → ${compacted.length} caracteres).',
      ),
    );
    compactNoticeIndex = messages.length - 1;
    notifyListeners();
  }

  /// Send [text] and stream the reply into [messages]. Runs on the session, so
  /// it survives the sheet closing. Counts against the daily [limiter].
  /// [quickAction] skips chat history — used for one-shot operations like
  /// "Resumir" or "Extraer tareas" so the model focuses only on the anchor.
  Future<void> send(
    AiAssistant assistant,
    AiUsageLimiter limiter,
    String text, {
    bool quickAction = false,
    List<AiToolDef> tools = const [],
    Future<String> Function(AiToolCall)? onToolCall,
    String? toolGuidance,
    List<String> widgetDocs = const [],
    List<String> knowledgeDocs = const [],
    List<String> memoryDocs = const [],
    List<AiImageInput> images = const [],
  }) async {
    final t = text.trim();
    if (streaming || t.isEmpty) return;
    if (images.isNotEmpty && model == AiModel.pro) return;
    if (images.length > kMaxAiImagesPerMessage) return;

    if (!await limiter.canSend()) {
      messages.add(
        const AiChatMsg(
          AiRole.assistant,
          '⚠️ Límite diario de IA alcanzado (150/día). Se reinicia mañana.',
        ),
      );
      notifyListeners();
      return;
    }

    // Mark busy NOW (before the auto-compact await) so the input is disabled
    // and a second send can't run concurrently during compaction.
    streaming = true;
    notifyListeners();

    // Token-shielding: the AI compacts an excessively long context first (and
    // notifies the user in the chat).
    if (settings.useNoteContext && anchorIsLong && !_compactTried) {
      await _autoCompact(assistant, limiter);
    }

    final modeId = mode.id;
    final history = List<AiChatMsg>.from(messages);
    messages.add(AiChatMsg(AiRole.user, t, images: images));
    messages.add(AiChatMsg(AiRole.assistant, '', modeId: modeId));
    notifyListeners();
    await limiter.record();

    final idx = messages.length - 1;
    final convo = <AiMessage>[
      AiMessage(AiRole.system, mode.systemPrompt),
      if (toolGuidance != null) AiMessage(AiRole.system, toolGuidance),
      if (settings.useNoteContext && hasAnchor)
        AiMessage(AiRole.user, _anchorContent(anchor!)),
      if (settings.useRelatedSources && hasRelatedAnchor)
        AiMessage(AiRole.user, _anchorContent(relatedAnchor!, kind: 'related')),
      // Keep this canonical policy inside the stable prefix. Per-turn retrieval
      // docs and the growing transcript follow it, so they cannot spoil its hit.
      if (scope == 'note')
        AiMessage(AiRole.system, settings.responseLength.semanticInstruction),
      if (knowledgeDocs.isNotEmpty)
        AiMessage(AiRole.system, knowledgeDocs.join('\n\n')),
      if (memoryDocs.isNotEmpty)
        AiMessage(AiRole.system, memoryDocs.join('\n\n')),
      if (widgetDocs.isNotEmpty)
        AiMessage(AiRole.system, widgetDocs.join('\n\n')),
    ];

    if (!quickAction) {
      // Mode-bleed defense. The model imitates its OWN prior assistant replies
      // (in-context few-shot) ABOVE the system prompt, so after a switch it
      // stays "trapped" in the persona that wrote most of the visible history.
      // A trailing system re-anchor wasn't enough (backends down-weight a system
      // turn placed after the user turn). Fix: find the last reply written in a
      // DIFFERENT mode — everything up to and including it is "foreign". Foreign
      // turns are FOLDED into one reference block sent as SYSTEM context (not as
      // assistant-role turns), so the model can still refer to what was said
      // (prior answers, the user's short "ok"/"no entiendo") WITHOUT a foreign
      // assistant *voice* left in the transcript to copy. Turns AFTER the cutoff
      // were written in the current mode and stay as normal role messages.
      var foreignCutoff = 0;
      for (var i = history.length - 1; i >= 0; i--) {
        final m = history[i];
        if (m.role == AiRole.assistant &&
            m.modeId != null &&
            m.modeId != modeId) {
          foreignCutoff = i + 1;
          break;
        }
      }

      if (foreignCutoff > 0) {
        final foreign =
            history
                .sublist(0, foreignCutoff)
                .where((m) => m.role != AiRole.system)
                .toList();
        final transcript = _foldTranscript(
          foreign,
          budget: _foreignTranscriptBudget,
        );
        if (transcript.isNotEmpty) {
          convo.add(
            AiMessage(
              AiRole.system,
              'Historial previo de esta conversación, escrito en OTRO modo de '
              'YuLi. Úsalo SOLO como información (puedes referirte a lo que ya se '
              'dijo), pero NO imites su estilo, su tono ni su formato: responde '
              'según tu modo actual y NO comentes ni acuses el cambio de modo.\n\n'
              '$transcript',
            ),
          );
        }
      }

      final live =
          history
              .sublist(foreignCutoff)
              .where((m) => m.role != AiRole.system)
              .toList();
      final maxHistory = _maxHistoryMessages;
      final capped =
          maxHistory != null && live.length > maxHistory
              ? live.sublist(live.length - maxHistory)
              : live;
      convo.addAll(capped.map((m) => AiMessage(m.role, m.text)));
    }
    convo.add(AiMessage(AiRole.user, t, images: images));

    if (tools.isNotEmpty && onToolCall != null) {
      await _streamWithTools(
        assistant,
        limiter,
        convo,
        idx,
        modeId,
        tools,
        onToolCall,
      );
    } else {
      await _streamPlain(assistant, limiter, convo, idx, modeId);
    }
    streaming = false;
    notifyListeners();
  }

  /// Plain streamed reply with transient-failure retry/backoff (the original
  /// path; used by the note chat without tools).
  Future<void> _streamPlain(
    AiAssistant assistant,
    AiUsageLimiter limiter,
    List<AiMessage> convo,
    int idx,
    String modeId,
  ) async {
    // Retry transient failures (network / 429 / 5xx) with backoff, but ONLY
    // before any token has streamed in this attempt — once text starts flowing
    // a retry would duplicate it. Shows a "Reintentando…" hint between tries.
    const maxRetries = 2;
    var attempt = 0;
    while (true) {
      var yielded = false;
      var truncated = false;
      try {
        await for (final event in assistant.streamReplyEvents(
          convo,
          model: model,
          maxTokens: _maxOutputTokens,
        )) {
          if (event is AiTextDelta) {
            yielded = true;
            messages[idx] = AiChatMsg(
              AiRole.assistant,
              messages[idx].text + event.text,
              modeId: modeId,
            );
            notifyListeners();
          } else if (event is AiStreamComplete) {
            truncated = event.truncated;
          }
        }
        if (truncated) _markTruncated(idx, modeId);
        break; // completed cleanly
      } catch (e) {
        final retryable = e is AiException && e.retryable;
        if (!yielded && retryable && attempt < maxRetries) {
          attempt++;
          if (!await limiter.canSend()) {
            messages[idx] = AiChatMsg(
              AiRole.assistant,
              '⚠️ Límite diario de IA alcanzado (150/día).',
              modeId: modeId,
            );
            notifyListeners();
            break;
          }
          await limiter.record();
          messages[idx] = AiChatMsg(
            AiRole.assistant,
            '⟳ Reintentando… ($attempt)',
            modeId: modeId,
          );
          notifyListeners();
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          messages[idx] = AiChatMsg(AiRole.assistant, '', modeId: modeId);
          notifyListeners();
          continue; // retry
        }
        if (yielded) {
          _markTruncated(idx, modeId);
          break;
        }
        messages[idx] = AiChatMsg(AiRole.assistant, '⚠️ $e', modeId: modeId);
        notifyListeners();
        break;
      }
    }
  }

  /// Function-calling loop: stream the turn; if the model requests tools, run
  /// them ([onToolCall]), append the results, and loop until it answers with
  /// text (or the iteration cap is hit). [convo] is mutated with the tool
  /// round-trip messages (which are NOT shown as chat bubbles).
  Future<void> _streamWithTools(
    AiAssistant assistant,
    AiUsageLimiter limiter,
    List<AiMessage> convo,
    int idx,
    String modeId,
    List<AiToolDef> tools,
    Future<String> Function(AiToolCall) onToolCall,
  ) async {
    const maxIters = 4;
    for (var iter = 0; iter < maxIters; iter++) {
      if (iter > 0) {
        if (!await limiter.canSend()) {
          messages[idx] = AiChatMsg(
            AiRole.assistant,
            '⚠️ Límite diario de IA alcanzado (150/día).',
            modeId: modeId,
          );
          notifyListeners();
          return;
        }
        await limiter.record();
      }
      final calls = <AiToolCall>[];
      var truncated = false;
      try {
        await for (final ev in assistant.streamReplyWithTools(
          convo,
          tools: tools,
          model: model,
          maxTokens: _maxOutputTokens,
        )) {
          if (ev is AiTextDelta) {
            messages[idx] = AiChatMsg(
              AiRole.assistant,
              messages[idx].text + ev.text,
              modeId: modeId,
            );
            notifyListeners();
          } else if (ev is AiToolCallRequest) {
            calls.addAll(ev.calls);
          } else if (ev is AiStreamComplete) {
            truncated = ev.truncated;
          }
        }
      } catch (e) {
        final hasPartial =
            messages[idx].text.trim().isNotEmpty &&
            messages[idx].text != kConsultingLabel;
        if (hasPartial) {
          _markTruncated(idx, modeId);
          return;
        }
        messages[idx] = AiChatMsg(AiRole.assistant, '⚠️ $e', modeId: modeId);
        notifyListeners();
        return;
      }

      if (truncated) {
        _markTruncated(idx, modeId);
        return;
      }
      if (calls.isEmpty) return; // model answered with text → done

      // Surface the lookup, then run the tools and feed results back.
      messages[idx] = AiChatMsg(
        AiRole.assistant,
        kConsultingLabel,
        modeId: modeId,
      );
      notifyListeners();
      // Ensure the indicator paints at least one frame before we run tools
      // (SQLite queries are near-instant and would otherwise flash invisible).
      await Future.delayed(const Duration(milliseconds: 400));
      convo.add(AiMessage(AiRole.assistant, '', toolCalls: calls));
      for (final c in calls) {
        final result = await onToolCall(c);
        convo.add(
          AiMessage(AiRole.tool, result, toolCallId: c.id, name: c.name),
        );
      }
      // Clear the placeholder for the next streamed turn.
      messages[idx] = AiChatMsg(AiRole.assistant, '', modeId: modeId);
      notifyListeners();
    }
    // Iteration cap hit without a final text answer.
    if (messages[idx].text.trim().isEmpty ||
        messages[idx].text == kConsultingLabel) {
      messages[idx] = AiChatMsg(
        AiRole.assistant,
        '⚠️ No pude completar la consulta.',
        modeId: modeId,
      );
      notifyListeners();
    }
  }

  void _markTruncated(int index, String modeId) {
    final current = messages[index].text;
    messages[index] = AiChatMsg(
      AiRole.assistant,
      current.trim().isEmpty
          ? 'La respuesta alcanzó el límite antes de poder mostrarse.'
          : current,
      modeId: modeId,
      truncated: true,
    );
    notifyListeners();
  }

  /// Regenerate the assistant reply at [assistantIndex]: drop it and everything
  /// after, then re-send the user turn that produced it. (Regenerating an older
  /// reply discards the turns below it — it's an explicit "redo from here".)
  Future<void> regenerate(
    int assistantIndex,
    AiAssistant assistant,
    AiUsageLimiter limiter,
  ) async {
    if (streaming) return;
    if (assistantIndex < 0 || assistantIndex >= messages.length) return;
    if (messages[assistantIndex].role != AiRole.assistant) return;
    int ui = -1;
    for (int i = assistantIndex - 1; i >= 0; i--) {
      if (messages[i].role == AiRole.user) {
        ui = i;
        break;
      }
    }
    if (ui < 0) return;
    final prompt = messages[ui].text;
    final images = messages[ui].images;
    messages.removeRange(ui, messages.length);
    notifyListeners();
    await send(assistant, limiter, prompt, images: images);
  }

  @override
  void dispose() {
    _settingsStore?.removeListener(_onGlobalSettings);
    super.dispose();
  }
}
