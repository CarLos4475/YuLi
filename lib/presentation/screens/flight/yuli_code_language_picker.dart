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

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final selected = yuliCodeLanguageFor(widget.language);
    final filtered =
        query.isEmpty
            ? yuliCodeLanguages
            : yuliCodeLanguages.where((language) {
              final terms = [
                language.id,
                language.label,
                ...language.aliases,
              ].map((term) => term.toLowerCase());
              return terms.any((term) => term.contains(query));
            }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'LENGUAJE',
          style: yBody(size: 14, weight: FontWeight.w700, color: yInk),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.1),
            border: Border.all(color: widget.accent, width: yLineThin),
          ),
          child: Text(
            selected.id.isEmpty
                ? 'SELECCIONADO: TEXTO PLANO'
                : 'SELECCIONADO: ${selected.label.toUpperCase()}  /  ${selected.id.toUpperCase()}',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              color: widget.accent,
              tracking: 0.7,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          style: yBody(size: 14, color: yInk),
          decoration: const InputDecoration(
            hintText: 'BUSCAR LENGUAJE',
            border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final language in filtered)
                  _YuliCodeLanguageChip(
                    language: language,
                    selected: language.id == selected.id,
                    accent: widget.accent,
                    onTap: () {
                      widget.onChanged(language.id);
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _YuliCodeLanguageChip extends StatelessWidget {
  final YuliCodeLanguage language;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _YuliCodeLanguageChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow:
              selected
                  ? const [
                    BoxShadow(color: yInk, offset: Offset(2, 2), blurRadius: 0),
                  ]
                  : null,
        ),
        child: Text(
          language.label.toUpperCase(),
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            color: selected ? yCream : yInk,
            tracking: 0.6,
          ),
        ),
      ),
    );
  }
}
