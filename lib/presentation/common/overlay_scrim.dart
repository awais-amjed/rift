import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_motion.dart';

/// The dimmed, tappable layer behind an overlaid pane.
///
/// It is what makes an overlay dismissible without aiming at anything: on a
/// phone the drawer covers most of the window, and the strip beside it is the
/// obvious place to tap to get rid of it. It also stops presses reaching the
/// content underneath, which would otherwise let you select a channel through
/// the dimming.
///
/// Fades on the same [K.sidebarMotion] as the pane it belongs to, so the two
/// arrive together, and is taken out of the hit-test entirely when hidden —
/// a transparent scrim left in place would swallow every tap on the content.
///
/// It sizes *itself* rather than relying on a [Positioned.fill] at the call
/// site. A childless [ColoredBox] takes `constraints.smallest`, and a Stack
/// hands its non-positioned children loose constraints — so the obvious
/// spelling of this widget is a scrim zero pixels across: nothing dims, and
/// tapping beside the drawer does nothing at all, which is exactly how it
/// shipped.
class OverlayScrim extends StatelessWidget {
  final bool visible;
  final VoidCallback onDismiss;

  const OverlayScrim({
    super.key,
    required this.visible,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: K.sidebarMotion,
        curve: AppMotion.panel,
        opacity: visible ? 1 : 0,
        child: GestureDetector(
          onTap: onDismiss,
          // Flinging the drawer back the way it came is the other half of the
          // gesture that opened it, and on a phone it is the one a thumb
          // reaches for first. Direction is not checked: only one drawer is
          // ever open, so any horizontal fling out here means the same thing.
          onHorizontalDragEnd: (_) => onDismiss(),
          // Opaque so the gesture wins over anything below, rather than only
          // where the colour happens to be painted.
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(
            child: ColoredBox(color: Color(0x99000000)),
          ),
        ),
      ),
    );
  }
}
