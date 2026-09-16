import 'package:flutter/material.dart';

import '../../chat/widgets/header_pane_buttons.dart';
import '../../dms/central_friends_view.dart';

/// Friends, as a page of its own: the way back, then the page a desktop shows
/// when nothing is open on Home.
class MobileFriendsPage extends StatelessWidget {
  const MobileFriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: HeaderBackButton(),
          ),
        ),
        Expanded(child: CentralFriendsView()),
      ],
    );
  }
}
