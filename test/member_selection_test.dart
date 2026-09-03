import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/member_selection.dart';

ServerMember member(String id, String name) => ServerMember(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  permissions: const UserPermissions(),
);

void main() {
  group('MemberSelection', () {
    test('toggling adds, then removes', () {
      final ada = member('1', 'Ada');
      final once = MemberSelection.empty.toggled(ada);
      expect(once.ids, {'1'});
      expect(once.members.single.displayName, 'Ada');

      final twice = once.toggled(ada);
      expect(twice.ids, isEmpty);
      expect(twice.members, isEmpty);
    });

    test('the rows travel with the ids', () {
      // The whole reason this type exists. Holding ids alone was fine while
      // the roster sat in memory; now somebody ticked may be in no page on
      // screen, and a picker that cannot draw them drops them on save.
      final selection = MemberSelection.empty
          .toggled(member('1', 'Ada'))
          .toggled(member('2', 'Grace'));

      expect(selection.members.map((m) => m.displayName), ['Ada', 'Grace']);
    });

    test('removing one leaves the others in order', () {
      final selection = MemberSelection.empty
          .toggled(member('1', 'Ada'))
          .toggled(member('2', 'Grace'))
          .toggled(member('3', 'Zoe'))
          .toggled(member('2', 'Grace'));

      expect(selection.ids, {'1', '3'});
      expect(selection.members.map((m) => m.displayName), ['Ada', 'Zoe']);
    });

    test('it is immutable — the old value is untouched', () {
      final before = MemberSelection.of([member('1', 'Ada')]);
      before.toggled(member('2', 'Grace'));

      expect(before.ids, {'1'});
    });

    test('a tick and an untick is not a change', () {
      // What decides whether Save is offered. Getting it wrong offers to write
      // what is already there.
      final original = {'1', '2'};
      final selection = MemberSelection.of([
        member('1', 'Ada'),
        member('2', 'Grace'),
      ]);

      expect(selection.differsFrom(original), isFalse);
      expect(
        selection.toggled(member('3', 'Zoe')).differsFrom(original),
        isTrue,
      );
      expect(
        selection
            .toggled(member('3', 'Zoe'))
            .toggled(member('3', 'Zoe'))
            .differsFrom(original),
        isFalse,
      );
    });

    test('swapping one person for another is a change', () {
      // Same size, different people — a length check alone would miss it.
      final selection = MemberSelection.of([member('1', 'Ada')]);
      expect(selection.differsFrom({'2'}), isTrue);
    });
  });
}
