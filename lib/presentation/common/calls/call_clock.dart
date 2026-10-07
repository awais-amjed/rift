import 'dart:async';

import 'package:flutter/material.dart';

import '../../../logic/services/call_duration.dart';

/// How long a call has run since [since], ticking once a second.
///
/// A widget of its own so the tick rebuilds this text and nothing else. Each
/// place that shows a call's length used to tick its whole self — the call
/// bar, the dock's call card, buttons and avatars and all — every second of
/// every call.
class CallClock extends StatefulWidget {
  final DateTime since;
  final TextStyle style;

  /// Written after the time, as in `04:07 · tap to return`.
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
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    '${formatCallDuration(DateTime.now().difference(widget.since))}'
    '${widget.suffix}',
    maxLines: widget.maxLines,
    overflow: widget.overflow,
    style: widget.style,
  );
}
