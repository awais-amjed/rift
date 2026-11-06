import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/member_sidebar.dart';

Map<String, dynamic> person(String id) => {
  'id': id,
  'username': id,
  'display_name': id,
};

/// What `member_sidebar` answers, after the repository has split each list.
void main() {
  test('it reads as the five requests it replaces', () {
    final sidebar = MemberSidebar.fromJson({
      'bots': {
        'users': [person('robot')],
        'has_more': false,
      },
      'people': {
        'users': [person('amy'), person('ben')],
        'has_more': true,
      },
      'counts': {'people': 120, 'bots': 1},
      'roles': [
        {'id': 'r2', 'name': 'Moderator', 'position': 200},
        {'id': 'r1', 'name': 'everyone', 'position': 0, 'is_everyone': true},
      ],
      'assignments': [
        {'user_id': 'amy', 'role_id': 'r1', 'name': 'Low', 'position': 1},
        {'user_id': 'amy', 'role_id': 'r2', 'name': 'High', 'position': 200},
      ],
    });

    expect(sidebar.bots.members.single.id, 'robot');
    expect(sidebar.bots.hasMore, isFalse);
    expect(sidebar.people.members.map((m) => m.id), ['amy', 'ben']);
    expect(sidebar.people.hasMore, isTrue);
    expect(sidebar.peopleCount, 120);
    expect(sidebar.roles.map((r) => r.id), ['r2', 'r1']);
    expect(sidebar.memberRoles['amy']!.first.id, 'r2', reason: 'senior first');
    expect(sidebar.memberRoles['ben'], isNull);
  });

  test('a server with nobody yet is empty, not a failure', () {
    final sidebar = MemberSidebar.fromJson({
      'bots': {'users': <Object>[], 'has_more': false},
      'people': {'users': <Object>[], 'has_more': false},
      'counts': {'people': 0, 'bots': 0},
      'roles': <Object>[],
      'assignments': <Object>[],
    });

    expect(sidebar.people.members, isEmpty);
    expect(sidebar.peopleCount, 0);
    expect(sidebar.memberRoles, isEmpty);
  });
}
