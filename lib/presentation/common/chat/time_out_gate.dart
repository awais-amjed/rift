import 'package:flutter/material.dart';

import '../../../logic/services/time_out_label.dart';
import 'composer_notice.dart';
import 'time_out_builder.dart';

/// The composer, or — while the member is timed out — a notice saying until
/// when, which gives the composer back by itself when the time is up.
class TimeOutGate extends StatelessWidget {
  final DateTime? until;
  final Widget child;

  const TimeOutGate({super.key, required this.until, required this.child});

  @override
  Widget build(BuildContext context) => TimeOutBuilder(
    until: until,
    builder: (context, timedOut) => !timedOut
        ? child
        : ComposerNotice(
            icon: Icons.timer_outlined,
            text:
                'You\'re timed out until ${timeOutEndLabel(until!)}. You '
                'can read, but not post, edit, react, pin or start calls.',
          ),
  );
}
