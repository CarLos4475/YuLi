import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

/// One remembered entry for a media pin's "recientes" list. [value] is the
/// addable string (a URL for web, a YouTube URL for video); [title] is the
/// optional label the user gave it.
class PinRecent {
  final String value;
  final String? title;

  const PinRecent({required this.value, this.title});

  Map<String, dynamic> toJson() => {'v': value, if (title != null) 't': title};

  static PinRecent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['v'];
    if (v is! String || v.isEmpty) return null;
    final t = raw['t'];
    return PinRecent(value: v, title: t is String && t.isNotEmpty ? t : null);
  }
}

/// Most-recently-used lists for the video and web pin prompts, stored in
/// SharedPreferences (device preference, not note content). Capped — adding past
/// [cap] evicts the oldest. Newest is first. De-duped by [PinRecent.value].
class PinRecents {
  static const _kWeb = 'pin_recent_web_v1';
  static const _kVideo = 'pin_recent_video_v1';
  static const _kPdf = 'pin_recent_pdf_v1';
  static const cap = 8;

  static Future<List<PinRecent>> web() => _load(_kWeb);
  static Future<List<PinRecent>> video() => _load(_kVideo);

  static Future<void> pushWeb(PinRecent r) => _push(_kWeb, r);
  static Future<void> pushVideo(PinRecent r) => _push(_kVideo, r);

  /// PDF recents reference the picked source file. Entries whose file no longer
  /// exists on disk are dropped (and the pruned list persisted) on load — if the
  /// user deletes the PDF, its recent quietly disappears.
  static Future<List<PinRecent>> pdf() async {
    final list = await _load(_kPdf);
    final alive = [for (final r in list) if (File(r.value).existsSync()) r];
    if (alive.length != list.length) await _write(_kPdf, alive);
    return alive;
  }

  static Future<void> pushPdf(PinRecent r) => _push(_kPdf, r);

  /// Removes a PDF recent by its source path (e.g. when a re-pin finds the file
  /// gone between listing and tapping).
  static Future<void> removePdf(String value) async {
    final list = await _load(_kPdf);
    final next = [for (final r in list) if (r.value != value) r];
    if (next.length != list.length) await _write(_kPdf, next);
  }

  static Future<List<PinRecent>> _load(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (PinRecent.fromJson(e) case final r?) r,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Pushes [r] to the front, removes any existing entry with the same value,
  /// and trims to [cap]. Fire-and-forget safe (never throws).
  static Future<void> _push(String key, PinRecent r) async {
    if (r.value.isEmpty) return;
    final current = await _load(key);
    final next = <PinRecent>[
      r,
      for (final e in current)
        if (e.value != r.value) e,
    ];
    if (next.length > cap) next.removeRange(cap, next.length);
    await _write(key, next);
  }

  static Future<void> _write(String key, List<PinRecent> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode([for (final e in list) e.toJson()]));
  }
}

/// Compact "RECIENTES" picker shown inside the video / web / pdf pin dialogs.
/// Tapping a row re-adds that entry. Renders nothing when [recents] is empty.
class PinRecentsList extends StatelessWidget {
  final List<PinRecent> recents;
  final IconData leadingIcon;
  final Color accent;
  final void Function(PinRecent) onPick;

  const PinRecentsList({
    super.key,
    required this.recents,
    required this.leadingIcon,
    required this.accent,
    required this.onPick,
  });

  String _label(PinRecent r) {
    if (r.title != null) return r.title!;
    final v = r.value;
    if (v.startsWith('http')) {
      return v
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceFirst(RegExp(r'/$'), '');
    }
    // File path → basename.
    return v.split(RegExp(r'[/\\]')).last;
  }

  @override
  Widget build(BuildContext context) {
    if (recents.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(YuLiIcons.clock, size: 11, color: yMuted),
            const SizedBox(width: 6),
            Text(
              'RECIENTES',
              style: yMono(
                size: 9,
                weight: FontWeight.w800,
                tracking: 1.4,
                color: yMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${recents.length})',
              style: yMono(size: 9, weight: FontWeight.w700, color: yMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: const BoxDecoration(
            color: yCream2,
            border: Border.fromBorderSide(
              BorderSide(color: yBorderStrong, width: yLineThin),
            ),
          ),
          constraints: const BoxConstraints(maxHeight: 168),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: recents.length,
            itemBuilder: (context, i) {
              final r = recents[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(r),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == recents.length - 1
                            ? Colors.transparent
                            : yBorderSoft,
                        width: yLineThin,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(leadingIcon, size: 14, color: accent),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _label(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: yMono(
                            size: 11,
                            weight: FontWeight.w600,
                            color: yInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(YuLiIcons.plus, size: 13, color: yMuted),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
