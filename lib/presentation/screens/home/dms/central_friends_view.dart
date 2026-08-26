import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import 'widgets/friends/add_friend_field.dart';
import 'widgets/friends/friends_list.dart';
import 'widgets/friends/friends_tab_bar.dart';

/// The friends page — what Home shows when no conversation is open.
///
/// It replaces the old resting state, which said "find someone by handle" over
/// an empty panel. That was a sentence where a screen should have been: the
/// people you know are the reason to be on this tier at all.
///
/// It is also the only way onto the tier now. Adding somebody is here, in the
/// field at the top, and nowhere else — the sidebar's handle search is gone,
/// because a field that answered three letters with a list of strangers was a
/// browsable index of everybody who had ever signed up.
///
/// Reached by the Friends row at the top of the column, which is selected
/// exactly when nothing else is.
class CentralFriendsView extends StatefulWidget {
  const CentralFriendsView({super.key});

  @override
  State<CentralFriendsView> createState() => _CentralFriendsViewState();
}

class _CentralFriendsViewState extends State<CentralFriendsView> {
  FriendsTab _tab = FriendsTab.friends;

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final graph = context.watch<CentralDmCubit>().state.graph;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Friends',
            style: AppText.sectionTitle.copyWith(color: themeState.textPrimary),
          ),
          const SizedBox(height: 14),
          const AddFriendField(),
          const SizedBox(height: 14),
          FriendsTabBar(
            current: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
            counts: {
              FriendsTab.friends: graph.friends.length,
              // Incoming only. An outgoing request is not something waiting
              // for you, and counting it here would make the number disagree
              // with the badge on the row that opened this page.
              FriendsTab.pending: graph.incoming.length,
              FriendsTab.blocked: graph.blocked.length,
            },
          ),
          Expanded(child: FriendsList(tab: _tab)),
        ],
      ),
    );
  }
}
