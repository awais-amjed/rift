import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../common/app_switch.dart';
import '../../../../common/soundboard_volume_control.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// How loud everybody else's clips are **here**.
///
/// At the foot of the picker rather than buried in settings, because the
/// moment somebody wants this is the moment a clip has just gone off. Nothing
/// it changes is sent anywhere: a press is played locally by each listener,
/// so this is the whole of the decision.
class SoundboardListenerControls extends StatelessWidget {
  /// Under a thumb, in a sheet: the row gets the height a finger needs and
  /// the label the size the rest of the sheet is set at.
  final bool compact;

  const SoundboardListenerControls({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = context.select<AppCubit, bool>(
      (cubit) => cubit.state.soundboardMuted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Mute everyone else',
                style: (compact ? AppText.input : AppText.row).copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            AppSwitch(
              value: muted,
              onChanged: context.read<AppCubit>().setSoundboardMuted,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          compact
              ? 'Their clips stop playing here. Yours still do.'
              : 'Their clips stop playing here. Yours still do, and the '
                    'room still hears them.',
          style: AppText.rowQuiet.copyWith(color: theme.textQuaternary),
        ),
        const SizedBox(height: 6),
        const SoundboardVolumeControl(),
      ],
    );
  }
}
