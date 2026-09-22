import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/theme_context.dart';
import '../../mobile/mobile_shell_scope.dart';
import 'chat_header_button.dart';

/// The way back out of a page on a phone — to the list, or to the call a
/// conversation was opened over.
///
/// Draws nothing anywhere else: a desktop's panes sit side by side and there
/// is nothing to go back to. It pops the shell's navigator rather than closing
/// anything itself, so back from here and the system back gesture are one
/// path, and the shell decides what closing the page means.
class HeaderBackButton extends StatelessWidget {
  const HeaderBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (MobileShellScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: K.touchTargetMin,
      child: IconButton(
        tooltip: 'Back',
        onPressed: navigator.maybePop,
        icon: Icon(
          Icons.chevron_left_rounded,
          size: 28,
          color: context.theme.textSecondary,
        ),
      ),
    );
  }
}

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
