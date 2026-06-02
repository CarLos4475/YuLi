import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_tokens.dart';
import '../../providers/image_storage_providers.dart';
import '../../../data/services/image_storage.dart';

/// Read-only browser of the images stored by the app (note_images folder).
/// Lets the user see what occupies space and which note each image belongs to.
class ImageStorageScreen extends ConsumerWidget {
  const ImageStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(allNoteImagesProvider);
    final bytesAsync = ref.watch(imageStorageBytesProvider);
    final ink = inkColor(context);
    final paper = paperColor(context);

    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              color: ink,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.arrow_back, size: 20, color: paper),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'IMÁGENES',
                    style: labelBold.copyWith(
                        color: paper, letterSpacing: 1.5, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    bytesAsync.maybeWhen(
                      data: humanBytes,
                      orElse: () => '…',
                    ),
                    style: labelBold.copyWith(
                        color: paper, fontSize: 12, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            Container(height: borderWidthHeavy, color: ink),
            Expanded(
              child: imagesAsync.when(
                loading: () => Center(
                  child: SizedBox(
                    width: 16,
                    height: borderWidth,
                    child: Container(color: inkGray.withAlpha(80)),
                  ),
                ),
                error: (e, _) => Center(
                  child: Text('No se pudo leer las imágenes',
                      style: bodyM.copyWith(color: ink)),
                ),
                data: (images) {
                  if (images.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No hay imágenes guardadas.',
                          textAlign: TextAlign.center,
                          style: bodyM.copyWith(color: inkGray),
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 150,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: images.length,
                    itemBuilder: (context, i) =>
                        _ImageTile(item: images[i], ink: ink, paper: paper),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final StoredImage item;
  final Color ink;
  final Color paper;
  const _ImageTile(
      {required this.item, required this.ink, required this.paper});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: ink, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Image.file(
              File(item.path),
              fit: BoxFit.cover,
              cacheWidth: 300,
              errorBuilder: (_, _, _) => Container(
                color: inkGray.withAlpha(30),
                child: Icon(Icons.broken_image_outlined,
                    size: 24, color: inkGray),
              ),
            ),
          ),
          Container(height: borderWidth, color: ink),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyS.copyWith(
                      color: ink, fontWeight: FontWeight.w600, fontSize: 10),
                ),
                const SizedBox(height: 1),
                Text(
                  humanBytes(item.sizeBytes),
                  style: labelBold.copyWith(
                      color: inkGray, fontSize: 9, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
