import 'package:material_ui/material_ui.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_motion.dart';
import '../../../../../theme/media_colors.dart';

/// A bar on a video you press or drag along: how far it has played, or how
/// loud it is. [onChanged] hears every move, [onChangeEnd] the place it was
/// let go; both as a fraction of the bar.
///
/// Grows a little and shows its knob while the pointer is over it, so a thin
/// line that stays out of the picture is still something to aim at.
class MediaTrack extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const MediaTrack({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<MediaTrack> createState() => _MediaTrackState();
}

class _MediaTrackState extends State<MediaTrack> {
  bool _hovered = false;
  bool _dragging = false;

  /// Where the last move put it, to let go at.
  double _last = 0;

  double _at(double dx, double width) =>
      _last = width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _dragging;
    final done = widget.value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => widget.onChanged(_at(d.localPosition.dx, width)),
            onTapUp: (d) =>
                widget.onChangeEnd?.call(_at(d.localPosition.dx, width)),
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              widget.onChanged(_at(d.localPosition.dx, width));
            },
            onHorizontalDragUpdate: (d) =>
                widget.onChanged(_at(d.localPosition.dx, width)),
            onHorizontalDragEnd: (_) {
              setState(() => _dragging = false);
              widget.onChangeEnd?.call(_last);
            },
            // A taller target than the bar it draws.
            child: SizedBox(
              height: 20,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: AppMotion.react,
                    height: lit ? 6 : 4,
                    decoration: BoxDecoration(
                      color: MediaColors.onMediaQuaternary,
                      borderRadius: BorderRadius.circular(K.radiusPill),
                    ),
                  ),
                  AnimatedContainer(
                    duration: AppMotion.react,
                    height: lit ? 6 : 4,
                    width: width * done,
                    decoration: BoxDecoration(
                      color: MediaColors.onMedia,
                      borderRadius: BorderRadius.circular(K.radiusPill),
                    ),
                  ),
                  Positioned(
                    left: (width * done - 6).clamp(-6.0, width - 6),
                    child: AnimatedScale(
                      duration: AppMotion.react,
                      scale: lit ? 1 : 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: MediaColors.onMedia,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
