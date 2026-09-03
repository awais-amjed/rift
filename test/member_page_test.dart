import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/member_page.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';

ServerMember member(String id, String name) => ServerMember(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  permissions: const UserPermissions(),
);

void main() {
  group('MemberPage.cursor', () {
    test('names the last row, both halves of it', () {
      // Both halves because display names collide: a cursor of the name alone
      // would skip everybody else called the same thing.
      final page = MemberPage(
        members: [member('1', 'Ada'), member('2', 'Grace')],
        hasMore: true,
      );

      expect(page.cursor, (name: 'Grace', id: '2'));
    });

    test('is null when there is nothing to resume after', () {
      expect(MemberPage.empty.cursor, isNull);
    });
  });

  group('MemberPage.followedBy', () {
    test('appends, and takes the newer end-of-list answer', () {
      final first = MemberPage(members: [member('1', 'Ada')], hasMore: true);
      final second = MemberPage(
        members: [member('2', 'Grace')],
        hasMore: false,
      );

      final joined = first.followedBy(second);
      expect(joined.members.map((m) => m.displayName), ['Ada', 'Grace']);
      expect(joined.hasMore, isFalse);
    });

    test('a page that says there is more reopens a list that had ended', () {
      // The end-of-list answer is the newest thing known about the far end, so
      // it is taken from the incoming page rather than kept.
      final ended = MemberPage(members: [member('1', 'Ada')], hasMore: false);
      final more = MemberPage(members: [member('2', 'Grace')], hasMore: true);

      expect(ended.followedBy(more).hasMore, isTrue);
    });

    test('the cursor after appending points at the new last row', () {
      final joined = MemberPage(
        members: [member('1', 'Ada')],
        hasMore: true,
      ).followedBy(MemberPage(members: [member('2', 'Grace')], hasMore: true));

      expect(joined.cursor, (name: 'Grace', id: '2'));
    });

    test('an empty page does not move the cursor', () {
      final first = MemberPage(members: [member('1', 'Ada')], hasMore: true);
      final joined = first.followedBy(MemberPage.empty);

      expect(joined.cursor, (name: 'Ada', id: '1'));
      expect(joined.hasMore, isFalse);
    });
  });
}
