import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/apis/members_api.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/repositories/session_repository.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/search_dropdown_field.dart';
import '../../../../common/search_result_row.dart';

/// Starts a DM with a member of the selected server.
///
/// Unlike the central directory this is a set worth browsing, so focusing the
/// field lists people and typing narrows it. Both halves are the database's
/// answer (`search_members`): an empty query is the first
/// alphabetical page, and a query is a ranked search.
///
/// It used to fetch the roster once and filter it in Dart, memoised on the
/// grounds that a server's membership doesn't change between keystrokes. True,
/// and beside the point — the fetch was capped at 1000 rows, so on a large
/// server the field confidently answered "No members match that name" about
/// somebody sitting in the room. A filter can only be as complete as the list
/// under it, and that list is no longer one the client holds.
class MemberSearchField extends StatefulWidget {
  /// Forwarded to [SearchDropdownField.onOpenChanged] so the list behind can
  /// stand down while results are floating over it.
  final ValueChanged<bool>? onOpenChanged;

  const MemberSearchField({super.key, this.onOpenChanged});

  @override
  State<MemberSearchField> createState() => _MemberSearchFieldState();
}

class _MemberSearchFieldState extends State<MemberSearchField> {
  Future<List<ServerMember>> _search(String query) async {
    // Read before awaiting: reaching back through the context afterwards
    // would be a use-after-dispose if the panel closed mid-flight.
    final myId = context.read<ServerCubit>().state.selectedServer?.user?.id;
    final members = MembersApi(session: context.read<SessionRepository>());
    // Bots included, because a DM to a bot is a conversation like any other
    // — sealed between the two of you, unreadable by the server, and the one
    // way to say something to a bot that the rest of a channel does not see
    // (BOTS.md §3). Excluding them here was the only thing standing between
    // that and the app: the database allows it and the bot SDK is written
    // around answering it.
    final results = await members.searchMembers(query: query);
    return [
      for (final member in results)
        if (member.id != myId) member,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SearchDropdownField<ServerMember>(
      hintText: 'Find a member…',
      onOpenChanged: widget.onOpenChanged,
      emptyMessage: 'No members match that name.',
      openOnFocus: true,
      onSearch: _search,
      itemBuilder: (context, member, dismiss) => SearchResultRow(
        name: member.displayName,
        seed: member.id,
        imageUrl: member.avatarPath,
        trailingNote: 'no keys yet',
        // Someone who has never opened the app has published no chat key, so
        // there is nothing to encrypt to yet.
        onTap: member.chatPublicKey == null
            ? null
            : () {
                dismiss();
                // Only one DM surface is open at a time.
                context.read<CentralDmCubit>().closeConversation();
                context.read<DmCubit>().openConversation(
                  peerId: member.id,
                  peerName: member.displayName,
                  peerChatKey: member.chatPublicKey,
                );
              },
      ),
    );
  }
}
