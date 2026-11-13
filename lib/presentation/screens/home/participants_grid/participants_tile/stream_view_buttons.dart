import 'package:material_ui/material_ui.dart';

import '../../../../../logic/services/host_platform.dart';
import 'stream_corner_button.dart';
import 'stream_view.dart';
import 'stream_volume_button.dart';

/// Edge to edge and full screen, side by side in the corner of a watched
/// stream, with its sound and the sharer's camera before them when it has
/// them.
///
/// Each one leaves when it is the view already on, and switches when the
/// other is: from full screen, edge to edge gives the window back without
/// putting the call back round the stream.
///
/// A phone has no edge to edge: its window is the screen already. In the
/// call that place holds the way back to the grid ([onBack]) instead, since
/// a tap on the stream there only shows or hides the controls.
class StreamViewButtons extends StatelessWidget {
  final StreamView view;
  final ValueChanged<StreamView> onView;

  /// Where the stream's sound is set ([StreamVolumeButton]). Null for a
  /// stream with none.
  final String? soundKey;

  /// Whether the sharer's camera floats over the stream (`StreamCameraPip`).
  final bool cameraShown;

  /// Puts their camera away or brings it back. Null while it is off.
  final VoidCallback? onCamera;

  /// Back from the focused stream to the grid. Null where a tap on the
  /// stream does that.
  final VoidCallback? onBack;

  const StreamViewButtons({
    super.key,
    required this.view,
    required this.onView,
    this.soundKey,
    this.cameraShown = false,
    this.onCamera,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final edgeToEdge = view == StreamView.edgeToEdge;
    final fullscreen = view == StreamView.fullscreen;
    return Row(
      mainAxisSize: MainAxisSize.min,
      // A phone's volume stands up above its speaker; the rest stay down.
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 6,
      children: [
        if (soundKey case final key?) StreamVolumeButton(settingsKey: key),
        if (onCamera case final toggle?)
          StreamCornerButton(
            icon: cameraShown
                ? Icons.videocam_off_outlined
                : Icons.videocam_outlined,
            tooltip: cameraShown ? 'Hide their camera' : 'Show their camera',
            onTap: toggle,
          ),
        if (onBack case final back?)
          StreamCornerButton(
            icon: Icons.grid_view_rounded,
            tooltip: 'Show everyone',
            onTap: back,
          )
        else if (!HostPlatform.isMobile)
          StreamCornerButton(
            icon: edgeToEdge
                ? Icons.close_fullscreen_rounded
                : Icons.fit_screen_outlined,
            tooltip: edgeToEdge ? 'Exit edge to edge' : 'Edge to edge',
            onTap: () => onView(StreamView.edgeToEdge),
          ),
        StreamCornerButton(
          icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          tooltip: fullscreen ? 'Exit full screen' : 'Full screen',
          onTap: () => onView(StreamView.fullscreen),
        ),
      ],
    );
  }
}
