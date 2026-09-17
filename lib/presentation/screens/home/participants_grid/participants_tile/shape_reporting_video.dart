import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;

/// A video that says what shape its frames are.
///
/// [VideoTrackRenderer] knows the frame size but keeps it private, so this
/// hands it a renderer of our own and listens to that. The grid uses the
/// shape to size a screen share's box to the picture instead of a fixed
/// 16:9 cell with bars around it.
class ShapeReportingVideo extends StatefulWidget {
  final VideoTrack track;

  /// Width over height, whenever a frame arrives at a new size.
  final ValueChanged<double> onAspectRatio;

  const ShapeReportingVideo({
    super.key,
    required this.track,
    required this.onAspectRatio,
  });

  @override
  State<ShapeReportingVideo> createState() => _ShapeReportingVideoState();
}

class _ShapeReportingVideoState extends State<ShapeReportingVideo> {
  final _renderer = rtc.RTCVideoRenderer();
  late final Future<void> _ready = _renderer.initialize();
  double? _reported;

  @override
  void initState() {
    super.initState();
    _renderer.addListener(_onValue);
  }

  @override
  void dispose() {
    _renderer.removeListener(_onValue);
    // The renderer inside has already let go of its view by now — children
    // unmount first — and it leaves an injected renderer for us to close.
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  void _onValue() {
    final value = _renderer.value;
    // Zero until the first frame; `aspectRatio` would claim a square.
    if (value.width <= 0 || value.height <= 0) return;
    final ratio = value.aspectRatio;
    if (ratio == _reported) return;
    _reported = ratio;
    widget.onAspectRatio(ratio);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return VideoTrackRenderer(
          widget.track,
          fit: VideoViewFit.contain,
          cachedRenderer: _renderer,
          autoDisposeRenderer: false,
        );
      },
    );
  }
}
