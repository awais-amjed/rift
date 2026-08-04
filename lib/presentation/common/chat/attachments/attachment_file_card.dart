import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
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
  static const double _width = 260;

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
    return InkWell(
      onTap: _download,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.bgTertiary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.borderPrimary),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 28,
              color: theme.textTertiary,
            ),
            const SizedBox(width: 10),
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
          style: AppText.rowQuiet.copyWith(
            fontSize: 13,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          humanSize(widget.attachment.size),
          // A file's size is a figure — mono keeps a column of cards
          // from having their sizes wander.
          style: AppText.meta.copyWith(color: theme.textQuaternary),
        ),
      ],
    );
  }

  Widget _trailing(ThemeState theme) {
    if (!_busy) {
      return Icon(Icons.download_rounded, size: 20, color: theme.textTertiary);
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary),
    );
  }
}
