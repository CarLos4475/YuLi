import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

/// Bottom panel to insert an image onto the drawing canvas. Shows recent
/// device photos (via photo_manager) plus Gallery / Camera buttons
/// (image_picker). Returns a ready-to-copy, compressed [File] through [onPick].
class ImageInsertPanel extends StatefulWidget {
  final Color accent;
  final void Function(File readyFile) onPick;
  final VoidCallback onClose;

  const ImageInsertPanel({
    super.key,
    required this.accent,
    required this.onPick,
    required this.onClose,
  });

  @override
  State<ImageInsertPanel> createState() => _ImageInsertPanelState();
}

class _ImageInsertPanelState extends State<ImageInsertPanel> {
  List<AssetEntity> _recent = const [];
  bool _loading = true;
  bool _permDenied = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) setState(() => _permDenied = true);
      if (mounted) setState(() => _loading = false);
      return;
    }
    final filter = FilterOptionGroup(
      orders: [
        const OrderOption(
          type: OrderOptionType.createDate,
          asc: false,
        ),
      ],
    );
    final assets = await PhotoManager.getAssetListPaged(
      page: 0,
      pageCount: 40,
      filterOption: filter,
      type: RequestType.image,
    );
    if (mounted) {
      setState(() {
        _recent = assets;
        _loading = false;
      });
    }
  }

  Future<File?> _compressToTemp(String srcPath) async {
    final tmp = await getTemporaryDirectory();
    final dest = p.join(tmp.path, '${const Uuid().v4()}.jpg');
    final out = await FlutterImageCompress.compressAndGetFile(
      srcPath,
      dest,
      quality: 80,
      minWidth: 1920,
      minHeight: 1920,
    );
    return out == null ? null : File(out.path);
  }

  Future<void> _pickFromAsset(AssetEntity asset) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await asset.file;
      if (file == null) return;
      final ready = await _compressToTemp(file.path);
      if (ready != null) widget.onPick(ready);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromPicker(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (x != null) widget.onPick(File(x.path));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('INSERTAR IMAGEN',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted,
                  )),
              const Spacer(),
              _action(YuLiIcons.images, 'GALERÍA',
                  () => _pickFromPicker(ImageSource.gallery)),
              const SizedBox(width: 6),
              _action(YuLiIcons.camera, 'CÁMARA',
                  () => _pickFromPicker(ImageSource.camera)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 220, child: _grid()),
        ],
      ),
    );
  }

  Widget _grid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: yInk));
    }
    if (_permDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'SIN ACCESO A FOTOS\nUsá GALERÍA o CÁMARA arriba',
            textAlign: TextAlign.center,
            style: yMono(
                size: 10, weight: FontWeight.w700, tracking: 1.2, color: yMuted),
          ),
        ),
      );
    }
    if (_recent.isEmpty) {
      return Center(
        child: Text('SIN FOTOS RECIENTES',
            style: yMono(
                size: 10, weight: FontWeight.w700, tracking: 1.2, color: yMuted)),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _recent.length,
      itemBuilder: (_, i) => _Thumb(
        asset: _recent[i],
        onTap: () => _pickFromAsset(_recent[i]),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: yInk),
            const SizedBox(width: 5),
            Text(label,
                style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: yInk)),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;
  const _Thumb({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: yBorderStrong, width: 1)),
        child: FutureBuilder(
          future: asset.thumbnailDataWithSize(const ThumbnailSize.square(220)),
          builder: (_, snap) {
            if (snap.data == null) {
              return Container(color: yCream2);
            }
            return Image.memory(snap.data!, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }
}
