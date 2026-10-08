import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/media_entry.dart';
import '../../../../data/constants.dart';
import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/media/media_cubit.dart';
import '../../../../logic/services/image_safety.dart';
import '../../../../logic/services/image_safety_classifier.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';
import '../../loading_dots.dart';
import 'attachment_image_viewer.dart';
import 'attachment_loader.dart';
import 'sensitive_image_cover.dart';

/// Over the widget budget and one job: an image attachment — fetch once, size,
/// cover if sensitive, open on tap.
///
/// An image attachment, decrypted on demand and shown as a rounded thumbnail.
/// Tapping opens it full-screen.
///
/// The bytes come from [MediaCubit], asked once in [initState], so every
/// place showing this attachment shows the same thing and a failed download
/// is retried for all of them. The classifier's verdict is the one thing held
/// here, and started once per set of bytes: starting it from `build` handed
/// [FutureBuilder] a fresh future every rebuild, which reset it to "waiting"
/// and swapped the image back to a placeholder of a different height — so
/// merely hovering the row resized it, which moved the rows under the
/// pointer, which changed what was hovered.
class AttachmentImageThumb extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  const AttachmentImageThumb({
    super.key,
    required this.attachment,
    required this.loader,
  });

  /// The most room a picture takes in the message list: about a link
  /// preview's width, so the two read as the same size of thing. At 220 on
  /// the long edge, a screenshot was too small to read without opening it.
  static const double maxWidth = 440;

  /// Lower than [maxWidth], so a tall phone screenshot doesn't fill the
  /// whole pane.
  static const double maxHeight = 340;

  /// Used only when the sender recorded no dimensions.
  static const double _fallbackHeight = 200;

  /// The box a thumbnail of [width]×[height] occupies, or null when the
  /// sender recorded no dimensions and the thumbnail has to size itself once
  /// the bytes land.
  ///
  /// Scales down to fit [maxWidth]×[maxHeight], and [within] — the width the
  /// message has, on a narrow window or a phone — and never up: a 40px
  /// sticker blown out is a blurry mess, and the ceiling is not a target.
  static Size? boxFor(int? width, int? height, {double within = maxWidth}) {
    final w = width?.toDouble();
    final h = height?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    final maxW = within < maxWidth ? within : maxWidth;
    if (w <= maxW && h <= maxHeight) return Size(w, h);
    // The limiting edge is set to its ceiling and the other derived from
    // it, rather than scaling both by a ratio: `w * (maxW / w)` lands a hair
    // *over* maxW in floating point, and this box is measured against it.
    return w / maxW >= h / maxHeight
        ? Size(maxW, h * maxW / w)
        : Size(w * maxHeight / h, maxHeight);
  }

  @override
  State<AttachmentImageThumb> createState() => _AttachmentImageThumbState();
}

class _AttachmentImageThumbState extends State<AttachmentImageThumb> {
  /// What the classifier made of [_verdictFor] — null where it could not
  /// answer or the setting is off.
  Future<ImageSafetyVerdict?>? _verdict;
  Uint8List? _verdictFor;

  /// Read once, when the fetch starts. The verdict is decided with the bytes
  /// rather than at draw time, because the classifier is the slow part and
  /// the placeholder is already up: the picture should land classified, not
  /// land and then be covered a beat later.
  late SensitiveContentMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = context.read<AppCubit>().state.sensitiveContentMode;
    _want();
  }

  @override
  void didUpdateWidget(AttachmentImageThumb old) {
    super.didUpdateWidget(old);
    if (old.attachment.id != widget.attachment.id ||
        old.loader != widget.loader) {
      _want();
    }
  }

  void _want() {
    final attachment = widget.attachment;
    final loader = widget.loader;
    context.read<MediaCubit>().want(
      MediaKind.attachment,
      attachment.storagePath,
      () => loader(attachment),
    );
  }

  /// The classifier's verdict on [bytes], started once for each new set.
  Future<ImageSafetyVerdict?> _verdictOf(Uint8List bytes) {
    if (!identical(bytes, _verdictFor) || _verdict == null) {
      _verdictFor = bytes;
      _verdict = ImageSafetyClassifier.instance.classify(
        widget.attachment.id,
        bytes,
      );
    }
    return _verdict!;
  }

  /// The box the thumbnail occupies, or null when the sender recorded no
  /// dimensions.
  ///
  /// Reserved up front where it can be, so the placeholder and the decoded
  /// image are the same size: otherwise the row jumps the moment the bytes
  /// land, which in a scrolled list drags everything below it.
  Size? _boxWithin(double within) => AttachmentImageThumb.boxFor(
    widget.attachment.width,
    widget.attachment.height,
    within: within,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _build(context, _boxWithin(constraints.maxWidth)),
    );
  }

  Widget _build(BuildContext context, Size? box) {
    final content = BlocSelector<MediaCubit, MediaState, MediaEntry?>(
      selector: (state) =>
          state.entry(MediaKind.attachment, widget.attachment.storagePath),
      builder: (context, entry) {
        final bytes = entry?.bytes;
        if (entry?.status == MediaStatus.failure) {
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
        if (bytes == null) return _loading(box);
        if (_mode == SensitiveContentMode.off) {
          return _picture(box, bytes, null);
        }
        final known = ImageSafetyClassifier.instance.cached(
          widget.attachment.id,
        );
        if (known != null) return _picture(box, bytes, known);
        return FutureBuilder<ImageSafetyVerdict?>(
          future: _verdictOf(bytes),
          builder: (context, verdict) =>
              verdict.connectionState == ConnectionState.done
              ? _picture(box, bytes, verdict.data)
              : _loading(box),
        );
      },
    );

    if (box == null) return content;
    return SizedBox(width: box.width, height: box.height, child: content);
  }

  Widget _loading(Size? box) => _placeholder(
    box,
    Center(child: LoadingDots(color: context.theme.primary, dotSize: 4)),
  );

  Widget _picture(Size? box, Uint8List bytes, ImageSafetyVerdict? verdict) {
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
                maxWidth: AttachmentImageThumb.maxWidth,
                maxHeight: AttachmentImageThumb.maxHeight,
              ),
              child: Image.memory(bytes),
            )
          : Image.memory(bytes, fit: BoxFit.cover),
    );
    // The cover goes *inside* the tap: a covered picture opens nothing
    // until it is revealed, and a hidden one never does.
    final sensitive = verdict?.isSensitive ?? false;
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
          : _Openable(bytes: bytes, name: widget.attachment.name, child: image),
    );
  }

  /// Sized only when [box] is null — otherwise the caller has already sized
  /// the whole thumbnail and a second size here would fight it.
  Widget _placeholder(Size? box, Widget child) {
    return Container(
      width: box == null ? AttachmentImageThumb.maxWidth : null,
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
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () => showAttachmentImageViewer(context, name, bytes),
      child: child,
    ),
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
