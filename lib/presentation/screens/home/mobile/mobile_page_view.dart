import 'package:flutter/material.dart';

import '../../../../data/enums/mobile_page.dart';
import '../../../theme/theme_context.dart';
import '../chat/channel_chat_view.dart';
import '../dms/central_dm_chat_view.dart';
import '../dms/server_dm_chat_view.dart';
import 'pages/mobile_call_page.dart';
import 'pages/mobile_friends_page.dart';

/// One pushed page on a phone, on the content surface and clear of the
/// display's cutouts.
///
/// Every page is the same widget a desktop shows in its centre pane. Nothing
/// here decides what a chat looks like — only that it is standing on its own.
class MobilePageView extends StatelessWidget {
  final MobilePage page;

  const MobilePageView({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.theme.bgContent,
      // The shell's own scaffold already makes room for the keyboard; a second
      // one doing it too would lift the composer twice as far.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: switch (page) {
          MobilePage.call => const MobileCallPage(),
          MobilePage.channelChat => const ChannelChatView(),
          MobilePage.serverDm => const ServerDmChatView(),
          MobilePage.centralDm => const CentralDmChatView(),
          MobilePage.friends => const MobileFriendsPage(),
        },
      ),
    );
  }
}
