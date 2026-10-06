import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/sound_share/sound_share_cubit.dart';
import '../../../controls/screen_share/screen_share_control.dart';
import '../../../controls/widgets/control_button.dart';
import '../../../controls/widgets/sound_share_button.dart';
import '../../../soundboard/soundboard_button.dart';

/// The call bar's own controls, in the dock: camera, screen, sound and the
/// soundboard, sharing the dock's width equally.
///
/// The same widgets the bar draws, in their dense shape, so a share started
/// here is the share the bar shows and its menu is the same menu.
class DockCallControls extends StatelessWidget {
  final bool cameraOn;

  const DockCallControls({super.key, required this.cameraOn});

  static const _gap = SizedBox(width: K.dockCallButtonGap);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ControlButton(
            icon: cameraOn ? Icons.videocam : Icons.videocam_off,
            isDimmed: !cameraOn,
            tooltip: cameraOn ? 'Turn off camera' : 'Turn on camera',
            onTap: () => context.read<LiveKitCubit>().toggleCamera(),
            dense: true,
          ),
        ),
        _gap,
        const Expanded(child: ScreenShareControl(dense: true)),
        if (SoundShareCubit.isSupported) ...[
          _gap,
          const Expanded(child: SoundShareButton(dense: true)),
        ],
        // Takes its own share and gap, since it is the one that can be absent.
        const SoundboardButton(dense: true),
      ],
    );
  }
}
