import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/member_roster.dart';

ServerMember member(
  String id,
  String name, {
  bool isBanned = false,
  UserPermissions permissions = const UserPermissions(),
}) => ServerMember(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  permissions: permissions,
  isBanned: isBanned,
);

void main() {
  group('MemberRoster.split', () {
    test('groups by presence', () {
      final result = MemberRoster.split(
        [member('1', 'Ana'), member('2', 'Bo'), member('3', 'Cy')],
        {'1', '3'},
      );
      expect(result.online.map((m) => m.displayName), ['Ana', 'Cy']);
      expect(result.offline.map((m) => m.displayName), ['Bo']);
    });

    test('sorts each group by display name, case-insensitively', () {
      final result = MemberRoster.split(
        [member('1', 'zoe'), member('2', 'Ana'), member('3', 'mia')],
        {'1', '2', '3'},
      );
      expect(result.online.map((m) => m.displayName), ['Ana', 'mia', 'zoe']);
    });

    test('drops banned members from both groups', () {
      final result = MemberRoster.split(
        [
          member('1', 'Ana', isBanned: true),
          member('2', 'Bo', isBanned: true),
          member('3', 'Cy'),
        ],
        {'1', '3'},
      );
      expect(result.online.map((m) => m.id), ['3']);
      expect(result.offline, isEmpty);
    });

    test('an online id with no member row is ignored, not invented', () {
      final result = MemberRoster.split([member('1', 'Ana')], {'1', 'ghost'});
      expect(result.online, hasLength(1));
      expect(result.offline, isEmpty);
    });

    test('nobody online puts everyone in offline', () {
      final result = MemberRoster.split([
        member('1', 'Ana'),
        member('2', 'Bo'),
      ], const {});
      expect(result.online, isEmpty);
      expect(result.offline, hasLength(2));
    });

    test('an empty member list yields two empty groups', () {
      final result = MemberRoster.split(const [], {'1'});
      expect(result.online, isEmpty);
      expect(result.offline, isEmpty);
    });
  });
}
