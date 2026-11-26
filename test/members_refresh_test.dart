import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/members_refresh.dart';

Map<String, dynamic> _row(String id, String name) => {
  'id': id,
  'username': name.toLowerCase(),
  'display_name': name,
};

void main() {
  // The answer to a `members` ring (062), as the repository hands it over.
  group('MembersRefresh.fromJson', () {
    test('reads the bots, the members, the counts, the roles and chips', () {
      final read = MembersRefresh.fromJson({
        'bots': {
          'users': [_row('b1', 'MusicBot')],
          'has_more': false,
        },
        'members': {
          'users': [_row('u1', 'Ada')],
        },
        'counts': {'people': 12, 'bots': 1},
        'roles': [
          {'id': 'r1', 'name': 'Mods', 'position': 5},
          {'id': 'r0', 'name': '@everyone', 'position': 0, 'is_everyone': true},
        ],
        'assignments': [
          {'user_id': 'u1', 'role_id': 'r1', 'name': 'Mods', 'position': 5},
        ],
      });

      expect(read.bots.members.single.id, 'b1');
      expect(read.bots.hasMore, isFalse);
      expect(read.members.single.displayName, 'Ada');
      expect(read.peopleCount, 12);
      expect(read.roles.map((r) => r.id), ['r1', 'r0']);
      expect(read.memberRoles['u1']!.single.id, 'r1');
      // Somebody asked about who holds nothing is simply absent here; the
      // cubit records them as holding nothing.
      expect(read.memberRoles.containsKey('b1'), isFalse);
    });

    test('a page of bots with more behind it says so', () {
      final read = MembersRefresh.fromJson({
        'bots': {'users': <Map<String, dynamic>>[], 'has_more': true},
        'members': {'users': <Map<String, dynamic>>[]},
      });
      expect(read.bots.hasMore, isTrue);
      expect(read.peopleCount, 0);
      expect(read.roles, isEmpty);
    });
  });
}
