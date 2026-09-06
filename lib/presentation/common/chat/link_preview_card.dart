import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/classes/link_preview.dart';
import '../../../data/constants.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';
import 'attachments/attachment_loader.dart';

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
    final uri = Uri.tryParse(preview.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                    _Thumbnail(future: loader!(image)),
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

/// The captured picture, once its bytes are decrypted; nothing while they
/// are on the way, so the card does not jump.
class _Thumbnail extends StatelessWidget {
  final Future<Uint8List?> future;

  const _Thumbnail({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return const SizedBox.shrink();
        return SizedBox(
          height: LinkPreviewCard.thumbnailHeight,
          width: double.infinity,
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      },
    );
  }
}
