import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/services/host_platform.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/media_colors.dart';
import '../../../../rising_panel.dart';
import '../../../../volume_readout.dart';
import 'media_track.dart';
import 'video_icon_button.dart';

/// The speaker on a video's strip: pressed, it mutes and unmutes; with a
/// pointer over it, a track stands up above it ([RisingPanel]), so it takes
/// no room from the strip.
///
/// One setting for every chat video (`AppState.chatVideoVolume`), so the
/// next starts where this one was left. A phone has no track: its own
/// volume keys set how loud, as in other apps there.
class VideoVolume extends StatelessWidget {
  /// Whether the tooltip names the key: on the full-screen page.
  final bool showsKeys;

  const VideoVolume({super.key, this.showsKeys = false});

  static const double _track = 96;
  static const double _panelWidth = 40;

  @override
  Widget build(BuildContext context) {
    final (volume, muted) = context.select<AppCubit, (double, bool)>(
      (c) => (c.state.chatVideoVolume, c.state.chatVideoMuted),
    );
    final app = context.read<AppCubit>();
    final silent = muted || volume == 0;
    final button = VideoIconButton(
      icon: silent
          ? Icons.volume_off_rounded
          : volume < 0.5
          ? Icons.volume_down_rounded
          : Icons.volume_up_rounded,
      tooltip: '${silent ? 'Unmute' : 'Mute'}${showsKeys ? ' (m)' : ''}',
      onPressed: () {
        // Unmuting a video turned all the way down brings some sound back.
        if (silent && volume == 0) return app.setChatVideoVolume(0.5);
        app.setChatVideoMuted(!muted);
      },
    );
    if (HostPlatform.isMobile) return button;
    return RisingPanel(
      anchor: button,
      panel: (_) => Container(
        width: _panelWidth,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: MediaColors.panel,
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text(
              VolumeReadout.figure(muted: muted, value: volume),
              style: AppText.chip.copyWith(color: MediaColors.onMedia),
            ),
            RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: _track,
                child: MediaTrack(
                  value: muted ? 0 : volume,
                  onChanged: app.setChatVideoVolume,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
