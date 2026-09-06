import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/search_dropdown_field.dart';
import '../../../../common/search_result_row.dart';

/// Starts a DM with a member of the selected server.
///
/// Unlike the central directory this is a set worth browsing, so focusing the
/// field lists people and typing narrows it. Both halves are the database's
/// answer (`search_members`, `011_directory.sql`): an empty query is the first
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
    final cubit = context.read<ServerCubit>();
    final myId = cubit.state.selectedServer?.user?.id;
    // Bots are excluded by the query rather than by a filter afterwards: a bot
    // has no DM inbox, and one dropped from a page after the fact would leave
    // the drop-down a row shorter than it asked for.
    final results = await cubit.searchMembers(query: query, bots: false);
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
