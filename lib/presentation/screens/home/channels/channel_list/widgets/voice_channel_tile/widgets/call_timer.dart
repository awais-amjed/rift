import 'package:flutter/material.dart';

import '../../../../../../../common/calls/call_clock.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/theme_context.dart';

/// How long a voice channel's call has been going, counting up — `04:07`,
/// then `1:04:07` — where its card used to say LIVE.
///
/// LIVE only ever marked the call you were in, which the card's accent already
/// says. The length says something the card didn't: whether you'd be joining
/// something just starting or two hours in. Mono, like every timer in the call
/// chrome, so the digits tick in place rather than shuffling the header.
class CallTimer extends StatelessWidget {
  final DateTime startedAt;

  /// The call you are in reads a step brighter, as its card does.
  final bool isYours;

  const CallTimer({super.key, required this.startedAt, this.isYours = false});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return CallClock(
      since: startedAt,
      style: AppText.figure.copyWith(
        color: isYours ? theme.textSecondary : theme.textTertiary,
      ),
    );
  }
}
