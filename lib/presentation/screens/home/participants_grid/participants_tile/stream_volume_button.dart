import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/call_volume.dart';
import '../../../../common/volume_readout.dart';
import '../../../../common/volume_slider.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import 'stream_corner_button.dart';
import 'stream_glass.dart';

/// A watched stream's sound, beside its view buttons: the speaker mutes it,
/// and pointing at it slides out the volume.
///
/// The same setting as the stream's menu ([StreamContextMenu]), stored under
/// [settingsKey], so either one moves the other. The menu was the only way
/// in, and a game too loud to talk over took a right-click and a hunt to
/// turn down.
///
/// The track opens to the speaker's left, so the speaker stays under the
/// pointer that opened it. A finger has no hover: its first tap opens the
/// track, and the speaker mutes from then on.
class StreamVolumeButton extends StatefulWidget {
  final String settingsKey;

  const StreamVolumeButton({super.key, required this.settingsKey});

  @override
  State<StreamVolumeButton> createState() => _StreamVolumeButtonState();
}

class _StreamVolumeButtonState extends State<StreamVolumeButton> {
  static const double _trackWidth = 96;

  /// Wide enough for "400%", so the track does not shift while dragged.
  static const double _figureWidth = 34;

  bool _open = false;
  PointerDeviceKind? _pressedWith;

  @override
  Widget build(BuildContext context) {
    final setting = context.select<AppCubit, ({bool muted, double volume})>((
      cubit,
    ) {
      final s = cubit.state.settingFor(widget.settingsKey);
      return (muted: s.muted, volume: s.volume);
    });
    final livekit = context.read<LiveKitCubit>();

    return MouseRegion(
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) => setState(() => _open = false),
      child: StreamGlass(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: AppMotion.state,
              curve: AppMotion.settle,
              alignment: Alignment.centerRight,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          SizedBox(
                            width: _trackWidth,
                            child: VolumeSlider(
                              value: setting.muted ? 0 : setting.volume,
                              max: CallVolume.max,
                              onChanged: setting.muted
                                  ? null
                                  : (value) => livekit.setVolumeFor(
                                      widget.settingsKey,
                                      value,
                                    ),
                            ),
                          ),
                          VolumeReadout(
                            value: setting.volume,
                            muted: setting.muted,
                            style: AppText.chip,
                            width: _figureWidth,
                            onChanged: (value) =>
                                livekit.setVolumeFor(widget.settingsKey, value),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Tooltip(
              message: setting.muted ? 'Unmute stream' : 'Mute stream',
              child: StreamCornerIcon(
                icon: _icon(setting.muted, setting.volume),
                onTapDown: (details) => _pressedWith = details.kind,
                onTap: () {
                  if (_pressedWith == PointerDeviceKind.touch && !_open) {
                    setState(() => _open = true);
                    return;
                  }
                  livekit.setMuteFor(widget.settingsKey, !setting.muted);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(bool muted, double volume) {
    if (muted || volume == 0) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }
}
