import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// What a pinned message carries besides its words: the first file's name and
/// how many more there are.
///
/// Names, never thumbnails. A picture would have to be fetched, decrypted and
/// checked by the image filter for every pin in the list before the list
/// could be read — and it is one press from the message, where all of that
/// already happens.
class PinnedAttachmentsLine extends StatelessWidget {
  final List<Attachment> attachments;

  const PinnedAttachmentsLine({super.key, required this.attachments});

  static IconData _iconFor(AttachmentKind kind) => switch (kind) {
    AttachmentKind.image => Icons.image_outlined,
    AttachmentKind.audio => Icons.graphic_eq_rounded,
    AttachmentKind.file => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final first = attachments.first;
    final more = attachments.length - 1;
    final style = AppText.secondary.copyWith(color: themeState.textTertiary);
    return Row(
      spacing: 6,
      children: [
        Icon(
          _iconFor(first.kind),
          size: K.iconInline,
          color: themeState.textTertiary,
        ),
        Flexible(
          child: Text(
            first.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (more > 0) Text('+$more more', style: style),
      ],
    );
  }
}
