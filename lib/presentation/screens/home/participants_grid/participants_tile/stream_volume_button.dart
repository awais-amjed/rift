import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/call_volume.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/context_menu/context_menu_watcher.dart';
import '../../../../common/volume_readout.dart';
import '../../../../common/volume_slider.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
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
///
/// A phone's track stands up above the speaker instead, the way a phone's
/// own volume does, with the mute at its foot: the speaker opens and closes
/// it, and so does a tap anywhere else. Opened sideways by the first tap, it
/// had no way to close.
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

  /// A phone's standing track: long enough for a thumb to set it finely.
  static const double _standingTrack = 140;

  /// The standing track's width: the speaker's under it (its icon, padding
  /// and the glass's rim), so the two make one column and nothing beside
  /// them moves when it opens.
  static const double _phoneColumn = K.iconButton + 14;

  /// The standing panel's width: room for "400%" at a phone's text size.
  static const double _panelWidth = 48;

  bool _open = false;

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
          // wider than that. It narrowed each time it grew, opening or
          // making room for the reset, and widened again once it stopped.
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
                            child: Container(
                              width: _panelWidth,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 6,
                                children: [
                                  // The figure alone: the readout's reset button
                                  // kept its room while hidden, and pushed the
                                  // figure to one side of a column this narrow.
                                  Text(
                                    VolumeReadout.figure(
                                      muted: setting.muted,
                                      value: setting.volume,
                                    ),
                                    style: AppText.chip.copyWith(
                                      color: context.theme.textSecondary,
                                    ),
                                  ),
                                  // Away from 100%, the way back to it, which
                                  // the panel grows to hold.
                                  if (!setting.muted &&
                                      (setting.volume * 100).round() != 100)
                                    Tooltip(
                                      message: 'Reset to 100%',
                                      child: StreamCornerIcon(
                                        icon: Icons.restart_alt_rounded,
                                        onTap: () => livekit.setVolumeFor(
                                          widget.settingsKey,
                                          1.0,
                                        ),
                                      ),
                                    ),
                                  RotatedBox(
                                    quarterTurns: 3,
                                    child: SizedBox(
                                      width: _standingTrack,
                                      height: _panelWidth,
                                      child: VolumeSlider(
                                        value: setting.muted
                                            ? 0
                                            : setting.volume,
                                        max: CallVolume.max,
                                        onChanged: setting.muted
                                            ? null
                                            : (value) => livekit.setVolumeFor(
                                                widget.settingsKey,
                                                value,
                                              ),
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message: setting.muted
                                        ? 'Unmute stream'
                                        : 'Mute stream',
                                    child: StreamCornerIcon(
                                      icon: setting.muted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_mute_rounded,
                                      onTap: () => livekit.setMuteFor(
                                        widget.settingsKey,
                                        !setting.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
