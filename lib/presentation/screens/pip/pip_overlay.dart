import 'package:flutter/material.dart';

import '../../../logic/services/pip_service.dart';
import 'pip_call_view.dart';

/// Puts [PipCallView] over the app while it is a floating window.
///
/// Over, not instead of: the app stays mounted behind it, merely offstage. A
/// call's renderers, its screenshare subscriptions and every open panel are
/// held by widgets, and tearing them down on the way into a window that lasts
/// seconds would rebuild the entire call on the way out — the one moment where
/// dropping a subscription would be least forgivable.
class PipOverlay extends StatelessWidget {
  final Widget child;

  const PipOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService.instance.isInPip,
      // Passed through rather than rebuilt: this listener fires on a window
      // resize, and the app below it has nothing to do with the answer.
      child: child,
      builder: (context, inPip, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: inPip, child: child),
            if (inPip) const PipCallView(),
          ],
        );
      },
    );
  }
}
