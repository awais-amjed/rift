import 'dart:async';

import 'package:flutter/material.dart';

import '../../../logic/services/time_out_label.dart';
import 'composer_notice.dart';

/// The composer, or — while the member is timed out — a notice saying until
/// when, which gives the composer back by itself when the time is up.
///
/// A timer rather than waiting to be told: nothing rings when a time-out
/// simply runs out, only when a moderator lifts it early, so without one the
/// notice would stay until the next refresh. The server is what enforces it
/// either way; this only saves typing into a box that would be refused.
class TimeOutGate extends StatefulWidget {
  final DateTime? until;
  final Widget child;

  const TimeOutGate({super.key, required this.until, required this.child});

  @override
  State<TimeOutGate> createState() => _TimeOutGateState();
}

class _TimeOutGateState extends State<TimeOutGate> {
  Timer? _timer;

  bool get _active =>
      widget.until != null && widget.until!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(TimeOutGate oldWidget) {
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
  Widget build(BuildContext context) {
    if (!_active) return widget.child;
    return ComposerNotice(
      icon: Icons.timer_outlined,
      text:
          'You\'re timed out until ${timeOutEndLabel(widget.until!)}. You '
          'can read, but not send messages, DMs or reactions.',
    );
  }
}
