import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

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

  /// Squares, as wide as they are tall, rather than shares of the dock's
  /// width: on a phone they sit in the call's own row, beside Leave, so the
  /// dock is a row shorter.
  final bool inline;

  const DockCallControls({
    super.key,
    required this.cameraOn,
    this.inline = false,
  });

  static const _gap = SizedBox(width: K.dockCallButtonGap);

  @override
  Widget build(BuildContext context) {
    Widget slot(Widget child) => inline ? child : Expanded(child: child);
    final gap = inline ? const SizedBox(width: K.dockIconGap) : _gap;
    return Row(
      mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
      children: [
        slot(
          ControlButton(
            icon: cameraOn ? Icons.videocam : Icons.videocam_off,
            isDimmed: !cameraOn,
            tooltip: cameraOn ? 'Turn off camera' : 'Turn on camera',
            onTap: () => context.read<LiveKitCubit>().toggleCamera(),
            dense: true,
          ),
        ),
        gap,
        slot(const ScreenShareControl(dense: true)),
        if (SoundShareCubit.isSupported) ...[
          gap,
          slot(const SoundShareButton(dense: true)),
        ],
        // Takes its own share and gap, since it is the one that can be absent.
        SoundboardButton(dense: true, width: inline ? K.touchTargetMin : null),
      ],
    );
  }
}
