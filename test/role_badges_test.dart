import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/role.dart';
import 'package:rift/logic/services/role_ladder.dart';

/// Which roles earn a chip beside somebody's name.
///
/// Every member is given the default role when they register, so a chip for it
/// appeared on every row in the server — saying, next to every name, what was
/// true of everybody. A badge that never varies is not a badge.
void main() {
  Role role(String name, {bool isDefault = false, bool isEveryone = false}) =>
      Role(
        id: name,
        name: name,
        position: 0,
        permissions: 0,
        isDefault: isDefault,
        isEveryone: isEveryone,
      );

  test('the default role never earns one', () {
    final badges = RoleLadder.badges([role('Members', isDefault: true)]);
    expect(badges, isEmpty);
  });

  test('a role somebody was actually given does', () {
    final badges = RoleLadder.badges([
      role('Admin'),
      role('Members', isDefault: true),
    ]);
    expect(badges.map((r) => r.name), ['Admin']);
  });

  test('order is kept, so the most senior is still first', () {
    // The sidebar takes the first of these as the one chip it shows.
    final badges = RoleLadder.badges([
      role('Admin'),
      role('Moderator'),
      role('Members', isDefault: true),
    ]);
    expect(badges.map((r) => r.name), ['Admin', 'Moderator']);
  });

  test('a member with nothing but the default shows nothing', () {
    // The common case, and the whole point: most people are just members.
    expect(RoleLadder.badges([role('Members', isDefault: true)]), isEmpty);
  });

  test('@everyone is not special here', () {
    // It is never in an assignment list to begin with — it applies implicitly,
    // so it has no `member_roles` row. If one ever appeared it would be shown,
    // and that would be a bug somewhere else.
    final badges = RoleLadder.badges([role('@everyone', isEveryone: true)]);
    expect(badges.map((r) => r.name), ['@everyone']);
  });
}
