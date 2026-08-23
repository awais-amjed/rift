import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import 'member_row.dart';

/// The roster inside the members dialog: one [MemberRow] per member, and the
/// rules about which of them the viewer may act on.
///
/// Those rules live here rather than in each row because they are all about the
/// *viewer* — who they are and what they may do — which no single row knows.
class MembersList extends StatelessWidget {
  final List<ServerMember> members;

  /// The viewer's own member id, so their row can refuse to act on itself: the
  /// server rejects self-edits, so offering them is a wasted trip.
  final String? viewerId;

  final bool viewerIsAdmin;
  final bool viewerIsModerator;

  /// Which row is open, and which is waiting on a call.
  final String? expandedId;
  final String? busyId;

  final void Function(ServerMember member) onTap;
  final void Function(
    ServerMember member, {
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  })
  onPermissionChanged;
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
    required this.viewerId,
    required this.viewerIsAdmin,
    required this.viewerIsModerator,
    required this.expandedId,
    required this.busyId,
    required this.onTap,
    required this.onPermissionChanged,
    required this.onModerate,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final isSelf = member.id == viewerId;

        return MemberRow(
          member: member,
          isSelf: isSelf,
          isExpanded: expandedId == member.id,
          isBusy: busyId == member.id,
          // Admins manage permissions for everyone but themselves (the server
          // rejects self-edits).
          canManagePermissions: viewerIsAdmin && !isSelf,
          // Moderators mute/deafen non-admins.
          canModerate:
              viewerIsModerator && !isSelf && !member.permissions.isServerAdmin,
          onTap: () => onTap(member),
          onPermissionChanged:
              ({isServerAdmin, isChannelManager, canCreateTokens}) =>
                  onPermissionChanged(
                    member,
                    isServerAdmin: isServerAdmin,
                    isChannelManager: isChannelManager,
                    canCreateTokens: canCreateTokens,
                  ),
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
}
