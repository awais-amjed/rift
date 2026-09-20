import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/soundboard_sound.dart';
import '../../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../widgets/manage_panel.dart';
import 'soundboard/add_clip_form.dart';
import 'soundboard/soundboard_clip_row.dart';

/// The soundboard page of the manage-server dialog.
///
/// Everything here is about the *library*. Who may press one is a permission
/// on the roles page (`Use soundboard`, on `@everyone` by default), and how
/// loud a clip is belongs to whoever hears it — neither is settable from
/// here, and both say so where they live.
class SoundboardPanel extends StatefulWidget {
  const SoundboardPanel({super.key});

  @override
  State<SoundboardPanel> createState() => _SoundboardPanelState();
}

class _SoundboardPanelState extends State<SoundboardPanel> {
  /// Which clip is mid-removal, so its own row goes quiet rather than the
  /// whole list.
  String? _removing;

  /// The last thing that went wrong here. The add form keeps its own — this
  /// one is for the list, where there is no field to hang a message under.
  String? _error;

  Future<void> _remove(SoundboardSound sound) async {
    final cubit = context.read<SoundboardCubit>();
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove ${sound.name}?',
      message:
          'It goes for everyone on this server, and the file goes with it. '
          'Nothing that has already been played is affected.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _removing = sound.id);
    final error = await cubit.remove(sound);
    if (!mounted) return;
    setState(() => _removing = null);
    if (error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return BlocBuilder<SoundboardCubit, SoundboardState>(
      builder: (context, state) {
        return ManagePanel(
          title: 'Soundboard',
          subtitle: 'Short clips anybody in a call can play',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const HintCard(
                icon: Icons.volume_up_outlined,
                text:
                    'A clip is played by everyone in the call on their own '
                    'device, so it costs the server nothing and each person '
                    'sets how loud it is for themselves. The clips are not '
                    'encrypted — the same trade-off as avatars.',
              ),
              const SizedBox(height: 18),
              AddClipForm(
                full: state.sounds.length >= SoundboardCubit.maxSounds,
                onAdd: context.read<SoundboardCubit>().add,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    'CLIPS',
                    style: AppText.sectionLabel.copyWith(
                      color: theme.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${state.sounds.length} / ${SoundboardCubit.maxSounds}',
                    style: AppText.chip.copyWith(color: theme.textQuaternary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error case final error?) ...[
                MessageBanner(message: error, kind: MessageBannerKind.error),
                const SizedBox(height: 8),
              ],
              if (state.status == SoundboardStatus.loading)
                Text(
                  'Loading…',
                  style: AppText.rowQuiet.copyWith(color: theme.textTertiary),
                )
              else if (state.isEmpty)
                Text(
                  'Nothing here yet.',
                  style: AppText.rowQuiet.copyWith(color: theme.textTertiary),
                )
              else
                for (final sound in state.sounds)
                  SoundboardClipRow(
                    key: ValueKey(sound.id),
                    sound: sound,
                    busy: _removing == sound.id,
                    onRemove: () => _remove(sound),
                  ),
            ],
          ),
        );
      },
    );
  }
}
