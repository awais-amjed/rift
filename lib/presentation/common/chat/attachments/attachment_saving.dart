import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/media_colors.dart';
import '../../../theme/theme_context.dart';
import '../../loading_dots.dart';
import 'attachment_download.dart';
import 'attachment_loader.dart';

/// Saving an attachment from a card that shows how far it has got: the file
/// card, and the audio card's save button.
mixin AttachmentSaving<T extends StatefulWidget> on State<T> {
  bool savingNow = false;

  /// How far a download has got, 0 to 1. Null before the first piece lands.
  double? saveProgress;

  Future<void> saveFile(AttachmentLoader loader, Attachment attachment) async {
    if (savingNow) return;
    setState(() => savingNow = true);
    try {
      await saveAttachment(
        context,
        loader,
        attachment,
        onProgress: (p) {
          if (mounted) setState(() => saveProgress = p);
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          savingNow = false;
          saveProgress = null;
        });
      }
    }
  }
}

/// The download arrow, or how far a save has got in its place.
class SaveProgressGlyph extends StatelessWidget {
  final bool busy;
  final double? progress;

  /// Drawn over a video, which is dark whatever the theme.
  final bool onMedia;

  const SaveProgressGlyph({
    super.key,
    required this.busy,
    this.progress,
    this.onMedia = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final progress = this.progress;
    if (!busy) {
      return Icon(
        Icons.download_rounded,
        size: K.iconButton,
        color: onMedia ? MediaColors.onMedia : theme.textTertiary,
      );
    }
    if (progress == null) {
      return LoadingDots(
        color: onMedia ? MediaColors.onMedia : theme.primary,
        dotSize: 4,
      );
    }
    return Text(
      '${(progress * 100).floor()}%',
      style: AppText.figure.copyWith(
        color: onMedia ? MediaColors.onMedia : theme.textSecondary,
      ),
    );
  }
}
