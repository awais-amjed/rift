import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/theme_context.dart';

/// A short fade at the foot of a scrolling page, for as long as there is more
/// of the page below it.
///
/// The mirror of [ScrolledUnderRule], and for the same reason. A page that
/// ends against a footer is sliced wherever the cut happens to fall — a field
/// label cut in half through the middle of its letters, with a hairline under
/// it that reads as the end of the panel rather than the middle of it. The
/// rule says "the panel ends here"; nothing said "and there is more".
///
/// Only while there is more, so a page that fits looks exactly as it did.
///
/// Wraps the scroll view rather than living inside it: the fade is painted
/// over the last few pixels of whatever is passing underneath, and must not
/// scroll with it.
class MoreBelowFade extends StatefulWidget {
  /// The scrolling page. Its own [Scrollable] may be at any depth — this
  /// listens for notifications rather than owning a controller.
  final Widget child;

  /// What the page fades into. The surface behind it, or the fade is a grey
  /// smear over the wrong colour.
  final Color? color;

  /// How tall the fade is. Enough to read as a soft edge on a line of text,
  /// not so much that it dims a button sitting near the bottom.
  final double height;

  const MoreBelowFade({
    super.key,
    required this.child,
    this.color,
    this.height = 24,
  });

  @override
  State<MoreBelowFade> createState() => _MoreBelowFadeState();
}

class _MoreBelowFadeState extends State<MoreBelowFade> {
  bool _more = false;

  /// Two pixels of slack: a page that fits exactly can report a fractional
  /// remainder from rounding, and a fade that flickers on a page with
  /// nothing below it is worse than no fade at all.
  void _update(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return;
    final more = metrics.extentAfter > 2;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.theme.bgSecondary;
    return NotificationListener<ScrollMetricsNotification>(
      // Fires on layout as well as on scroll, which is what catches a page
      // that is already too long the first time it is drawn.
      onNotification: (notification) {
        _update(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _update(notification.metrics);
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: widget.height,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _more ? 1 : 0,
                  duration: AppMotion.react,
                  curve: AppMotion.settle,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withValues(alpha: 0), color],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
