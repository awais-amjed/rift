import 'package:flutter/material.dart';

import 'server_dms_row.dart';
import 'sidebar_channel_list.dart';
import 'sidebar_header.dart';

/// A server's own column: who the server is, its DMs, and its channels.
///
/// Identity, then navigation, and nothing else — the actions that act on the
/// server as a whole (invite, settings, manage members, leave) live on the
/// rail chip's context menu, on the chip they act on. A toolbar here would be
/// a second home for them that every member pays for in vertical space.
///
/// Also used by the content pane on a phone, where the sidebar is a drawer
/// and "the server" has to be somewhere you can stand rather than something
/// you hold open. [inSidebar] is what tells the header there is no sidebar to
/// collapse in that case.
class ServerNavColumn extends StatelessWidget {
  final bool inSidebar;

  const ServerNavColumn({super.key, this.inSidebar = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SidebarHeader(showHideButton: inSidebar),
        const ServerDmsRow(),
        const SidebarChannelList(),
      ],
    );
  }
}
