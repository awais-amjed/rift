import 'package:flutter_test/flutter_test.dart';
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
      final state = ServerMembersState(members: [_member('u1', 'Test3')]);

      expect(state.nameFor('u1', 'Test2'), 'Test3');
    });

    test('an unknown user keeps the name the transport carried', () {
      final state = ServerMembersState(members: [_member('u1', 'Test3')]);

      // Someone who joined the call seconds ago, before our refetch landed.
      expect(state.nameFor('u2', 'Newcomer'), 'Newcomer');
    });

    test('a roster that has not loaded yet falls back rather than blanking', () {
      expect(ServerMembersState().nameFor('u1', 'Test2'), 'Test2');
    });

    test('byId indexes every member', () {
      final state = ServerMembersState(
        members: [_member('u1', 'Alice'), _member('u2', 'Bob')],
      );

      expect(state.byId.keys, containsAll(<String>['u1', 'u2']));
      expect(state.byId['u2']!.displayName, 'Bob');
    });
  });
}
