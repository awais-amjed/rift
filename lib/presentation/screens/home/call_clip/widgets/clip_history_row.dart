import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/stored_clip.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/services/conversation_time.dart';
import '../../../../common/row_delete_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One kept clip: when, how long, and where it was taken. A press opens it in
/// the trim view; the bin deletes it.
class ClipHistoryRow extends StatelessWidget {
  final StoredClip clip;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const ClipHistoryRow({
    super.key,
    required this.clip,
    required this.onOpen,
    required this.onDelete,
  });

  /// `m:ss`: a clip is a whole length, the nearest second.
  static String lengthLabel(Duration d) {
    final seconds = (d.inMilliseconds / 1000).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: radius,
      hoverColor: theme.bgHover,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${formatMessageMoment(clip.at, DateTime.now())} · '
                    '${lengthLabel(clip.duration)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(color: theme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    clip.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(color: theme.textTertiary),
                  ),
                ],
              ),
            ),
            RowDeleteButton(tooltip: 'Delete clip', onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}
