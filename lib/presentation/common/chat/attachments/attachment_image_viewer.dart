import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/media_colors.dart';
import 'attachment_download.dart';

/// Opens a decrypted image full-screen, pannable and zoomable, with a save
/// button. The bytes are already in memory — nothing is written to disk unless
/// the user asks for it.
Future<void> showAttachmentImageViewer(
  BuildContext context,
  String name,
  Uint8List bytes,
) {
  return showDialog<void>(
    context: context,
    barrierColor: MediaColors.viewerBarrier,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          // The viewer fills the dialog, so the barrier behind it never
          // sees a tap: a click beside the picture has to close it here. The
          // picture keeps its own taps, so clicking it does nothing; a drag
          // or a pinch still pans and zooms, since a tap only wins the
          // gesture when nothing moved.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Image.memory(bytes),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _ViewerActions(
              onSave: () => saveToDisk(context, name, bytes),
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Save and close, on a dark pill of their own.
///
/// White glyphs straight on the picture vanished on a white picture — a
/// screenshot, a chart, a page — which is most of what gets shared. The
/// pill is the same darkness whatever is underneath, so the two buttons
/// read on any image and cost nothing on a dark one.
class _ViewerActions extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onClose;

  const _ViewerActions({required this.onSave, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MediaColors.toolbar,
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.download_rounded,
                color: MediaColors.onMedia,
              ),
              tooltip: 'Save',
              onPressed: onSave,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: MediaColors.onMedia),
              tooltip: 'Close',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
