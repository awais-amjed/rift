import 'dart:typed_data';

import 'package:flutter/material.dart';

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
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          InteractiveViewer(child: Center(child: Image.memory(bytes))),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  tooltip: 'Save',
                  onPressed: () => saveToDisk(context, name, bytes),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
