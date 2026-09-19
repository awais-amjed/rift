import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/theme_context.dart';

/// A hairline above [child] that appears once [child] has been scrolled.
///
/// A fixed header sitting directly on a scroll view gives whatever scrolls
/// past it nothing to disappear behind: a heading on its way out is sliced
/// mid-glyph a few pixels under the subtitle, which reads as two pieces of
/// text colliding rather than as one of them leaving. The rule is the edge
/// that was missing — the same hairline the footer already draws, so the two
/// ends of a panel are built the same way.
///
/// Only while scrolled, because a panel whose page fits should look exactly
/// as it did: an always-drawn rule would be chrome on every page to solve a
/// problem only the long ones have. It doubles as the answer to "is there
/// more above?", which is the other thing a clipped heading fails to say.
///
/// Wraps the scroll view rather than living inside it — the point is to be
/// the thing that does *not* move.
class ScrolledUnderRule extends StatefulWidget {
  /// The scrolling page. Its own [Scrollable] may be at any depth: this
  /// listens for the notification rather than owning a controller, so a page
  /// that scrolls itself works the same as one scrolled for it.
  final Widget child;

  const ScrolledUnderRule({super.key, required this.child});

  @override
  State<ScrolledUnderRule> createState() => _ScrolledUnderRuleState();
}

class _ScrolledUnderRuleState extends State<ScrolledUnderRule> {
  bool _scrolled = false;

  /// True once anything vertical below us is off its own top.
  ///
  /// Horizontal scrollables are ignored rather than trusted to be absent — a
  /// row of chips inside a settings page would otherwise draw the rule by
  /// being dragged sideways.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final scrolled = notification.metrics.pixels > 0;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedOpacity(
          opacity: _scrolled ? 1 : 0,
          duration: AppMotion.react,
          curve: AppMotion.settle,
          child: Divider(height: 1, color: context.theme.borderPrimary),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
