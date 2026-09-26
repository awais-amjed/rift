import 'package:flutter/material.dart';

import '../../../../responsive/shell_scope.dart';
import 'chat_header_button.dart';

/// Opens the member list from a panel header — a sheet, on a phone.
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
