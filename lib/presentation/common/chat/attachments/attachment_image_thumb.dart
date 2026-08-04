import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'attachment_image_viewer.dart';
import 'attachment_loader.dart';

/// An image attachment, decrypted on demand and shown as a rounded thumbnail.
/// Tapping opens it full-screen.
///
/// Stateful for one reason: the fetch is started once, in [initState], and
/// held. Kicking it off from `build` instead handed [FutureBuilder] a fresh
/// future every rebuild, which reset it to "waiting" and swapped the image
/// back to a placeholder of a different height — so merely hovering the row
/// resized it, which moved the rows under the pointer, which changed what was
/// hovered. The thrash was a feedback loop, not a slow decrypt.
class AttachmentImageThumb extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const AttachmentImageThumb({
    super.key,
    required this.attachment,
    required this.loader,
    required this.themeState,
  });

  /// Longest edge of a thumbnail in the message list.
  static const double maxSize = 220;

  /// Used only when the sender recorded no dimensions.
  static const double _fallbackHeight = 140;

  /// The box a thumbnail of [width]×[height] occupies, or null when the
  /// sender recorded no dimensions and the thumbnail has to size itself once
  /// the bytes land.
  ///
  /// Scales down to fit [maxSize] on the longest edge, and never up: a 40px
  /// sticker blown out to 220 is a blurry mess, and the design's thumbnails
  /// are a ceiling rather than a target.
  static Size? boxFor(int? width, int? height) {
    final w = width?.toDouble();
    final h = height?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    if (w <= maxSize && h <= maxSize) return Size(w, h);
    // The long edge is set to the ceiling and the short one derived from it,
    // rather than scaling both by a ratio: `w * (maxSize / w)` lands a hair
    // *over* maxSize in floating point, and this box is measured against it.
    return w >= h
        ? Size(maxSize, h * maxSize / w)
        : Size(w * maxSize / h, maxSize);
  }

  @override
  State<AttachmentImageThumb> createState() => _AttachmentImageThumbState();
}

class _AttachmentImageThumbState extends State<AttachmentImageThumb> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.loader(widget.attachment);
  }

  @override
  void didUpdateWidget(AttachmentImageThumb old) {
    super.didUpdateWidget(old);
    // Only a genuinely different attachment re-fetches. A rebuild that merely
    // rebuilt the widget must not.
    if (old.attachment.id != widget.attachment.id ||
        old.loader != widget.loader) {
      _bytes = widget.loader(widget.attachment);
    }
  }

  /// The box the thumbnail occupies, or null when the sender recorded no
  /// dimensions.
  ///
  /// Reserved up front where it can be, so the placeholder and the decoded
  /// image are the same size: otherwise the row jumps the moment the bytes
  /// land, which in a scrolled list drags everything below it.
  Size? get _box => AttachmentImageThumb.boxFor(
    widget.attachment.width,
    widget.attachment.height,
  );

  @override
  Widget build(BuildContext context) {
    final box = _box;
    final content = FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _placeholder(
            box,
            Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.themeState.primary,
                ),
              ),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return _placeholder(
            box,
            Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: widget.themeState.textQuaternary,
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () =>
              showAttachmentImageViewer(context, widget.attachment.name, bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            // `cover` only where the box is known to be the image's own
            // aspect ratio. Without dimensions the box is a guess, and
            // cropping to a guess would cut the picture.
            child: box == null
                ? ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AttachmentImageThumb.maxSize,
                      maxHeight: AttachmentImageThumb.maxSize,
                    ),
                    child: Image.memory(bytes),
                  )
                : Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      },
    );

    if (box == null) return content;
    return SizedBox(width: box.width, height: box.height, child: content);
  }

  /// Sized only when [box] is null — otherwise the caller has already sized
  /// the whole thumbnail and a second size here would fight it.
  Widget _placeholder(Size? box, Widget child) {
    return Container(
      width: box == null ? AttachmentImageThumb.maxSize : null,
      height: box == null ? AttachmentImageThumb._fallbackHeight : null,
      decoration: BoxDecoration(
        color: widget.themeState.bgTertiary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.themeState.borderPrimary),
      ),
      child: child,
    );
  }
}
