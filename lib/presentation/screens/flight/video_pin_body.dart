import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

/// Height of the YuLi study bar under the 16:9 player. Reserved by the pin clamp
/// (see [VideoPinPayload.bottomChromeHeight]) so width drives the player height.
const double kVideoStudyBarHeight = 38;

/// Brutalist dialog: paste a YouTube link (+ optional title) for a new video
/// pin. Returns null on cancel / empty link.
Future<({String url, String? title})?> promptYoutubeVideo(
    BuildContext context) async {
  final urlCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  InputDecoration deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: yMono(size: 11, color: yMuted),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
  return showDialog<({String url, String? title})>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: yBorderStrong, width: yLineMid),
        borderRadius: BorderRadius.zero,
      ),
      title: Text(
        'PEGAR LINK DE YOUTUBE',
        style: yMono(size: 11, weight: FontWeight.w700, tracking: 1.2),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: urlCtrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: yMono(size: 12),
            decoration: deco('https://youtu.be/...'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: titleCtrl,
            style: yMono(size: 12),
            decoration: deco('TÍTULO (OPCIONAL)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('CANCELAR', style: yMono(size: 11, color: yMuted)),
        ),
        TextButton(
          onPressed: () {
            final url = urlCtrl.text.trim();
            if (url.isEmpty) {
              Navigator.pop(ctx);
              return;
            }
            final title = titleCtrl.text.trim();
            Navigator.pop(ctx, (url: url, title: title.isEmpty ? null : title));
          },
          child: Text('AGREGAR', style: yMono(size: 11, weight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// Body of a floating YouTube pin: the official iframe player (its own controls
/// stay visible for ads/skip) plus a YuLi study bar (play/pause, -10/+10, seek,
/// copy timestamp). Online-only by nature. Owns the controller so it survives
/// the window's rebuilds; on collapse the parent passes [active] = false and we
/// PAUSE (the WebView stays mounted, just hidden — restoring is instant). The
/// last position is reported up so it persists across reopen and app restart.
class VideoPinBody extends StatefulWidget {
  final String videoId;
  final int startSeconds;
  final bool active;

  /// Note/folder accent — fills the play button + the seek track.
  final Color accent;
  final ValueChanged<int>? onPosition;

  const VideoPinBody({
    super.key,
    required this.videoId,
    this.startSeconds = 0,
    this.active = true,
    required this.accent,
    this.onPosition,
  });

  @override
  State<VideoPinBody> createState() => _VideoPinBodyState();
}

class _VideoPinBodyState extends State<VideoPinBody> {
  late final YoutubePlayerController _controller =
      YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: false,
    startSeconds: widget.startSeconds.toDouble(),
    params: const YoutubePlayerParams(
      showControls: true,
      showFullscreenButton: false,
      enableCaption: false,
    ),
  );

  late final Stream<Duration> _posStream =
      _controller.videoStateStream.map((s) => s.position);
  StreamSubscription<Duration>? _posSub;
  final ValueNotifier<double?> _dragSeconds = ValueNotifier(null);
  int _lastSeconds = 0;

  @override
  void initState() {
    super.initState();
    _lastSeconds = widget.startSeconds;
    _posSub = _posStream.listen((d) {
      final s = d.inSeconds;
      if (s != _lastSeconds) {
        _lastSeconds = s;
        widget.onPosition?.call(s); // controller debounces the write
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideoPinBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Collapsing pauses; restoring leaves it paused for the user to resume.
    if (oldWidget.active && !widget.active) {
      _controller.pauseVideo();
    }
  }

  @override
  void dispose() {
    widget.onPosition?.call(_lastSeconds); // final flush
    _posSub?.cancel();
    _dragSeconds.dispose();
    _controller.close();
    super.dispose();
  }

  String _fmt(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  void _seek(int seconds) =>
      _controller.seekTo(seconds: seconds.toDouble(), allowSeekAhead: true);

  void _copyTimestamp() {
    Clipboard.setData(
      ClipboardData(text: 'https://youtu.be/${widget.videoId}?t=$_lastSeconds'),
    );
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF0A0A0A),
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: YoutubePlayer(
                  controller: _controller,
                  autoFullScreen: false,
                  enableFullScreenOnVerticalDrag: false,
                ),
              ),
            ),
          ),
        ),
        _studyBar(),
      ],
    );
  }

  Widget _studyBar() {
    return SizedBox(
      height: kVideoStudyBarHeight,
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border:
              Border(top: BorderSide(color: yBorderStrong, width: yLineThin)),
        ),
        padding: const EdgeInsets.only(left: 4, right: 26),
        child: YoutubeValueBuilder(
          controller: _controller,
          builder: (context, value) {
            final playing = value.playerState == PlayerState.playing;
            final total = _controller.metadata.duration.inSeconds;
            return StreamBuilder<Duration>(
              stream: _posStream,
              builder: (context, snap) {
                final pos = snap.data?.inSeconds ?? _lastSeconds;
                return ValueListenableBuilder<double?>(
                  valueListenable: _dragSeconds,
                  builder: (context, drag, _) {
                    final shown = (drag?.round() ?? pos).clamp(0, total);
                    return Row(
                      children: [
                        _primaryBtn(
                          playing ? YuLiIcons.pause : YuLiIcons.play,
                          () => playing
                              ? _controller.pauseVideo()
                              : _controller.playVideo(),
                        ),
                        _skipBtn(YuLiIcons.rotateCcw, () => _seek(pos - 10)),
                        _skipBtn(YuLiIcons.rotateCw, () => _seek(pos + 10)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbColor: widget.accent,
                              activeTrackColor: widget.accent,
                              inactiveTrackColor: yBorderSoft,
                              overlayColor:
                                  widget.accent.withValues(alpha: 0.15),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 11),
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                            ),
                            child: Slider(
                              value: (drag ?? pos.toDouble())
                                  .clamp(0, total == 0 ? 1 : total.toDouble()),
                              min: 0,
                              max: total == 0 ? 1 : total.toDouble(),
                              onChanged: total > 0
                                  ? (v) => _dragSeconds.value = v
                                  : null,
                              onChangeEnd: total > 0
                                  ? (v) {
                                      _seek(v.round());
                                      _dragSeconds.value = null;
                                    }
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_fmt(shown)} / ${_fmt(total)}',
                          style: yMono(
                            size: 9,
                            weight: FontWeight.w700,
                            tracking: 0.4,
                            color: yInk,
                          ),
                        ),
                        _iconBtn(YuLiIcons.copy, _copyTimestamp),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Icon(icon, size: 16, color: yInk),
        ),
      );

  /// Filled accent square (the design's primary play/pause control).
  Widget _primaryBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: widget.accent,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );

  /// Circular skip arrow with a tiny "10" inside (YouTube-style -10/+10).
  Widget _skipBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 20, color: yInk),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '10',
                    style: yMono(
                      size: 6.5,
                      weight: FontWeight.w800,
                      color: yInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
