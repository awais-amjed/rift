import 'package:material_ui/material_ui.dart';

import '../../../../../theme/app_text.dart';
import '../../../../../theme/media_colors.dart';
import '../clip_playback.dart';
import 'media_track.dart';
import 'video_icon_button.dart';
import 'video_volume.dart';

/// The strip along a playing video's foot: play and pause, where it is as a
/// bar to press or drag, the time, the speaker, and the ways to make it
/// bigger.
class VideoControls extends StatefulWidget {
  final ClipPlayback playback;
  final VoidCallback onToggle;

  /// On the viewer page rather than the card: larger, the bar above the
  /// buttons, and the keys named, since they work only there.
  final bool big;

  /// Whether it is on the whole screen, where the button comes out of it.
  final bool fullscreen;
  final VoidCallback onFullscreen;

  /// Opens it in the window, as a picture opens; null where that is not
  /// offered (on the page already, or on a phone, whose window is the
  /// screen).
  final VoidCallback? onExpand;

  const VideoControls({
    super.key,
    required this.playback,
    required this.onToggle,
    required this.big,
    required this.fullscreen,
    required this.onFullscreen,
    this.onExpand,
  });

  static String clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  /// Where a drag along the bar has got: drawn there, and sought only when
  /// it is let go, so the player is not asked to seek for every pixel.
  double? _dragged;

  @override
  Widget build(BuildContext context) {
    final p = widget.playback;
    final total = p.length.inMilliseconds;
    final done =
        _dragged ??
        (total == 0 ? 0.0 : (p.position.inMilliseconds / total).clamp(0, 1))
            .toDouble();
    final shown = _dragged == null ? p.position : p.length * done;
    final big = widget.big;
    final whole = widget.fullscreen;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A portrait video's card is narrow, so the strip lets go of what
        // it can do without as it narrows: the length, then the time, then
        // the speaker. Its volume stands up above it, taking no room here.
        final width = constraints.maxWidth;
        final time = width < 220
            ? null
            : width < 340
            ? VideoControls.clock(shown)
            : '${VideoControls.clock(shown)} / '
                  '${VideoControls.clock(p.length)}';
        return Container(
          color: big ? null : MediaColors.toolbar,
          padding: big
              ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
              : const EdgeInsets.fromLTRB(4, 2, 6, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (big) _track(done),
              Row(
                spacing: big ? 6 : 2,
                children: [
                  VideoIconButton(
                    icon: p.ended
                        ? Icons.replay_rounded
                        : p.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: _key(p.playing ? 'Pause' : 'Play', 'k'),
                    size: big ? 28 : 22,
                    onPressed: widget.onToggle,
                  ),
                  if (width >= 140) VideoVolume(showsKeys: big),
                  if (!big) Expanded(child: _track(done)),
                  if (time != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        time,
                        // Ticks while playing, so it must not change width.
                        style: AppText.figure.copyWith(
                          color: MediaColors.onMedia,
                        ),
                      ),
                    ),
                  if (big) const Spacer(),
                  if (widget.onExpand case final expand? when width >= 200)
                    VideoIconButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: 'Expand',
                      size: 18,
                      onPressed: expand,
                    ),
                  VideoIconButton(
                    icon: whole
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    tooltip: _key(
                      whole ? 'Exit full screen' : 'Full screen',
                      'f',
                    ),
                    size: big ? 28 : 22,
                    onPressed: widget.onFullscreen,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// The page's keys work only there, so only there are they named.
  String _key(String what, String key) => widget.big ? '$what ($key)' : what;

  Widget _track(double done) => MediaTrack(
    value: done,
    onChanged: (f) => setState(() => _dragged = f),
    onChangeEnd: (f) {
      setState(() => _dragged = null);
      widget.playback.seek(widget.playback.length * f);
    },
  );
}
