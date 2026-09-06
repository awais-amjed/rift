import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../theme/app_motion.dart';
import 'attachment_image_viewer.dart';
import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/image_safety.dart';
import '../../../../logic/services/image_safety_classifier.dart';
import 'attachment_loader.dart';
import 'sensitive_image_cover.dart';
import '../../../../data/constants.dart';
import '../../../theme/theme_context.dart';

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
  const AttachmentImageThumb({
    super.key,
    required this.attachment,
    required this.loader,
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

/// The bytes, and what the classifier made of them — null where it was not
/// asked, could not answer, or the setting is off.
typedef _Loaded = ({Uint8List? bytes, ImageSafetyVerdict? verdict});

class _AttachmentImageThumbState extends State<AttachmentImageThumb> {
  late Future<_Loaded> _loaded;

  /// Read once, when the fetch starts. The verdict is decided with the bytes
  /// rather than at draw time, because the classifier is the slow part and
  /// the placeholder is already up: the picture should land classified, not
  /// land and then be covered a beat later.
  late SensitiveContentMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = context.read<AppCubit>().state.sensitiveContentMode;
    _loaded = _load();
  }

  @override
  void didUpdateWidget(AttachmentImageThumb old) {
    super.didUpdateWidget(old);
    // Only a genuinely different attachment re-fetches. A rebuild that merely
    // rebuilt the widget must not.
    if (old.attachment.id != widget.attachment.id ||
        old.loader != widget.loader) {
      _loaded = _load();
    }
  }

  Future<_Loaded> _load() async {
    final bytes = await widget.loader(widget.attachment);
    if (bytes == null || _mode == SensitiveContentMode.off) {
      return (bytes: bytes, verdict: null);
    }
    final verdict = await ImageSafetyClassifier.instance.classify(
      widget.attachment.id,
      bytes,
    );
    return (bytes: bytes, verdict: verdict);
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
    final content = FutureBuilder<_Loaded>(
      future: _loaded,
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
                  color: context.theme.primary,
                ),
              ),
            ),
          );
        }
        final bytes = snap.data?.bytes;
        if (bytes == null) {
          return _placeholder(
            box,
            Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: context.theme.textQuaternary,
              ),
            ),
          );
        }
        // Faded up from the placeholder rather than swapped for it. An
        // attachment is decrypted and decoded before it can be shown, so the
        // swap lands at an unpredictable moment — and a picture appearing
        // instantly mid-scroll reads as a glitch rather than as a load
        // finishing.
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(K.radiusCard),
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
        );
        // The cover goes *inside* the tap: a covered picture opens nothing
        // until it is revealed, and a hidden one never does.
        final sensitive = snap.data?.verdict?.isSensitive ?? false;
        return _FadeIn(
          child: sensitive
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(K.radiusCard),
                  child: SensitiveImageCover(
                    attachmentId: widget.attachment.id,
                    mode: _mode,
                    child: _Openable(
                      bytes: bytes,
                      name: widget.attachment.name,
                      child: image,
                    ),
                  ),
                )
              : _Openable(
                  bytes: bytes,
                  name: widget.attachment.name,
                  child: image,
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
        color: context.theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: context.theme.borderPrimary),
      ),
      child: child,
    );
  }
}

/// A tap opens the full-size viewer.
class _Openable extends StatelessWidget {
  final Uint8List bytes;
  final String name;
  final Widget child;

  const _Openable({
    required this.bytes,
    required this.name,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showAttachmentImageViewer(context, name, bytes),
    child: child,
  );
}

/// Fades its child up once, on first build.
///
/// Deliberately one-shot: the tween's end value never changes, so a rebuild
/// for any other reason — the row re-laying out, a theme change — cannot
/// replay it and make a picture already on screen flicker.
class _FadeIn extends StatelessWidget {
  final Widget child;

  const _FadeIn({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.enter,
      curve: AppMotion.settle,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }
}
