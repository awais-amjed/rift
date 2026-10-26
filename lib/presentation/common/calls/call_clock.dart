import 'dart:async';

import 'package:flutter/material.dart';

import '../../../logic/services/call_duration.dart';
import '../../../logic/services/steady_clock.dart';

/// How long a call has run since [since], a time on [SteadyClock], ticking
/// each second of its first minute, then as each whole minute passes.
///
/// A widget of its own so the tick rebuilds this text and nothing else. Each
/// place that shows a call's length used to tick its whole self — the call
/// bar, the dock's call card, buttons and avatars and all — every second of
/// every call. Even the text alone, once a second, redrew the whole window
/// that often, so past its first minute the clock shows minutes and wakes
/// only when one turns.
class CallClock extends StatefulWidget {
  final DateTime since;
  final TextStyle style;

  /// Written after the time, as in `4m · tap to return`.
  final String suffix;

  final int? maxLines;
  final TextOverflow? overflow;

  const CallClock({
    super.key,
    required this.since,
    required this.style,
    this.suffix = '',
    this.maxLines,
    this.overflow,
  });

  @override
  State<CallClock> createState() => _CallClockState();
}

class _CallClockState extends State<CallClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(CallClock old) {
    super.didUpdateWidget(old);
    if (old.since != widget.since) _schedule();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Wakes just after the text next changes: each second of the first
  /// minute, then each whole minute. A timer per change rather than a
  /// periodic one, so a late wake never drifts the rest.
  void _schedule() {
    _tick?.cancel();
    var elapsed = SteadyClock.now().difference(widget.since);
    if (elapsed.isNegative) elapsed = Duration.zero;
    final step = elapsed < const Duration(minutes: 1)
        ? const Duration(seconds: 1)
        : const Duration(minutes: 1);
    final into = elapsed.inMicroseconds % step.inMicroseconds;
    _tick = Timer(
      step - Duration(microseconds: into) + _margin,
      () => setState(_schedule),
    );
  }

  /// Past the turn, so the text has always changed by the time it is read.
  static const _margin = Duration(milliseconds: 50);

  @override
  Widget build(BuildContext context) => Text(
    '${formatCallDuration(SteadyClock.now().difference(widget.since))}'
    '${widget.suffix}',
    maxLines: widget.maxLines,
    overflow: widget.overflow,
    style: widget.style,
  );
}
