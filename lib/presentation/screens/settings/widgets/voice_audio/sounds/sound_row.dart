import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/participant_setting.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/app_sound.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/services/sound_service.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../common/volume_slider.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One of Rift's sounds: whether it plays, and how loud.
///
/// Moving the slider plays the cue at the level it is moving through. A
/// volume for a sound you cannot hear while choosing it is a number, and the
/// only way to tell whether 40% is too quiet is to listen to 40%.
class SoundRow extends StatelessWidget {
  final AppSound sound;
  final ParticipantSetting setting;

  const SoundRow({super.key, required this.sound, required this.setting});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final cubit = context.read<AppCubit>();
    final muted = setting.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sound.label,
                    style: AppText.row.copyWith(color: theme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sound.description,
                    style: AppText.secondary.copyWith(
                      color: theme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Play',
              onPressed: muted
                  ? null
                  : () => SoundService.instance.preview(sound, setting.volume),
              icon: Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color: muted ? theme.textQuaternary : theme.textTertiary,
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(K.radiusRow),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // On means it plays — the switch says what you hear, the way
            // every other switch on this page does.
            AppSwitch(
              value: !muted,
              onChanged: (on) => cubit.setSoundMuted(sound, !on),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: VolumeSlider(
                value: muted ? 0 : setting.volume,
                onChanged: muted
                    ? null
                    : (volume) {
                        cubit.setSoundVolume(sound, volume);
                        SoundService.instance.preview(sound, volume);
                      },
              ),
            ),
            SizedBox(
              width: _readoutWidth,
              child: Text(
                muted ? '—' : '${(setting.volume * 100).round()}%',
                textAlign: TextAlign.end,
                style: AppText.chip.copyWith(color: theme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Wide enough for "100%", so the track does not shift as it is dragged.
  static const _readoutWidth = 40.0;
}
