import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/sound_share/sound_share_cubit.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_modal.dart';
import '../../soundshare/sound_share_picker_dialog.dart';
import 'control_button.dart';

/// Shares one application's sound, with no picture — a room listening to
/// music somebody has on, rather than watching them have it on.
///
/// Desktop only ([SoundShareCubit.isSupported]): capturing another
/// application's output is something a phone and a browser tab cannot do at
/// all, so the places that show this leave it out there rather than drawing a
/// button that explains itself.
class SoundShareButton extends StatelessWidget {
  /// Drawn for the user dock: see [ControlButton.dense].
  final bool dense;

  const SoundShareButton({super.key, this.dense = false});

  Future<void> _toggle(BuildContext context) async {
    final soundShareCubit = context.read<SoundShareCubit>();
    final livekitCubit = context.read<LiveKitCubit>();

    if (soundShareCubit.state.isSharing) {
      await soundShareCubit.stopSoundShare();
      return;
    }

    final source = await showCustomDialog<AudioSource>(
      context: context,
      build: (_) => const SoundSharePickerDialog(),
    );
    if (source == null) return;
    if (!livekitCubit.state.inCall) return;

    await soundShareCubit.startSoundShare(source: source);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SoundShareCubit, SoundShareState>(
      buildWhen: (prev, curr) => prev.isSharing != curr.isSharing,
      builder: (context, state) {
        final sharing = state.isSharing;
        return ControlButton(
          icon: sharing ? Icons.music_note_rounded : Icons.music_note_outlined,
          isActive: sharing,
          tooltip: sharing ? 'Stop sharing sound' : 'Share sound',
          onTap: () => _toggle(context),
          dense: dense,
        );
      },
    );
  }
}
