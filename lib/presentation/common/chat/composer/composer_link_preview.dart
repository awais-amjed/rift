import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The preview the composer has built for the link in the field, shown
/// before the message goes so the sender can drop it.
///
/// Sits where the staged attachments do, above the bar, because it is one:
/// something that will travel with the message and can be taken off first.
/// The ✕ sends the link without a preview; it does not remove the link.
class ComposerLinkPreview extends StatelessWidget {
  final PendingLinkPreview preview;
  final VoidCallback onRemove;

  const ComposerLinkPreview({
    super.key,
    required this.preview,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final image = preview.image;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: themeState.bgSecondary,
          borderRadius: BorderRadius.circular(K.radiusCard),
          border: Border.all(color: themeState.borderPrimary),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(K.radiusRow),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.memory(image.bytes, fit: BoxFit.cover),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.siteName ?? Uri.parse(preview.url).host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                  if (preview.title case final title?)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.secondaryStrong.copyWith(
                        color: themeState.textPrimary,
                      ),
                    ),
                  if (preview.description case final description?)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.secondary.copyWith(
                        color: themeState.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Tooltip(
              message: 'Send without preview',
              waitDuration: const Duration(milliseconds: 400),
              child: InkWell(
                borderRadius: BorderRadius.circular(K.radiusPill),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: themeState.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
