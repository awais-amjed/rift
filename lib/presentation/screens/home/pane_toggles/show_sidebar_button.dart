import 'package:flutter/material.dart';

import '../../../responsive/shell_scope.dart';
import '../chat/widgets/chat_header_button.dart';

/// Brings the left sidebar back, from the start of the centre pane's header —
/// where apps put the button for the panel on that side.
///
/// Only while the sidebar is hidden, and never on a phone, where the channel
/// list is the screen underneath and back is the way to it.
class ShowSidebarButton extends StatelessWidget {
  const ShowSidebarButton({super.key});

  /// Whether to put one in a header at all — see [ShowMembersButton.shows]
  /// for why it is left out rather than drawn empty.
  static bool shows(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null || shell.immersive || shell.mode.isCompact) return false;
    return !shell.sidebarOpen;
  }

  @override
  Widget build(BuildContext context) {
    return ChatHeaderButton(
      // The panel icon mirrored, so the panel it draws is on the left, where
      // the sidebar will open.
      icon: Icons.view_sidebar_outlined,
      mirror: true,
      tooltip: 'Show sidebar',
      onTap: ShellScope.of(context).toggleSidebar,
    );
  }
}
