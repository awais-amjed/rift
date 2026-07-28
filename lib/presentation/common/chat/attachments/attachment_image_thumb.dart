import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'attachment_image_viewer.dart';
import 'attachment_loader.dart';

/// An image attachment, decrypted on demand and shown as a rounded thumbnail.
/// Tapping opens it full-screen. While the bytes are in flight (or if they
/// can't be fetched) a placeholder of the same footprint holds the layout.
class AttachmentImageThumb extends StatelessWidget {
  static const double _maxSize = 220;
  static const double _placeholderHeight = 140;

  final Attachment attachment;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const AttachmentImageThumb({
    super.key,
    required this.attachment,
    required this.loader,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loader(attachment),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _placeholder(
            Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: themeState.primary,
                ),
              ),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return _placeholder(
            Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: themeState.textQuaternary,
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () =>
              showAttachmentImageViewer(context, attachment.name, bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _maxSize,
                maxHeight: _maxSize,
              ),
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder(Widget child) {
    return Container(
      width: _maxSize,
      height: _placeholderHeight,
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeState.borderPrimary),
      ),
      child: child,
    );
  }
}
