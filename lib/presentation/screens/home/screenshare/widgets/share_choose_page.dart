import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_button.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'share_dialog_header.dart';
import 'share_summary.dart';
import 'source_thumbnail_grid.dart';

/// The list of windows or screens, with the whole dialog to itself: on a small
/// window it was squeezed in above the settings, and a window could not be told
/// from another.
class ShareChoosePage extends StatelessWidget {
  final ScreenShareSettings settings;
  final bool isLoading;
  final List<CaptureSource>? sources;
  final Map<int, Uint8List> thumbnails;
  final ValueChanged<CaptureSource> onChanged;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final VoidCallback onStart;

  const ShareChoosePage({
    super.key,
    required this.settings,
    required this.isLoading,
    required this.sources,
    required this.thumbnails,
    required this.onChanged,
    required this.onRefresh,
    required this.onBack,
    required this.onClose,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final full = settings.captureFullScreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        ShareDialogHeader(
          title: full ? 'Choose a screen' : 'Choose a window',
          onBack: onBack,
          onRefresh: onRefresh,
          onClose: onClose,
        ),
        Expanded(child: _list(context)),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: Text(
                ShareSummary.quality(settings),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowQuiet.copyWith(color: theme.textTertiary),
              ),
            ),
            AppButton(
              label: 'Start sharing',
              onPressed: settings.selectedVideoSourceIndex == null
                  ? null
                  : onStart,
            ),
          ],
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final theme = context.theme;
    final full = settings.captureFullScreen;
    if (isLoading) {
      return Center(child: LoadingDots(color: theme.accentBright, dotSize: 4));
    }
    final found = sources;
    if (found == null || found.isEmpty) {
      return Center(
        child: Text(
          full ? 'No screens found.' : 'No windows found.',
          style: AppText.body.copyWith(color: theme.textTertiary),
        ),
      );
    }
    return SourceThumbnailGrid(
      sources: found,
      selectedIndex: settings.selectedVideoSourceIndex,
      thumbnails: thumbnails,
      captureFullScreen: full,
      onChanged: onChanged,
    );
  }
}
