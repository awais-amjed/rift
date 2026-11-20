import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';

/// The start and end of the selection over the waveform, as fractions of the
/// clip. A drag anywhere moves the nearer handle, so a thin handle need not be
/// aimed at; the two stay [minGap] apart.
class ClipTrimHandles extends StatefulWidget {
  final double start;
  final double end;

  /// The least a selection may be, as a fraction of the clip.
  final double minGap;

  final void Function(double start, double end) onChanged;

  const ClipTrimHandles({
    super.key,
    required this.start,
    required this.end,
    required this.minGap,
    required this.onChanged,
  });

  @override
  State<ClipTrimHandles> createState() => _ClipTrimHandlesState();
}

class _ClipTrimHandlesState extends State<ClipTrimHandles> {
  static const double _width = 10;

  /// Which handle the drag holds: the start, or the end.
  bool _movingStart = true;

  void _grab(double at) {
    _movingStart = (at - widget.start).abs() <= (at - widget.end).abs();
    _move(at);
  }

  void _move(double at) {
    final to = at.clamp(0.0, 1.0);
    if (_movingStart) {
      widget.onChanged(to.clamp(0.0, widget.end - widget.minGap), widget.end);
    } else {
      widget.onChanged(
        widget.start,
        to.clamp(widget.start + widget.minGap, 1.0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double fractionOf(Offset local) => local.dx / width;
        Widget handle(double at) => Positioned(
          left: at * width - _width / 2,
          top: 0,
          bottom: 0,
          width: _width,
          child: Center(
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: theme.accentBright,
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
            ),
          ),
        );
        return MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => _grab(fractionOf(d.localPosition)),
            onHorizontalDragUpdate: (d) => _move(fractionOf(d.localPosition)),
            onTapDown: (d) => _grab(fractionOf(d.localPosition)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [handle(widget.start), handle(widget.end)],
            ),
          ),
        );
      },
    );
  }
}
