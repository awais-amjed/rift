import 'package:flutter/material.dart';

import 'shell_scope.dart';

/// Closes the route it sits in once the window stops being phone-shaped.
///
/// Most of the app answers a resize by rebuilding into the other shape: an
/// [AppModal] is a dialog when there is room and a page when there is not, and
/// crossing the breakpoint swaps one for the other. A few surfaces have no
/// other shape — the server switcher replaces a rail that exists at every
/// other width, a bottom sheet replaces a dialog — so widening the window
/// leaves them stranded: a 340px panel pinned to the edge of a 1500px window,
/// over the very chrome it stood in for.
///
/// Wrapping those, and only those, closes them instead. Nothing is lost by
/// it: each one is a picker whose whole content is reachable again from the
/// chrome that has just come back.
class CompactOnly extends StatefulWidget {
  final Widget child;

  const CompactOnly({super.key, required this.child});

  @override
  State<CompactOnly> createState() => _CompactOnlyState();
}

class _CompactOnlyState extends State<CompactOnly> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.layoutMode.isCompact) return;
    // After the frame: a resize arrives mid-build, and a route cannot be
    // taken off the navigator while the tree that holds it is being laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || context.layoutMode.isCompact) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      // Pop where this is the top route so the exit animation plays; remove
      // where something has opened over it, which pop would take instead.
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
