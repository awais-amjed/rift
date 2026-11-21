import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/classes/attachment.dart';
import '../../../data/classes/link_preview.dart';
import '../../../data/constants.dart';
import '../../../data/enums/sensitive_content_mode.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/media/media_cubit.dart';
import '../../../logic/services/image_safety.dart';
import '../../../logic/services/image_safety_classifier.dart';
import '../../../logic/services/open_link.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';
import 'attachments/attachment_loader.dart';
import 'attachments/sensitive_image_cover.dart';

/// The sender's preview of a link, under their message: site, title, a line
/// or two, and the thumbnail they captured. Tapping opens the link.
///
/// Draws only what arrived inside the message. The thumbnail is one of the
/// message's encrypted blobs, fetched through the same [AttachmentLoader]
/// as a photo; the page itself is never asked for anything.
class LinkPreviewCard extends StatelessWidget {
  final LinkPreview preview;
  final AttachmentLoader? loader;

  const LinkPreviewCard({super.key, required this.preview, this.loader});

  static const double maxWidth = 420;
  static const double thumbnailHeight = 160;

  Future<void> _open() async {
    await openExternalLink(preview.url);
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final image = preview.image;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: themeState.bgSecondary,
          borderRadius: BorderRadius.circular(K.radiusCard),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(K.radiusCard),
            onTap: _open,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(K.radiusCard),
                border: Border.all(color: themeState.borderPrimary),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (image != null && loader != null)
                    _Thumbnail(image: image, loader: loader!),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview.siteName ?? preview.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(
                            color: themeState.textTertiary,
                          ),
                        ),
                        if (preview.title case final title?) ...[
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.strong.copyWith(
                              color: themeState.textPrimary,
                            ),
                          ),
                        ],
                        if (preview.description case final description?) ...[
                          const SizedBox(height: 3),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.secondary.copyWith(
                              color: themeState.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The captured picture, once its bytes are decrypted and looked at;
/// nothing while they are on the way, so the card does not jump.
///
/// Looked at by the same on-device model as a picture sent in a message, and
/// covered the same way: the sender chose this picture as surely as one they
/// attached, and a page's own picture went past the setting uncovered
/// (review, Nov 22).
///
/// Stateful to ask [MediaCubit] once, when it appears, and to run the model
/// once for the bytes; those are read from there, so a failed download is
/// retried like any other picture.
class _Thumbnail extends StatefulWidget {
  final Attachment image;
  final AttachmentLoader loader;

  const _Thumbnail({required this.image, required this.loader});

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  /// Read once, as a message picture's thumbnail reads it.
  late SensitiveContentMode _mode;
  Future<ImageSafetyVerdict?>? _verdict;
  Uint8List? _verdictFor;

  String get _key => widget.loader.keyOf(widget.image);

  @override
  void initState() {
    super.initState();
    _mode = context.read<AppCubit>().state.sensitiveContentMode;
    _want();
  }

  @override
  void didUpdateWidget(_Thumbnail old) {
    super.didUpdateWidget(old);
    if (old.loader.keyOf(old.image) != _key) _want();
  }

  void _want() {
    final image = widget.image;
    final loader = widget.loader;
    context.read<MediaCubit>().want(
      MediaKind.attachment,
      _key,
      () => loader(image),
    );
  }

  Future<ImageSafetyVerdict?> _verdictOf(Uint8List bytes) {
    if (!identical(bytes, _verdictFor) || _verdict == null) {
      _verdictFor = bytes;
      _verdict = ImageSafetyClassifier.instance.classify(_key, bytes);
    }
    return _verdict!;
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<MediaCubit, MediaState, Uint8List?>(
      selector: (state) => state.bytes(MediaKind.attachment, _key),
      builder: (context, bytes) {
        if (bytes == null) return const SizedBox.shrink();
        if (_mode == SensitiveContentMode.off) return _picture(bytes, null);
        final known = ImageSafetyClassifier.instance.cached(_key);
        if (known != null) return _picture(bytes, known);
        return FutureBuilder<ImageSafetyVerdict?>(
          future: _verdictOf(bytes),
          builder: (context, verdict) =>
              verdict.connectionState == ConnectionState.done
              ? _picture(bytes, verdict.data)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _picture(Uint8List bytes, ImageSafetyVerdict? verdict) {
    final image = Image.memory(bytes, fit: BoxFit.cover);
    return SizedBox(
      height: LinkPreviewCard.thumbnailHeight,
      width: double.infinity,
      child: (verdict?.isSensitive ?? false)
          ? SensitiveImageCover(attachmentId: _key, mode: _mode, child: image)
          : image,
    );
  }
}
