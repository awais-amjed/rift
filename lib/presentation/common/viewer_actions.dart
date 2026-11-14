import 'package:material_ui/material_ui.dart';

import '../../data/constants.dart';
import '../theme/media_colors.dart';

/// Save and close, on a dark pill of their own, at the corner of a picture
/// or video opened in the window ([showImageViewer], `VideoViewerPage`).
///
/// White glyphs straight on the picture vanished on a white picture — a
/// screenshot, a chart, a page — which is most of what gets shared. The
/// pill is the same darkness whatever is underneath, so the two buttons
/// read on any image and cost nothing on a dark one.
class ViewerActions extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onClose;

  /// In place of the arrow while a save is on its way: how far it has got.
  final Widget? saving;

  const ViewerActions({
    super.key,
    required this.onSave,
    required this.onClose,
    this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MediaColors.toolbar,
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon:
                  saving ??
                  const Icon(
                    Icons.download_rounded,
                    color: MediaColors.onMedia,
                  ),
              tooltip: 'Save',
              onPressed: onSave,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: MediaColors.onMedia),
              tooltip: 'Close',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
