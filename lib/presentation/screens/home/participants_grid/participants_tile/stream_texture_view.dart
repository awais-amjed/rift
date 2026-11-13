import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/watched_picture.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/theme_context.dart';

/// A share watched through the Rust watch connection: the runner's texture,
/// fitted inside the box as the call's own renderer fits a track.
///
/// Covered until the first picture, which only comes once it decrypts and
/// decodes, so there is no garbage to hide as [DecryptedVideo] hides it.
class StreamTextureView extends StatefulWidget {
  final WatchedPicture picture;

  /// Width over height, whenever the picture arrives at a new size.
  final ValueChanged<double>? onAspectRatio;

  const StreamTextureView({
    super.key,
    required this.picture,
    this.onAspectRatio,
  });

  @override
  State<StreamTextureView> createState() => _StreamTextureViewState();
}

class _StreamTextureViewState extends State<StreamTextureView> {
  double? _reported;

  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(StreamTextureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _report();
  }

  /// After the frame: the grid resizes the box in answer.
  void _report() {
    final onAspectRatio = widget.onAspectRatio;
    final picture = widget.picture;
    if (onAspectRatio == null || !picture.hasPicture) return;
    final ratio = picture.width / picture.height;
    if (ratio == _reported) return;
    _reported = ratio;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) onAspectRatio(ratio);
    });
  }

  @override
  Widget build(BuildContext context) {
    final picture = widget.picture;
    if (!picture.hasPicture) {
      return ColoredBox(
        color: context.theme.bgSecondary,
        child: Center(
          child: LoadingDots(color: context.theme.textTertiary, dotSize: 4),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: picture.width.toDouble(),
        height: picture.height.toDouble(),
        child: Texture(
          textureId: picture.textureId,
          filterQuality: FilterQuality.low,
        ),
      ),
    );
  }
}
