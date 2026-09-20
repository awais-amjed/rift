import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/soundboard_sound.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../../../logic/services/byte_format.dart';
import '../../../../../../../logic/services/soundboard_staging.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/custom_colors.dart';
import '../../../../../../theme/theme_context.dart';

/// One clip in the manage list: what it is, and the two things that can be
/// done to it.
///
/// Preview plays it **here only**, through the same path a listener takes —
/// nothing is sent to the room. Adding a clip without being able to hear it
/// first is how a server ends up with three airhorns and no idea which is
/// which.
class SoundboardClipRow extends StatelessWidget {
  final SoundboardSound sound;
  final bool busy;
  final VoidCallback onRemove;

  const SoundboardClipRow({
    super.key,
    required this.sound,
    required this.busy,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final author = sound.createdBy == null
        ? null
        : context
              .watch<ServerMembersCubit>()
              .state
              .byId[sound.createdBy]
              ?.displayName;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              sound.emoji ?? '♪',
              style: AppText.row.copyWith(
                color: sound.emoji == null
                    ? theme.textQuaternary
                    : theme.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sound.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(color: theme.textPrimary),
                ),
                Text(
                  [
                    SoundboardStaging.durationLabel(sound.duration),
                    humanSize(sound.bytes),
                    if (author != null) 'added by $author',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowQuiet.copyWith(color: theme.textQuaternary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Play it here',
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            color: theme.textSecondary,
            onPressed: () => context.read<SoundboardCubit>().preview(sound),
          ),
          // An icon, not a button with a word on it. `QuietDangerButton` is
          // sized to be one option among several in a stacked list; in a
          // dense row it is a slab of red beside a bare glyph, and it reads
          // as the point of the row rather than as the thing you reach for
          // once. The weight this action needs is carried by the
          // confirmation it opens, not by the control that opens it.
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            color: theme.textTertiary,
            hoverColor: CustomColors.error.withValues(alpha: 0.10),
            // Red on approach rather than at rest: enough to say what it
            // does before it is pressed, quiet enough to stay in a list.
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? CustomColors.error
                    : theme.textTertiary,
              ),
            ),
            onPressed: busy ? null : onRemove,
          ),
        ],
      ),
    );
  }
}
