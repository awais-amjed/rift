import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/edge_tab.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_motion.dart';

/// Brings the left sidebar back once it has been hidden.
///
/// This docks it again — the same tab the member list uses, on the other
/// edge. For a look without docking, the middle of the left edge opens a
/// `SidebarPeek` over the content.
///
/// Stays in the tree while the sidebar is open so it has something to animate
/// from, sliding out through the left edge rather than blinking away.
class SidebarTab extends StatelessWidget {
  const SidebarTab({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    // Out of the way over an immersive stream too: sitting on the video's
    // edge it is the one piece of chrome left, and the next pointer
    // movement brings it back with everything else.
    final open = shell.sidebarOpen || shell.immersive;

    return IgnorePointer(
      ignoring: open,
      child: AnimatedSlide(
        duration: K.sidebarMotion,
        curve: AppMotion.panel,
        offset: open ? const Offset(-1, 0) : Offset.zero,
        child: AnimatedOpacity(
          duration: K.sidebarMotion,
          curve: AppMotion.panel,
          opacity: open ? 0 : 1,
          child: EdgeTab(
            side: EdgeTabSide.left,
            tooltip: 'Show sidebar',
            onTap: shell.toggleSidebar,
          ),
        ),
      ),
    );
  }
}
