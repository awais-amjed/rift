import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../icon_tile.dart';
import '../../loading_dots.dart';
import 'attachment_download.dart';
import 'attachment_loader.dart';

/// A non-media attachment: name, size, and a tap to decrypt and save it.
/// The card owns the in-flight state so a download shows how far it has got
/// in place of the download affordance.
class AttachmentFileCard extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  const AttachmentFileCard({
    super.key,
    required this.attachment,
    required this.loader,
  });

  @override
  State<AttachmentFileCard> createState() => _AttachmentFileCardState();
}

class _AttachmentFileCardState extends State<AttachmentFileCard> {
  static const double _width = 270;

  bool _busy = false;

  /// How far a download has got, 0 to 1. Null before the first piece lands.
  double? _progress;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await saveAttachment(
        context,
        widget.loader,
        widget.attachment,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    // Card outside, ink inside. With the InkWell wrapping the card its hover
    // was painted on whatever Material was under the message row and then
    // covered by the card's own fill, so a control the size of a paragraph
    // gave no sign it was one. The padding moves in with it, so the whole card
    // lights rather than just the strip its contents occupy.
    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: radius,
        border: Border.all(color: theme.borderElevated),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: _download,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              spacing: 10,
              children: [
                // The glyph sits on its own accent tile rather than loose on
                // the card, which is what makes the card read as a file rather
                // than a row of text with an icon in front of it.
                IconTile(
                  icon: Icons.description_outlined,
                  color: theme.accentBright,
                  size: 38,
                  radius: K.radiusRow,
                  iconSize: 19,
                ),
                Expanded(child: _details(theme)),
                _trailing(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(ThemeState theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.attachment.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
        const SizedBox(height: 1),
        Text(
          humanSize(widget.attachment.size),
          // A file's size is a figure — mono keeps a column of cards
          // from having their sizes wander.
          style: AppText.meta.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }

  Widget _trailing(ThemeState theme) {
    if (!_busy) {
      return Icon(
        Icons.download_rounded,
        size: K.iconButton,
        color: theme.textTertiary,
      );
    }
    final progress = _progress;
    if (progress == null) return LoadingDots(color: theme.primary, dotSize: 4);
    return Text(
      '${(progress * 100).floor()}%',
      style: AppText.figure.copyWith(color: theme.textSecondary),
    );
  }
}
