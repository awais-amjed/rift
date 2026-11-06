import 'package:equatable/equatable.dart';

import '../../logic/services/role_ladder.dart';
import 'member_page.dart';
import 'role.dart';
import 'server_member.dart';

/// All the member sidebar's first frame needs, from one request
/// (`member_sidebar`): the first page of bots and of people, how many people
/// there are, the roles, and which of those the rows here hold.
class MemberSidebar extends Equatable {
  final MemberPage bots;
  final MemberPage people;
  final int peopleCount;
  final List<Role> roles;
  final Map<String, List<Role>> memberRoles;

  const MemberSidebar({
    required this.bots,
    required this.people,
    required this.peopleCount,
    required this.roles,
    required this.memberRoles,
  });

  @override
  List<Object?> get props => [bots, people, peopleCount, roles, memberRoles];

  factory MemberSidebar.fromJson(Map<String, dynamic> json) {
    MemberPage page(String key) {
      final data = json[key] as Map<String, dynamic>;
      return MemberPage(
        members: ServerMember.listFrom(data),
        hasMore: data['has_more'] == true,
      );
    }

    final counts = json['counts'] as Map<String, dynamic>? ?? const {};
    return MemberSidebar(
      bots: page('bots'),
      people: page('people'),
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
