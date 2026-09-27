import 'dart:async';

import 'package:flutter/material.dart';

/// Builds with whether the member is timed out, and builds again the moment
/// the time-out runs out.
///
/// A timer rather than waiting to be told: nothing rings when a time-out
/// simply runs out, only when a moderator lifts it early, so without one
/// whatever it took away would stay gone until something else happened to
/// rebuild. The server is what enforces it either way; this only keeps the
/// screen from offering what it would refuse.
class TimeOutBuilder extends StatefulWidget {
  final DateTime? until;
  final Widget Function(BuildContext context, bool timedOut) builder;

  const TimeOutBuilder({super.key, required this.until, required this.builder});

  @override
  State<TimeOutBuilder> createState() => _TimeOutBuilderState();
}

class _TimeOutBuilderState extends State<TimeOutBuilder> {
  Timer? _timer;

  bool get _active =>
      widget.until != null && widget.until!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(TimeOutBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_active) return;
    _timer = Timer(widget.until!.difference(DateTime.now()), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _active);
}
