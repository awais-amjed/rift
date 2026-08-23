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
/// Unlike the central directory this is a bounded set worth browsing, so
/// focusing the field lists everyone and typing narrows it. The roster is
/// fetched once and filtered locally — a server's membership doesn't change
/// between keystrokes.
class MemberSearchField extends StatefulWidget {
  /// Forwarded to [SearchDropdownField.onOpenChanged] so the list behind can
  /// stand down while results are floating over it.
  final ValueChanged<bool>? onOpenChanged;

  const MemberSearchField({super.key, this.onOpenChanged});

  @override
  State<MemberSearchField> createState() => _MemberSearchFieldState();
}

class _MemberSearchFieldState extends State<MemberSearchField> {
  /// The in-flight *or* settled roster fetch — not the roster itself.
  ///
  /// Holding the list instead meant every search that started before the
  /// first one came back still saw it empty and launched its own fetch, so
  /// each keystroke kicked off another full round trip and only the newest
  /// was ever rendered. One future, assigned before anything is awaited, is
  /// what makes the second search wait on the first instead of racing it.
  Future<List<ServerMember>>? _roster;

  Future<List<ServerMember>> _search(String query) async {
    // Read before awaiting: reaching back through the context afterwards
    // would be a use-after-dispose if the panel closed mid-flight.
    final myId = context.read<ServerCubit>().state.selectedServer?.user?.id;
    final roster = await (_roster ??= _load());
    final q = query.trim().toLowerCase();
    return roster
        .where(
          (m) =>
              m.id != myId &&
              !m.isBanned &&
              (q.isEmpty || m.displayName.toLowerCase().contains(q)),
        )
        .toList();
  }

  Future<List<ServerMember>> _load() async {
    final result = await context.read<ServerCubit>().listMembers();
    final members = result.members;
    if (members == null) {
      // Don't let a failed fetch be the answer forever — drop the memo so the
      // next keystroke tries again rather than showing an empty roster.
      _roster = null;
      return const [];
    }
    return members;
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
