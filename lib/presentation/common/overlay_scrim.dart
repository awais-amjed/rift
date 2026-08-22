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
class OverlayScrim extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const OverlayScrim({super.key, required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: K.sidebarMotion,
        curve: AppMotion.panel,
        opacity: visible ? 1 : 0,
        child: GestureDetector(
          onTap: onTap,
          // Opaque so the gesture wins over anything below, rather than only
          // where the colour happens to be painted.
          behavior: HitTestBehavior.opaque,
          child: const ColoredBox(color: Color(0x99000000)),
        ),
      ),
    );
  }
}
