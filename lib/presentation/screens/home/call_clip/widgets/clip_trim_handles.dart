import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';

/// The start and end of the selection over the waveform, as fractions of the
/// clip, and the waveform's own clicks.
///
/// Only a drag that begins on a handle moves it ([reach] either side of its
/// line); the two stay [minGap] apart. Anywhere else a click puts the play
/// line there ([onSeek]), and a drag scrubs it, between [onScrubStart] and
/// [onScrubEnd]. A click used to move the nearer handle, so trying to hear a
/// moment of the clip cut the selection down to it.
class ClipTrimHandles extends StatefulWidget {
  final double start;
  final double end;

  /// The least a selection may be, as a fraction of the clip.
  final double minGap;

  final void Function(double start, double end) onChanged;
  final ValueChanged<double> onSeek;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  const ClipTrimHandles({
    super.key,
    required this.start,
    required this.end,
    required this.minGap,
    required this.onChanged,
    required this.onSeek,
    this.onScrubStart,
    this.onScrubEnd,
  });

  /// How far from a handle's line, in pixels, a drag still takes the handle.
  static const double reach = 12;

  @override
  State<ClipTrimHandles> createState() => _ClipTrimHandlesState();
}

enum _Drag { start, end, scrub }

class _ClipTrimHandlesState extends State<ClipTrimHandles> {
  _Drag? _drag;

  /// How far the handle's line was from the press, as a fraction, so a handle
  /// taken from beside its line moves with the drag rather than jumping.
  double _offset = 0;

  /// The handle under [x] pixels across [width], the nearer of the two when
  /// both are in reach, or null away from both.
  _Drag? _handleAt(double x, double width) {
    final toStart = (x - widget.start * width).abs();
    final toEnd = (x - widget.end * width).abs();
    if (toStart > ClipTrimHandles.reach && toEnd > ClipTrimHandles.reach) {
      return null;
    }
    return toStart <= toEnd ? _Drag.start : _Drag.end;
  }

  void _begin(double x, double width) {
    final drag = _handleAt(x, width) ?? _Drag.scrub;
    _drag = drag;
    _offset = switch (drag) {
      _Drag.start => widget.start - x / width,
      _Drag.end => widget.end - x / width,
      _Drag.scrub => 0,
    };
    if (drag == _Drag.scrub) widget.onScrubStart?.call();
    _move(x / width);
  }

  void _move(double at) {
    final to = (at + _offset).clamp(0.0, 1.0);
    switch (_drag) {
      case _Drag.start:
        widget.onChanged(to.clamp(0.0, widget.end - widget.minGap), widget.end);
      case _Drag.end:
        widget.onChanged(
          widget.start,
          to.clamp(widget.start + widget.minGap, 1.0),
        );
      case _Drag.scrub:
        widget.onSeek(to);
      case null:
        break;
    }
  }

  void _finish() {
    if (_drag == _Drag.scrub) widget.onScrubEnd?.call();
    _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        Widget handle(double at) => Positioned(
          left: at * width - ClipTrimHandles.reach,
          top: 0,
          bottom: 0,
          width: ClipTrimHandles.reach * 2,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Center(
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: theme.accentBright,
                  borderRadius: BorderRadius.circular(K.radiusPill),
                ),
              ),
            ),
          ),
        );
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Where the press landed decides handle or scrub, not where the
            // pointer had got to once the drag was recognised.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (d) => _begin(d.localPosition.dx, width),
            onHorizontalDragUpdate: (d) => _move(d.localPosition.dx / width),
            onHorizontalDragEnd: (_) => _finish(),
            onHorizontalDragCancel: _finish,
            onTapUp: (d) =>
                widget.onSeek((d.localPosition.dx / width).clamp(0.0, 1.0)),
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
