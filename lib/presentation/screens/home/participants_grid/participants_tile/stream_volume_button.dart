import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/call_volume.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/context_menu/context_menu_watcher.dart';
import '../../../../common/rising_panel.dart';
import '../../../../common/volume_readout.dart';
import '../../../../common/volume_slider.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'stream_corner_button.dart';
import 'stream_glass.dart';

/// A watched stream's sound, beside its view buttons: the speaker mutes it,
/// and pointing at it stands the volume up above it ([RisingPanel]), so the
/// buttons beside it keep their places.
///
/// The same setting as the stream's menu ([StreamContextMenu]), stored under
/// [settingsKey], so either one moves the other. The menu was the only way
/// in, and a game too loud to talk over took a right-click and a hunt to
/// turn down.
///
/// A finger on a desktop has no hover: its first tap opens the track, and
/// the speaker mutes from then on, until a tap elsewhere closes it.
///
/// A phone's track stands up above the speaker too, the way a phone's own
/// volume does, but with the mute at its foot: the speaker opens and closes
/// it, and so does a tap anywhere else. Opened sideways by the first tap, it
/// had no way to close.
class StreamVolumeButton extends StatefulWidget {
  final String settingsKey;

  const StreamVolumeButton({super.key, required this.settingsKey});

  @override
  State<StreamVolumeButton> createState() => _StreamVolumeButtonState();
}

class _StreamVolumeButtonState extends State<StreamVolumeButton> {
  /// A desktop's standing track: as long as the sideways one was.
  static const double _deskTrack = 110;

  /// A phone's standing track: long enough for a thumb to set it finely.
  static const double _standingTrack = 140;

  /// The standing track's width: the speaker's under it (its icon, padding
  /// and the glass's rim), so the two make one column and nothing beside
  /// them moves when it opens.
  static const double _phoneColumn = K.iconButton + 14;

  /// The standing panel's width: room for "400%" at a phone's text size.
  static const double _panelWidth = 48;

  /// A phone's standing track is open.
  bool _open = false;

  /// A desktop's, which opens with the pointer over the speaker.
  final GlobalKey<RisingPanelState> _rising = GlobalKey();

  /// The call's controls, told while a phone's track stands open, as they
  /// are told of a menu: left to fade, they took the track with them
  /// between one touch of it and the next.
  ContextMenuWatcher? _watcher;

  /// A phone's: opens or closes the standing track, and tells the controls.
  void _setPhoneOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    if (open) {
      _watcher = ContextMenuWatcher.maybeOf(context)?..onOpened();
    } else {
      _watcher?.onClosed();
      _watcher = null;
    }
  }

  @override
  void dispose() {
    _watcher?.onClosed();
    super.dispose();
  }

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
    if (HostPlatform.isMobile) return _phone(setting, livekit);

    return RisingPanel(
      key: _rising,
      panel: (_) => StreamGlass(
        child: _standing(setting, livekit, track: _deskTrack, mute: false),
      ),
      anchor: StreamGlass(
        child: Tooltip(
          message: setting.muted ? 'Unmute stream' : 'Mute stream',
          child: StreamCornerIcon(
            icon: _icon(setting.muted, setting.volume),
            onTapDown: (details) => _pressedWith = details.kind,
            onTap: () {
              final rising = _rising.currentState;
              if (_pressedWith == PointerDeviceKind.touch &&
                  rising != null &&
                  !rising.isOpen) {
                return rising.pin();
              }
              livekit.setMuteFor(widget.settingsKey, !setting.muted);
            },
          ),
        ),
      ),
    );
  }

  /// The phone's: a speaker that opens a standing track above it.
  Widget _phone(({bool muted, double volume}) setting, LiveKitCubit livekit) {
    return TapRegion(
      onTapOutside: (_) => _setPhoneOpen(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          // Clipped top and bottom only: AnimatedSize clips to its own box
          // while it moves, which is the column's width, and the panel is
          // wider than that. It narrowed each time it grew, opening (or,
          // before it was always there, making room for the reset) and
          // widened again once it stopped.
          ClipRect(
            clipper: const _UpAndDown(),
            child: AnimatedSize(
              duration: AppMotion.state,
              curve: AppMotion.settle,
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              child: _open
                  // Wider than the speaker, centred over it, without widening
                  // the row: only its middle, the track and the mute, takes a
                  // touch, and that is inside the speaker's width.
                  ? SizedBox(
                      width: _phoneColumn,
                      // The panel's own height, which an OverflowBox would
                      // otherwise take from the unbounded column.
                      child: IntrinsicHeight(
                        child: OverflowBox(
                          minWidth: _panelWidth,
                          maxWidth: _panelWidth,
                          child: StreamGlass(
                            child: _standing(
                              setting,
                              livekit,
                              track: _standingTrack,
                              mute: true,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          StreamGlass(
            child: Tooltip(
              message: _open ? 'Close volume' : 'Stream volume',
              child: StreamCornerIcon(
                icon: _icon(setting.muted, setting.volume),
                onTap: () => _setPhoneOpen(!_open),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The standing track, its figure above it and the way back to 100%. A phone's has the mute at its foot, since its speaker opens
  /// and closes the track; a desktop's speaker mutes, under the pointer.
  Widget _standing(
    ({bool muted, double volume}) setting,
    LiveKitCubit livekit, {
    required double track,
    required bool mute,
  }) => Container(
    width: _panelWidth,
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        // The figure alone: the readout's reset button kept its room while
        // hidden, and pushed the figure to one side of a column this narrow.
        Text(
          VolumeReadout.figure(muted: setting.muted, value: setting.volume),
          style: AppText.chip.copyWith(color: context.theme.textSecondary),
        ),
        // The way back to 100%, always there: it came and went as a drag
        // crossed 100%, and the panel moved with it.
        Tooltip(
          message: 'Reset to 100%',
          child: StreamCornerIcon(
            icon: Icons.restart_alt_rounded,
            onTap: () => livekit.setVolumeFor(widget.settingsKey, 1.0),
          ),
        ),
        RotatedBox(
          quarterTurns: 3,
          child: SizedBox(
            width: track,
            height: _panelWidth,
            child: VolumeSlider(
              value: setting.muted ? 0 : setting.volume,
              max: CallVolume.max,
              onChanged: setting.muted
                  ? null
                  : (value) => livekit.setVolumeFor(widget.settingsKey, value),
            ),
          ),
        ),
        if (mute)
          Tooltip(
            message: setting.muted ? 'Unmute stream' : 'Mute stream',
            child: StreamCornerIcon(
              icon: setting.muted
                  ? Icons.volume_off_rounded
                  : Icons.volume_mute_rounded,
              onTap: () =>
                  livekit.setMuteFor(widget.settingsKey, !setting.muted),
            ),
          ),
      ],
    ),
  );

  static IconData _icon(bool muted, double volume) {
    if (muted || volume == 0) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }
}

/// A clip as tall as the box and far wider: the standing panel hangs over
/// both sides of its column.
class _UpAndDown extends CustomClipper<Rect> {
  const _UpAndDown();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, 0, size.width * 2, size.height);

  @override
  bool shouldReclip(_UpAndDown oldClipper) => false;
}
