import 'package:flutter/material.dart';

import 'stream_corner_button.dart';
import 'stream_view.dart';

/// Edge to edge and full screen, side by side in the corner of a watched
/// stream.
///
/// Each one leaves when it is the view already on, and switches when the
/// other is: from full screen, edge to edge gives the window back without
/// putting the call back round the stream.
class StreamViewButtons extends StatelessWidget {
  final StreamView view;
  final ValueChanged<StreamView> onView;

  const StreamViewButtons({
    super.key,
    required this.view,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final edgeToEdge = view == StreamView.edgeToEdge;
    final fullscreen = view == StreamView.fullscreen;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
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
