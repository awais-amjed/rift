import 'package:flutter/material.dart';

import '../../../../responsive/shell_scope.dart';
import 'chat_header_button.dart';

/// Opens the channel sidebar from a panel header, on the widths where it is a
/// drawer rather than a fixed column.
///
/// The edge tabs on the window's sides are the way back to a *docked* pane and
/// stay where they are. They are a poor fit for a drawer, though: a 6px strip
/// against the frame is a mouse target, not a thumb one, and on a phone the
/// top-left corner is the one place every app already puts this. So below the
/// medium breakpoint the tabs stand down and these take over.
///
/// Renders nothing at all when the pane it controls is docked — the pane is
/// already on screen, and a second control for it only makes it ambiguous
/// which one you are meant to reach for.
class HeaderSidebarButton extends StatelessWidget {
  const HeaderSidebarButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.layoutMode.sidebarIsOverlay) return const SizedBox.shrink();
    return ChatHeaderButton(
      icon: Icons.menu_rounded,
      tooltip: 'Show channels',
      onTap: ShellScope.of(context).toggleSidebar,
    );
  }
}

/// Opens the member list from a panel header. See [HeaderSidebarButton].
///
/// Only on compact widths, not everywhere the list is overlaid: at medium the
/// content still has room to spare and the edge tab is a perfectly good target
/// for a pointer, which is what is on the other end of a window that size.
class HeaderMembersButton extends StatelessWidget {
  const HeaderMembersButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.layoutMode.isCompact) return const SizedBox.shrink();
    return ChatHeaderButton(
      icon: Icons.people_alt_rounded,
      tooltip: 'Show members',
      onTap: ShellScope.of(context).toggleMembers,
    );
  }
}
