import 'package:flutter/material.dart';

import '../../../responsive/shell_scope.dart';
import '../chat/widgets/chat_header_button.dart';

/// Brings the member list back, from the header of whatever the server's
/// centre pane is showing.
///
/// Where the floating tab on the window's right edge used to be the way back.
/// A header already has a row of buttons for this pane, and a button among
/// them is found where people look, rather than on the border between two
/// panels. On a phone, where the list is always a sheet, it is always here.
class ShowMembersButton extends StatelessWidget {
  const ShowMembersButton({super.key});

  /// Whether to put one in a header at all. Left out rather than drawn empty,
  /// because a header row's spacing goes round an empty box too.
  static bool shows(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null || shell.immersive) return false;
    return shell.mode.isCompact || !shell.membersOpen;
  }

  @override
  Widget build(BuildContext context) {
    return ChatHeaderButton(
      icon: Icons.people_alt_rounded,
      tooltip: 'Show members',
      onTap: ShellScope.of(context).toggleMembers,
    );
  }
}
