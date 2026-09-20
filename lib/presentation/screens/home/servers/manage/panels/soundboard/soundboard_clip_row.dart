import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/soundboard_sound.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../../../logic/services/byte_format.dart';
import '../../../../../../../logic/services/soundboard_staging.dart';
import '../../../../../../common/quiet_danger_button.dart';
import '../../../../../../theme/app_text.dart';
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
          const SizedBox(width: 4),
          QuietDangerButton(
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            onTap: busy ? null : onRemove,
          ),
        ],
      ),
    );
  }
}
