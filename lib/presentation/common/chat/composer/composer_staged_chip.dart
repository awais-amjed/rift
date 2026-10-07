import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

/// One picked-but-not-yet-sent attachment: an image preview, or an icon and
/// filename for everything else, with a corner button to drop it again — and,
/// on a big file, a second one to send it unencrypted.
class ComposerStagedChip extends StatelessWidget {
  static const double _size = 76;
  static const double _fileChipWidth = 150;

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  /// Null where this file cannot be sent unencrypted.
  final VoidCallback? onTogglePlain;

  const ComposerStagedChip({
    super.key,
    required this.attachment,
    required this.onRemove,
    this.onTogglePlain,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // A big picture is held only as a file, so it shows as one: there are no
    // bytes in hand to draw.
    final image = attachment.kind == AttachmentKind.image
        ? attachment.bytes
        : null;
    final isImage = image != null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isImage ? _size : _fileChipWidth,
          height: _size,
          decoration: BoxDecoration(
            color: themeState.bgTertiary,
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(
              color: attachment.plain
                  ? CustomColors.warning
                  : themeState.borderElevated,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.memory(image, fit: BoxFit.cover)
              : _fileBody(context),
        ),
        Positioned(top: -6, right: -6, child: _removeButton(context)),
        if (onTogglePlain != null)
          Positioned(bottom: -6, right: -6, child: _lockButton(context)),
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
            size: K.iconLarge,
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

  Widget _lockButton(BuildContext context) {
    final themeState = context.theme;
    final plain = attachment.plain;
    return Tooltip(
      message: plain
          ? 'Sending unencrypted. Tap to encrypt'
          : 'Send unencrypted. Best for big files that aren\'t private',
      child: _cornerButton(
        context,
        onTap: onTogglePlain!,
        icon: plain ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
        color: plain
            ? themeState.statusInk(CustomColors.warning)
            : themeState.textSecondary,
      ),
    );
  }

  Widget _removeButton(BuildContext context) => _cornerButton(
    context,
    onTap: onRemove,
    icon: Icons.close,
    color: context.theme.textSecondary,
  );

  Widget _cornerButton(
    BuildContext context, {
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
  }) {
    final themeState = context.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
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
          child: Icon(icon, size: K.iconTiny, color: color),
        ),
      ),
    );
  }
}
