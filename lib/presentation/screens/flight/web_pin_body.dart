import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'pin_dialog.dart';
import 'pin_recents.dart';

/// Height of the brutalist nav bar under the WebView. Web pins resize freely, so
/// (unlike the video study bar) this isn't reserved by the clamp — it just lives
/// inside the body Column, taking from the user-set height like the PDF bar.
const double kWebNavBarHeight = 34;

/// Normalizes user input into a loadable URL: trims, prepends `https://` when no
/// scheme is present. Returns null for empty input.
String? normalizeWebUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  return 'https://$t';
}

/// YuLi dialog: type a URL (+ optional title) for a new web pin, or tap a
/// recent. Returns null on cancel / empty link. The URL is normalized.
Future<({String url, String? title})?> promptWebUrl(
  BuildContext context, {
  required Color accent,
}) async {
  final recents = await PinRecents.web();
  if (!context.mounted) return null;
  final urlCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  return showDialog<({String url, String? title})>(
    context: context,
    builder: (ctx) {
      void confirm() {
        final url = normalizeWebUrl(urlCtrl.text);
        if (url == null) {
          Navigator.pop(ctx);
          return;
        }
        final title = titleCtrl.text.trim();
        Navigator.pop(ctx, (url: url, title: title.isEmpty ? null : title));
      }

      return PinDialogShell(
        icon: YuLiIcons.globe,
        title: 'AGREGAR WEB',
        accent: accent,
        footer: Row(
          children: [
            const Spacer(),
            PinGhostButton(label: 'CANCELAR', onTap: () => Navigator.pop(ctx)),
            const SizedBox(width: 6),
            PinPrimaryButton(
              label: 'AGREGAR',
              icon: YuLiIcons.plus,
              accent: accent,
              onTap: confirm,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pinDialogField(
              controller: urlCtrl,
              hint: 'geogebra.org/classic',
              accent: accent,
              autofocus: true,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            pinDialogField(
              controller: titleCtrl,
              hint: 'TÍTULO (OPCIONAL)',
              accent: accent,
            ),
            PinRecentsList(
              recents: recents,
              leadingIcon: YuLiIcons.globe,
              accent: accent,
              onPick: (r) => Navigator.pop(ctx, (url: r.value, title: r.title)),
            ),
          ],
        ),
      );
    },
  );
}

/// Body of a floating web pin: a JS-enabled WebView (GeoGebra, Desmos, a school
/// portal, etc.) plus a brutalist nav bar (back / forward / reload + host). The
/// pin persists the ORIGINAL url like a bookmark; in-page navigation is live but
/// not saved, so reopening returns to a known start. Online-only by nature.
/// Owns the controller so the page survives the window's rebuilds and collapse
/// (the parent's Offstage hides it without unmounting → state, like a half-built
/// GeoGebra construction, is preserved).
class WebPinBody extends StatefulWidget {
  final String url;

  /// Note/folder accent — fills the reload button + the loading line.
  final Color accent;

  const WebPinBody({super.key, required this.url, required this.accent});

  @override
  State<WebPinBody> createState() => _WebPinBodyState();
}

class _WebPinBodyState extends State<WebPinBody> {
  late final WebViewController _controller;
  final ValueNotifier<int> _progress = ValueNotifier(0);
  final ValueNotifier<String> _host = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    _host.value = Uri.tryParse(widget.url)?.host ?? '';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(yCream)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => _progress.value = p,
          onPageStarted: (_) => _progress.value = 0,
          onPageFinished: (url) {
            _progress.value = 100;
            final h = Uri.tryParse(url)?.host;
            if (h != null && h.isNotEmpty) _host.value = h;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _progress.dispose();
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<int>(
                  valueListenable: _progress,
                  builder: (context, p, _) {
                    if (p >= 100) return const SizedBox.shrink();
                    return LinearProgressIndicator(
                      value: p / 100,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: widget.accent,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        _navBar(),
      ],
    );
  }

  Widget _navBar() {
    return SizedBox(
      height: kWebNavBarHeight,
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border:
              Border(top: BorderSide(color: yBorderStrong, width: yLineThin)),
        ),
        padding: const EdgeInsets.only(left: 2, right: 26),
        child: Row(
          children: [
            _primaryBtn(YuLiIcons.refresh, () => _controller.reload()),
            _iconBtn(YuLiIcons.chevronLeft, () async {
              if (await _controller.canGoBack()) _controller.goBack();
            }),
            _iconBtn(YuLiIcons.chevronRight, () async {
              if (await _controller.canGoForward()) _controller.goForward();
            }),
            const SizedBox(width: 4),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _host,
                builder: (context, host, _) => Text(
                  host.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 0.4,
                    color: yMuted,
                  ),
                ),
              ),
            ),
            _iconBtn(YuLiIcons.copy, _copyUrl),
          ],
        ),
      ),
    );
  }

  void _copyUrl() async {
    final url = await _controller.currentUrl() ?? widget.url;
    await Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.selectionClick();
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Icon(icon, size: 16, color: yInk),
        ),
      );

  /// Filled accent square (the design's primary control — reload here).
  Widget _primaryBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: widget.accent,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      );
}
