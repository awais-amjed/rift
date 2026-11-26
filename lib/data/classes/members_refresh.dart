import 'package:equatable/equatable.dart';

import '../../logic/services/role_ladder.dart';
import 'member_page.dart';
import 'role.dart';
import 'server_member.dart';

/// What the member list re-reads when `members` rings, from one request
/// (`members_refresh`): the first page of bots, the members asked about, how
/// many people there are, the roles, and which of those the rows here hold.
class MembersRefresh extends Equatable {
  final MemberPage bots;
  final List<ServerMember> members;
  final int peopleCount;
  final List<Role> roles;
  final Map<String, List<Role>> memberRoles;

  const MembersRefresh({
    required this.bots,
    required this.members,
    required this.peopleCount,
    required this.roles,
    required this.memberRoles,
  });

  @override
  List<Object?> get props => [bots, members, peopleCount, roles, memberRoles];

  factory MembersRefresh.fromJson(Map<String, dynamic> json) {
    final bots = json['bots'] as Map<String, dynamic>;
    final counts = json['counts'] as Map<String, dynamic>? ?? const {};
    return MembersRefresh(
      bots: MemberPage(
        members: ServerMember.listFrom(bots),
        hasMore: bots['has_more'] == true,
      ),
      members: ServerMember.listFrom(json['members']),
      peopleCount: (counts['people'] as num?)?.toInt() ?? 0,
      roles: [
        for (final row in (json['roles'] as List? ?? const []))
          Role.fromJson(row as Map<String, dynamic>),
      ],
      memberRoles: RoleLadder.byUser(
        (json['assignments'] as List? ?? const []).cast<Map<String, dynamic>>(),
      ),
    );
  }
}
