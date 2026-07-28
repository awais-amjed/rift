import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';

/// One picked-but-not-yet-sent attachment: an image preview, or an icon and
/// filename for everything else, with a corner button to drop it again.
class ComposerStagedChip extends StatelessWidget {
  static const double _size = 76;
  static const double _fileChipWidth = 150;

  final PendingAttachment attachment;
  final ThemeState themeState;
  final VoidCallback onRemove;

  const ComposerStagedChip({
    super.key,
    required this.attachment,
    required this.themeState,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.kind == AttachmentKind.image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isImage ? _size : _fileChipWidth,
          height: _size,
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: themeState.borderPrimary),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.memory(attachment.bytes, fit: BoxFit.cover)
              : _fileBody(),
        ),
        Positioned(top: -6, right: -6, child: _removeButton()),
      ],
    );
  }

  Widget _fileBody() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Icon(
            attachment.kind == AttachmentKind.audio
                ? Icons.audiotrack_rounded
                : Icons.insert_drive_file_outlined,
            size: 20,
            color: themeState.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: themeState.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _removeButton() {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        decoration: BoxDecoration(
          color: themeState.bgPrimary,
          shape: BoxShape.circle,
          border: Border.all(color: themeState.borderPrimary),
        ),
        padding: const EdgeInsets.all(2),
        child: Icon(Icons.close, size: 14, color: themeState.textSecondary),
      ),
    );
  }
}
