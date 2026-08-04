import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../icon_tile.dart';
import 'attachment_download.dart';
import 'attachment_loader.dart';
import '../../../theme/app_text.dart';

/// A non-media attachment: name, size, and a tap to decrypt and save it.
/// The card owns the in-flight state so a slow download shows a spinner in
/// place of the download affordance.
class AttachmentFileCard extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const AttachmentFileCard({
    super.key,
    required this.attachment,
    required this.loader,
    required this.themeState,
  });

  @override
  State<AttachmentFileCard> createState() => _AttachmentFileCardState();
}

class _AttachmentFileCardState extends State<AttachmentFileCard> {
  static const double _width = 270;

  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bytes = await widget.loader(widget.attachment);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) {
      HelperMethods.showError(error: "Couldn't download that file.");
      return;
    }
    if (!mounted) return;
    await saveToDisk(context, widget.attachment.name, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;
    final radius = BorderRadius.circular(K.radiusAttachment);
    return InkWell(
      onTap: _download,
      borderRadius: radius,
      child: Container(
        width: _width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.bgTertiary,
          borderRadius: radius,
          border: Border.all(color: theme.borderElevated),
        ),
        child: Row(
          spacing: 10,
          children: [
            // The glyph sits on its own accent tile rather than loose on the
            // card, which is what makes the card read as a file rather than a
            // row of text with an icon in front of it.
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
          style: AppText.row.copyWith(fontSize: 12.5, color: theme.textPrimary),
        ),
        const SizedBox(height: 1),
        Text(
          humanSize(widget.attachment.size),
          // A file's size is a figure — mono keeps a column of cards
          // from having their sizes wander.
          style: AppText.meta.copyWith(
            fontSize: 10.5,
            color: theme.textQuaternary,
          ),
        ),
      ],
    );
  }

  Widget _trailing(ThemeState theme) {
    if (!_busy) {
      return Icon(Icons.download_rounded, size: 18, color: theme.textTertiary);
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary),
    );
  }
}
