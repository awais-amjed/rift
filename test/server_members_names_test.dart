import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/member_page.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';

ServerMember _member(String id, String displayName) => ServerMember(
  id: id,
  username: displayName.toLowerCase(),
  displayName: displayName,
  permissions: const UserPermissions(),
);

void main() {
  group('ServerMembersState.nameFor', () {
    // A display name used to exist in three places at once: the `users` row,
    // the presence payload captured at track time, and the `name` claim baked
    // into a LiveKit token — which is cached for its full hour, so a rename
    // mid-call survived even a disconnect and reconnect. Everything that draws
    // a name now resolves it here instead.
    test('the roster wins over the name frozen into a token', () {
      final state = ServerMembersState(
        people: MemberPage(members: [_member('u1', 'Test3')], hasMore: false),
      );

      expect(state.nameFor('u1', 'Test3-stale'), 'Test3');
    });

    test('an unknown user keeps the name the transport carried', () {
      final state = ServerMembersState(
        people: MemberPage(members: [_member('u1', 'Test3')], hasMore: false),
      );

      // Someone who joined the call seconds ago, before our lookup landed.
      // Routine now that the roster pages: anybody far enough down the
      // alphabet is simply not in hand until `resolve` names them.
      expect(state.nameFor('u2', 'Newcomer'), 'Newcomer');
    });

    test(
      'a roster that has not loaded yet falls back rather than blanking',
      () {
        expect(ServerMembersState().nameFor('u1', 'Test2'), 'Test2');
      },
    );

    test('byId indexes every source the client knows about', () {
      // Three of them since the roster paged: the bots, whoever was resolved
      // by id, and the pages themselves. Somebody nameable from any of them
      // has to be nameable from here, or their row in a call goes blank.
      final state = ServerMembersState(
        bots: [_member('b1', 'MusicBot')],
        known: {'u3': _member('u3', 'Zoe')},
        people: MemberPage(
          members: [_member('u1', 'Alice'), _member('u2', 'Bob')],
          hasMore: true,
        ),
      );

      expect(state.byId.keys, containsAll(<String>['b1', 'u1', 'u2', 'u3']));
      expect(state.byId['u2']!.displayName, 'Bob');
      expect(state.nameFor('u3', 'stale'), 'Zoe');
    });

    test('a page wins over an older copy resolved by id', () {
      // They carry the same columns, but the page is the more recent read —
      // so a rename that arrived with a page must not be undone by a lookup
      // made before it.
      final state = ServerMembersState(
        known: {'u1': _member('u1', 'Old')},
        people: MemberPage(members: [_member('u1', 'New')], hasMore: false),
      );

      expect(state.nameFor('u1', 'fallback'), 'New');
    });
  });
}
