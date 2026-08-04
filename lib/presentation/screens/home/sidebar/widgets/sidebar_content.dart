import 'package:flutter/material.dart';

import '../../profile/user_dock/user_dock.dart';
import '../../servers/server_rail/server_rail.dart';
import 'server_dms_row.dart';
import 'sidebar_channel_list.dart';
import 'sidebar_header.dart';
import 'sidebar_actions.dart';

/// The main content of the sidebar, used both in pinned and floating modes.
class SidebarContent extends StatelessWidget {
  final bool isPinned;
  final double topPadding;

  const SidebarContent({
    super.key,
    required this.isPinned,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    // The panel's background, border and rounding belong to [AppPanel], which
    // wraps this in both modes — this widget is only the contents.
    return Row(
      children: [
        ServerRail(topPadding: topPadding),
        Expanded(
          child: Column(
            children: [
              SizedBox(height: topPadding),
              SidebarHeader(),
              SidebarActions(),
              ServerDmsRow(),
              SidebarChannelList(),
              UserDock(),
            ],
          ),
        ),
      ],
    );
  }
}
