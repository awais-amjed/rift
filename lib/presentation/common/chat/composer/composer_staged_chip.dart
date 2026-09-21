import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// One picked-but-not-yet-sent attachment: an image preview, or an icon and
/// filename for everything else, with a corner button to drop it again.
class ComposerStagedChip extends StatelessWidget {
  static const double _size = 76;
  static const double _fileChipWidth = 150;

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  const ComposerStagedChip({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final isImage = attachment.kind == AttachmentKind.image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isImage ? _size : _fileChipWidth,
          height: _size,
          decoration: BoxDecoration(
            color: themeState.bgTertiary,
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(color: themeState.borderElevated),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.memory(attachment.bytes, fit: BoxFit.cover)
              : _fileBody(context),
        ),
        Positioned(top: -6, right: -6, child: _removeButton(context)),
      ],
    );
  }

  Widget _fileBody(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            attachment.kind == AttachmentKind.audio
                ? Icons.audiotrack_rounded
                : Icons.description_outlined,
            size: 20,
            color: themeState.textTertiary,
          ),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w400,
                height: 1.4,
                color: themeState.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _removeButton(BuildContext context) {
    final themeState = context.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onRemove,
        child: Container(
          width: 20,
          height: 20,
          // The elevated surface, not the canvas: the button overhangs the chip
          // and has to read as sitting on top of it rather than punched through.
          decoration: BoxDecoration(
            color: themeState.bgElevated,
            shape: BoxShape.circle,
            border: Border.all(color: themeState.borderElevated),
          ),
          child: Icon(Icons.close, size: 12, color: themeState.textSecondary),
        ),
      ),
    );
  }
}
