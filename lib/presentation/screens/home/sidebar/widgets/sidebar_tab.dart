import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/edge_tab.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_motion.dart';

/// Brings the left sidebar back once it has been hidden.
///
/// Hiding used to swap the panel for an overlay that slid out on hover, which
/// meant it appeared when you were on your way somewhere else and vanished from
/// under any menu opened inside it. Hidden means hidden now, and this is the
/// only way back — the same tab the member list uses, on the other edge.
///
/// Stays in the tree while the sidebar is open so it has something to animate
/// from, sliding out through the left edge rather than blinking away.
class SidebarTab extends StatelessWidget {
  const SidebarTab({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final open = shell.sidebarOpen;

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
