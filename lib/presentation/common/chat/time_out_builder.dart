import 'dart:async';

import 'package:material_ui/material_ui.dart';

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

  /// The longest single wait. A browser's timer overflows past about 24.8
  /// days and fires at once, and a time-out may run 28; waking once a day and
  /// asking again costs nothing.
  static const _longestWait = Duration(days: 1);

  /// Wait for the end, then ask again: a timer that fires early — the clock
  /// stepped back, or a capped wait above — re-arms rather than leaving the
  /// gate up until something else rebuilds it.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_active) return;
    final left = widget.until!.difference(DateTime.now());
    _timer = Timer(left > _longestWait ? _longestWait : left, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
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
