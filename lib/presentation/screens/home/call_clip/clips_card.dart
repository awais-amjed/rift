import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/stored_clip.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/clip_history/clip_history_cubit.dart';
import '../../../../logic/services/call_clip/clip_notice_rules.dart';
import '../../../common/app_button.dart';
import '../../../common/confirm_dialog.dart';
import '../../../common/popover_surface.dart';
import '../../../common/row_delete_button.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/clip_history_list.dart';

/// The Clips card, opened from the call's control bar (`ClipsButton`): clip
/// the call without the shortcut, which not everybody has set, and the clips
/// this device keeps (CALLS.md, *Clipping a call*).
///
/// With clipping off, the top is the setting's own switch rather than a
/// button that only says no, with the line the settings carry: the call is
/// told. Turning it on keeps nothing from before, by design.
class ClipsCard extends StatelessWidget {
  /// Clip the call, as the shortcut does. The button closes the card first,
  /// so the trim view opens over the call.
  final VoidCallback onClip;

  /// Open a kept clip in the trim view, the card closed first.
  final void Function(StoredClip clip) onOpen;

  const ClipsCard({super.key, required this.onClip, required this.onOpen});

  static const double width = 320;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final app = context.read<AppCubit>();
    final on = context.select<AppCubit, bool>((c) => c.state.clippingEnabled);
    final seconds = context.select<AppCubit, int>((c) => c.state.clipSeconds);
    final any = context.select<ClipHistoryCubit, bool>(
      (c) => c.state.clips.isNotEmpty,
    );
    final note = AppText.secondary.copyWith(color: theme.textTertiary);

    return PopoverSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CLIPS',
                  style: AppText.sectionLabel.copyWith(
                    color: theme.textTertiary,
                  ),
                ),
              ),
              if (any)
                RowDeleteButton(
                  tooltip: 'Delete all clips',
                  icon: Icons.delete_sweep_outlined,
                  onPressed: () => _deleteAll(context),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (on)
            AppButton(
              label: 'Clip the last ${clipSpanText(seconds)}',
              icon: const Icon(Icons.content_cut_rounded, size: K.iconButton),
              onPressed: () {
                Navigator.of(context).pop();
                onClip();
              },
            )
          else ...[
            Text('Clipping is off.', style: note),
            const SizedBox(height: 4),
            Text(
              'People in the call see that you have clipping on.',
              style: note,
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Turn on clipping',
              variant: AppButtonVariant.secondary,
              icon: const Icon(Icons.content_cut_rounded, size: K.iconButton),
              onPressed: () => app.setClippingEnabled(true),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: theme.borderElevated),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: ClipHistoryList(
                onOpen: (clip) {
                  Navigator.of(context).pop();
                  onOpen(clip);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context) async {
    final history = context.read<ClipHistoryCubit>();
    final sure = await showConfirmDialog(
      context: context,
      title: 'Delete all clips?',
      message:
          'The clips kept on this device go for good. Clips you saved '
          'or put on a soundboard stay.',
      confirmLabel: 'Delete all',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (sure) await history.deleteAll();
  }
}
