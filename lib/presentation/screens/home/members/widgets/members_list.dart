import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/loading_dots.dart';
import 'member_row.dart';
import '../../../../../data/classes/role.dart';

/// The roster inside the members dialog: one [MemberRow] per member, and the
/// rules about which of them the viewer may act on.
///
/// Those rules live here rather than in each row because they are all about the
/// *viewer* — who they are and what they may do — which no single row knows.
class MembersList extends StatelessWidget {
  final List<ServerMember> members;
  final ThemeState themeState;

  /// Whether another page of the roster exists. Draws a footer, and is what
  /// makes [onLoadMore] worth calling.
  final bool hasMore;

  /// Asked for when the list is scrolled near its end. Safe to fire often —
  /// `MemberRosterPager` drops a call made while one is already in flight,
  /// which is why the guard is not repeated here.
  final VoidCallback onLoadMore;

  /// The viewer's own member id, so their row can refuse to act on itself: the
  /// server rejects self-edits, so offering them is a wasted trip.
  final String? viewerId;

  final bool viewerIsAdmin;
  final bool viewerIsModerator;

  /// Which row is open, and which is waiting on a call.
  final String? expandedId;
  final String? busyId;

  /// Which roles each member holds, keyed by user id.
  final Map<String, List<Role>> memberRoles;

  final void Function(ServerMember member) onTap;
  final void Function(
    ServerMember member, {
    bool? muted,
    bool? deafened,
    bool? banned,
  })
  onModerate;

  const MembersList({
    super.key,
    required this.members,
    required this.themeState,
    required this.hasMore,
    required this.onLoadMore,
    required this.memberRoles,
    required this.viewerId,
    required this.viewerIsAdmin,
    required this.viewerIsModerator,
    required this.expandedId,
    required this.busyId,
    required this.onTap,
    required this.onModerate,
  });

  /// How close to the bottom counts as "nearly there".
  ///
  /// Roughly two rows' worth, so the next page is asked for while there is
  /// still something to look at rather than when the list has already stopped.
  static const double _loadMoreSlack = 120;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore && notification.metrics.extentAfter < _loadMoreSlack) {
          onLoadMore();
        }
        // Never swallowed: the scrollbar and any parent listening for the same
        // notifications still need to see it.
        return false;
      },
      child: _buildList(),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      itemCount: members.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == members.length) return _buildFooter();
        final member = members[index];
        final isSelf = member.id == viewerId;

        return MemberRow(
          member: member,
          isSelf: isSelf,
          isExpanded: expandedId == member.id,
          isBusy: busyId == member.id,
          // Named for what it now gates: the Roles row and the ban button.
          // Both refuse a self-edit at the server, so neither is offered on
          // your own row.
          canManagePermissions: viewerIsAdmin && !isSelf,
          // Moderators mute/deafen non-admins.
          canModerate:
              viewerIsModerator && !isSelf && !member.permissions.isServerAdmin,
          roles: memberRoles[member.id] ?? const [],
          onTap: () => onTap(member),
          onModerate: ({muted, deafened, banned}) => onModerate(
            member,
            muted: muted,
            deafened: deafened,
            banned: banned,
          ),
        );
      },
    );
  }

  /// The spinner at the end of a page, which is also the thing whose appearing
  /// tells somebody the list has not simply stopped.
  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: LoadingDots(color: themeState.accentBright, dotSize: 5),
    ),
  );
}
