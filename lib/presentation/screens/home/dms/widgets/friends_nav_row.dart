import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/nav_row.dart';
import '../../../../common/unread_badge.dart';
import '../../../../responsive/shell_scope.dart';

/// The row at the top of the central column that opens the friends page.
///
/// It is *selected* whenever no conversation is open, because the friends page
/// is what the content pane rests on — Home with nothing open is your people,
/// not an empty panel apologising for being empty. Tapping it closes whatever
/// conversation is open, which is the only way back.
///
/// The badge counts incoming requests, and only those. An outgoing one is not
/// news; waiting is not something to be notified about.
class FriendsNavRow extends StatelessWidget {
  const FriendsNavRow({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<CentralDmCubit>().state;
    final requests = state.friends.requestCount;

    return NavRow(
      icon: Icons.people_alt_outlined,
      label: 'Friends',
      // On a desktop the friends page is what "nothing open" shows, so no
      // conversation is the same statement. A phone's empty pane is the
      // conversation list instead, and there the flag is the only thing that
      // knows.
      isSelected:
          state.openPeerId == null &&
          (state.friendsOpen || !context.layoutMode.isCompact),
      isUnread: requests > 0,
      trailing: requests > 0
          ? UnreadBadge(count: requests, themeState: themeState)
          : null,
      onTap: () => context.read<CentralDmCubit>().openFriends(),
    );
  }
}
