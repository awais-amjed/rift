import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/server_permission.dart';
import 'package:rift/presentation/screens/home/servers/manage/server_manage_tab.dart';

void main() {
  group('manage-server tabs', () {
    test('an ordinary member has nothing to manage', () {
      expect(ServerManageTabs.visible(const UserPermissions()), isEmpty);
    });

    test('an administrator sees everything but the owner\'s page', () {
      const admin = UserPermissions(isServerAdmin: true);
      expect(ServerManageTabs.visible(admin), [
        ServerManageTab.overview,
        ServerManageTab.voice,
        ServerManageTab.limits,
        ServerManageTab.roles,
        ServerManageTab.members,
        ServerManageTab.bots,
        ServerManageTab.webhooks,
        ServerManageTab.soundboard,
      ]);
    });

    test('the owner gets the last page too, in nav order', () {
      const owner = UserPermissions(isServerAdmin: true, isOwner: true);
      expect(ServerManageTabs.visible(owner), ServerManageTab.values);
    });

    test('a channel manager gets members, not the overview or roles', () {
      const mod = UserPermissions(isChannelManager: true);
      expect(ServerManageTabs.visible(mod), [ServerManageTab.members]);
    });

    test('inviting alone opens no page: that is the rail menu\'s', () {
      final inviter = UserPermissions(
        bits: 0.with_(ServerPermission.createInvite),
      );
      expect(ServerManageTabs.visible(inviter), isEmpty);
    });
  });
}
