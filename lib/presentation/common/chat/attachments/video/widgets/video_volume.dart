import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/services/host_platform.dart';
import '../../../../../theme/app_motion.dart';
import 'media_track.dart';
import 'video_icon_button.dart';

/// The speaker on a video's strip: pressed, it mutes and unmutes; with a
/// pointer over it, a slider slides out beside it.
///
/// One setting for every chat video (`AppState.chatVideoVolume`), so the
/// next starts where this one was left. A phone has no slider: its own
/// volume keys set how loud, as in other apps there.
class VideoVolume extends StatefulWidget {
  /// Whether the tooltip names the key: on the full-screen page.
  final bool showsKeys;

  /// Whether there is room beside it for the slider.
  final bool slider;

  const VideoVolume({super.key, this.showsKeys = false, this.slider = true});

  @override
  State<VideoVolume> createState() => _VideoVolumeState();
}

class _VideoVolumeState extends State<VideoVolume> {
  bool _open = false;
  Timer? _closing;

  @override
  void dispose() {
    _closing?.cancel();
    super.dispose();
  }

  /// Open at once, and closed a moment after the pointer leaves, so a
  /// pointer slipping off the thin slider does not snap it shut under it.
  void _hover(bool over) {
    _closing?.cancel();
    if (over) {
      if (!_open) setState(() => _open = true);
      return;
    }
    _closing = Timer(AppMotion.linger, () {
      if (mounted) setState(() => _open = false);
    });
  }

  static const double _sliderWidth = 72;
  static const double _sliderHeight = 20;

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
      tooltip: '${silent ? 'Unmute' : 'Mute'}${widget.showsKeys ? ' (m)' : ''}',
      onPressed: () {
        // Unmuting a video turned all the way down brings some sound back.
        if (silent && volume == 0) return app.setChatVideoVolume(0.5);
        app.setChatVideoMuted(!muted);
      },
    );
    if (HostPlatform.isMobile || !widget.slider) return button;
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          AnimatedContainer(
            duration: AppMotion.state,
            curve: AppMotion.settle,
            width: _open ? _sliderWidth : 0,
            // A height of its own: the strip lies where nothing bounds its
            // height, and the box inside, left to it, took all of it — the
            // strip never drew.
            height: _sliderHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: _sliderWidth,
                maxWidth: _sliderWidth,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 6),
                  child: MediaTrack(
                    value: muted ? 0 : volume,
                    onChanged: app.setChatVideoVolume,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
