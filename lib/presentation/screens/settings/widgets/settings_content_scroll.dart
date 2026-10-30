import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A settings tab's scroll view, which can open part way down, where the tab
/// was left.
///
/// A tab builds some of itself after it opens — a device list, a section
/// waiting on its cubit — so on the first frame it can be too short to reach
/// that point, and the offset would be cut to what fits. It follows the tab
/// down as it grows instead, until it gets there or the person scrolls.
class SettingsContentScroll extends StatefulWidget {
  final double initialOffset;

  /// How far down it is, on every move: where to come back to.
  final ValueChanged<double> onScrolled;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const SettingsContentScroll({
    super.key,
    this.initialOffset = 0,
    required this.onScrolled,
    required this.padding,
    required this.child,
  });

  @override
  State<SettingsContentScroll> createState() => _SettingsContentScrollState();
}

class _SettingsContentScrollState extends State<SettingsContentScroll> {
  late final ScrollController _controller;

  /// Where it is still on its way to; null once there, or once the person
  /// took over.
  double? _restoring;

  @override
  void initState() {
    super.initState();
    final offset = widget.initialOffset;
    _restoring = offset > 0 ? offset : null;
    _controller = ScrollController(initialScrollOffset: offset)
      ..addListener(_report);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Closed before it got there, it still comes back to the same point.
  void _report() => widget.onScrolled(_restoring ?? _controller.offset);

  bool _onMetrics(ScrollMetricsNotification note) {
    final target = _restoring;
    if (note.depth != 0 || target == null || !_controller.hasClients) {
      return false;
    }
    final reach = math.min(target, note.metrics.maxScrollExtent);
    if (reach >= target) _restoring = null;
    if (_controller.offset != reach) _controller.jumpTo(reach);
    return false;
  }

  bool _onUserScroll(UserScrollNotification note) {
    if (note.depth == 0) _restoring = null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<UserScrollNotification>(
      onNotification: _onUserScroll,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: SingleChildScrollView(
          controller: _controller,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}
