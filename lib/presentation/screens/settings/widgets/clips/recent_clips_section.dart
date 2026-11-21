import 'package:material_ui/material_ui.dart';

import '../../../../../logic/services/call_clip/clip_library.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../../home/call_clip/stored_clip_opener.dart';
import '../../../home/call_clip/widgets/clip_history_list.dart';
import '../section_title.dart';

/// The clips this device keeps (`ClipLibrary`). Shown with clipping off too:
/// what was kept before stays until it is deleted, and this is where it can
/// be, outside a call.
class RecentClipsSection extends StatelessWidget {
  const RecentClipsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Recent clips'),
        const SizedBox(height: 4),
        Text(
          'The last ${ClipLibrary.keep}, kept on this device, sealed with '
          'your account. Open one to trim it again.',
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
        const SizedBox(height: 8),
        ClipHistoryList(onOpen: (clip) => openStoredClip(context, clip)),
      ],
    );
  }
}
