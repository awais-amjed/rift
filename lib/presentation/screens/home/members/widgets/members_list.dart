import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../common/list_loading_footer.dart';
import 'member_row.dart';

/// The roster inside the members dialog: one [MemberRow] per member, and the
/// rules about which of them the viewer may act on.
///
/// Those rules live here rather than in each row because they are all about the
/// *viewer* — who they are and what they may do — which no single row knows.
class MembersList extends StatelessWidget {
  final List<ServerMember> members;

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

  /// Holds Kick members or Ban members, which open a row on their own.
  final bool viewerCanRemove;

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
    bool kick,
  })
  onModerate;

  const MembersList({
    super.key,
    required this.members,
    required this.hasMore,
    required this.onLoadMore,
    required this.memberRoles,
    required this.viewerId,
    required this.viewerIsAdmin,
    required this.viewerIsModerator,
    this.viewerCanRemove = false,
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
      child: _buildList(context),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      itemCount: members.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == members.length) return const ListLoadingFooter();
        final member = members[index];
        final isSelf = member.id == viewerId;

        return MemberRow(
          member: member,
          isSelf: isSelf,
          isExpanded: expandedId == member.id,
          isBusy: busyId == member.id,
          // Named for what it now gates: the Roles row and the ban button.
          // On your own row only Roles: the server lets an admin give
          // themselves a role, or drop one beneath their top, and nowhere
          // else offered it. Kick and ban refuse a self-edit, so the panel
          // leaves them off ([MemberManagePanel.isSelf]).
          canManagePermissions: viewerIsAdmin,
          // Moderators mute/deafen non-admins.
          canModerate:
              viewerIsModerator && !isSelf && !member.permissions.isServerAdmin,
          // Not yourself, and not an admin: the server refuses both.
          canRemove:
              viewerCanRemove && !isSelf && !member.permissions.isServerAdmin,
          roles: memberRoles[member.id] ?? const [],
          onTap: () => onTap(member),
          onModerate: ({muted, deafened, banned, kick = false}) => onModerate(
            member,
            muted: muted,
            deafened: deafened,
            banned: banned,
            kick: kick,
          ),
        );
      },
    );
  }
}
