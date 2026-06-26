import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';

class YuliCodeLanguage {
  final String id;
  final String label;
  final List<String> aliases;

  const YuliCodeLanguage({
    required this.id,
    required this.label,
    this.aliases = const [],
  });
}

const yuliCodeLanguages = [
  YuliCodeLanguage(id: '', label: 'Texto plano', aliases: ['plain', 'text']),
  YuliCodeLanguage(id: 'dart', label: 'Dart'),
  YuliCodeLanguage(id: 'js', label: 'JavaScript', aliases: ['javascript']),
  YuliCodeLanguage(id: 'ts', label: 'TypeScript', aliases: ['typescript']),
  YuliCodeLanguage(id: 'python', label: 'Python', aliases: ['py']),
  YuliCodeLanguage(id: 'java', label: 'Java'),
  YuliCodeLanguage(id: 'kotlin', label: 'Kotlin', aliases: ['kt']),
  YuliCodeLanguage(id: 'swift', label: 'Swift'),
  YuliCodeLanguage(id: 'c', label: 'C'),
  YuliCodeLanguage(id: 'cpp', label: 'C++', aliases: ['c++', 'cc', 'cxx']),
  YuliCodeLanguage(id: 'csharp', label: 'C#', aliases: ['cs', 'c#']),
  YuliCodeLanguage(id: 'go', label: 'Go', aliases: ['golang']),
  YuliCodeLanguage(id: 'rust', label: 'Rust', aliases: ['rs']),
  YuliCodeLanguage(id: 'php', label: 'PHP'),
  YuliCodeLanguage(id: 'ruby', label: 'Ruby', aliases: ['rb']),
  YuliCodeLanguage(id: 'sql', label: 'SQL'),
  YuliCodeLanguage(id: 'html', label: 'HTML'),
  YuliCodeLanguage(id: 'css', label: 'CSS'),
  YuliCodeLanguage(id: 'scss', label: 'SCSS', aliases: ['sass']),
  YuliCodeLanguage(id: 'json', label: 'JSON'),
  YuliCodeLanguage(id: 'yaml', label: 'YAML', aliases: ['yml']),
  YuliCodeLanguage(id: 'xml', label: 'XML'),
  YuliCodeLanguage(id: 'markdown', label: 'Markdown', aliases: ['md']),
  YuliCodeLanguage(id: 'bash', label: 'Bash', aliases: ['sh', 'shell']),
  YuliCodeLanguage(id: 'powershell', label: 'PowerShell', aliases: ['ps1']),
  YuliCodeLanguage(id: 'dockerfile', label: 'Dockerfile', aliases: ['docker']),
  YuliCodeLanguage(id: 'toml', label: 'TOML'),
  YuliCodeLanguage(id: 'ini', label: 'INI'),
  YuliCodeLanguage(id: 'r', label: 'R'),
  YuliCodeLanguage(id: 'matlab', label: 'MATLAB'),
  YuliCodeLanguage(id: 'julia', label: 'Julia', aliases: ['jl']),
  YuliCodeLanguage(id: 'lua', label: 'Lua'),
  YuliCodeLanguage(id: 'scala', label: 'Scala'),
  YuliCodeLanguage(id: 'elixir', label: 'Elixir', aliases: ['ex']),
  YuliCodeLanguage(id: 'erlang', label: 'Erlang', aliases: ['erl']),
  YuliCodeLanguage(id: 'haskell', label: 'Haskell', aliases: ['hs']),
  YuliCodeLanguage(id: 'clojure', label: 'Clojure', aliases: ['clj']),
  YuliCodeLanguage(id: 'solidity', label: 'Solidity', aliases: ['sol']),
];

String yuliNormalizeCodeLanguage(String value) {
  final normalized = value.trim().toLowerCase();
  for (final language in yuliCodeLanguages) {
    if (language.id == normalized ||
        language.label.toLowerCase() == normalized ||
        language.aliases.contains(normalized)) {
      return language.id;
    }
  }
  return normalized;
}

YuliCodeLanguage yuliCodeLanguageFor(String value) {
  final id = yuliNormalizeCodeLanguage(value);
  return yuliCodeLanguages.firstWhere(
    (language) => language.id == id,
    orElse:
        () => YuliCodeLanguage(id: id, label: id.isEmpty ? 'Texto plano' : id),
  );
}

class YuliCodeLanguagePicker extends StatefulWidget {
  final String language;
  final Color accent;
  final ValueChanged<String> onChanged;

  const YuliCodeLanguagePicker({
    super.key,
    required this.language,
    required this.accent,
    required this.onChanged,
  });

  @override
  State<YuliCodeLanguagePicker> createState() => _YuliCodeLanguagePickerState();
}

class _YuliCodeLanguagePickerState extends State<YuliCodeLanguagePicker> {
  late final TextEditingController _searchController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final selected = yuliCodeLanguageFor(widget.language);
    final filtered =
        query.isEmpty
            ? const <YuliCodeLanguage>[]
            : yuliCodeLanguages
                .where((language) {
                  final terms = [
                    language.id,
                    language.label,
                    ...language.aliases,
                  ].map((term) => term.toLowerCase());
                  return terms.any((term) => term.contains(query));
                })
                .take(6)
                .toList();
    final showSuggestions = _focusNode.hasFocus && filtered.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'LENGUAJE',
          style: yBody(size: 14, weight: FontWeight.w700, color: yInk),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          focusNode: _focusNode,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _selectFirst(filtered),
          textInputAction: TextInputAction.search,
          style: yBody(size: 14, color: yInk),
          decoration: InputDecoration(
            hintText:
                selected.id.isEmpty
                    ? 'BUSCAR LENGUAJE'
                    : 'BUSCAR LENGUAJE · ${selected.label.toUpperCase()}',
            hintStyle: yBody(size: 13, color: yMuted),
            border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: widget.accent, width: yLineMid),
            ),
          ),
        ),
        if (showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 6, right: 3, bottom: 3),
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineThin),
              boxShadow: const [
                BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final language in filtered)
                  _YuliCodeLanguageOption(
                    language: language,
                    selected: language.id == selected.id,
                    accent: widget.accent,
                    onTap: () {
                      _select(language);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _selectFirst(List<YuliCodeLanguage> languages) {
    if (languages.isEmpty) return;
    _select(languages.first);
  }

  void _select(YuliCodeLanguage language) {
    widget.onChanged(language.id);
    _searchController.clear();
    _focusNode.unfocus();
    setState(() {});
  }
}

class _YuliCodeLanguageOption extends StatelessWidget {
  final YuliCodeLanguage language;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _YuliCodeLanguageOption({
    required this.language,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : yCream,
          border: const Border(
            bottom: BorderSide(color: yBorderSoft, width: yLineThin),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                language.label.toUpperCase(),
                style: yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  color: selected ? accent : yInk,
                  tracking: 0.6,
                ),
              ),
            ),
            Text(
              language.id.isEmpty ? 'TEXT' : language.id.toUpperCase(),
              style: yMono(size: 9, color: yMuted, tracking: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
