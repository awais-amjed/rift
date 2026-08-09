import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/presentation/common/server_role.dart';

/// The Members dialog and the participant context menu both hand these out, so
/// the wording and the reads live in one place. A role that read the wrong flag
/// would show a tick against a permission the member doesn't hold — and the
/// next click would then "revoke" something they never had.
void main() {
  test('each role reads its own flag', () {
    const admin = UserPermissions(isServerAdmin: true);
    const manager = UserPermissions(isChannelManager: true);
    const inviter = UserPermissions(canCreateTokens: true);

    expect(ServerRole.admin.isHeldBy(admin), isTrue);
    expect(ServerRole.channelManager.isHeldBy(admin), isFalse);
    expect(ServerRole.invites.isHeldBy(admin), isFalse);

    expect(ServerRole.channelManager.isHeldBy(manager), isTrue);
    expect(ServerRole.admin.isHeldBy(manager), isFalse);

    expect(ServerRole.invites.isHeldBy(inviter), isTrue);
    expect(ServerRole.admin.isHeldBy(inviter), isFalse);
  });

  test('a member with nothing holds no role', () {
    const none = UserPermissions();
    for (final role in ServerRole.values) {
      expect(role.isHeldBy(none), isFalse, reason: role.label);
    }
  });

  test('a member with everything holds all of them', () {
    const all = UserPermissions(
      isServerAdmin: true,
      isChannelManager: true,
      canCreateTokens: true,
    );
    for (final role in ServerRole.values) {
      expect(role.isHeldBy(all), isTrue, reason: role.label);
    }
  });

  test('labels are distinct, so a menu never shows the same row twice', () {
    final labels = ServerRole.values.map((r) => r.label).toSet();
    expect(labels.length, ServerRole.values.length);
  });
}
