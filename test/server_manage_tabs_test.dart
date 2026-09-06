import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/server_permission.dart';
import 'package:rift/presentation/screens/home/servers/manage/server_manage_tab.dart';

void main() {
  group('manage-server tabs', () {
    test('an ordinary member sees the roles and the way out, and no more', () {
      expect(ServerManageTabs.visible(const UserPermissions()), [
        ServerManageTab.roles,
        ServerManageTab.danger,
      ]);
      expect(ServerManageTabs.worthOpening(const UserPermissions()), isFalse);
    });

    test('an administrator sees everything, in nav order', () {
      const admin = UserPermissions(isServerAdmin: true);
      expect(ServerManageTabs.visible(admin), ServerManageTab.values);
      expect(ServerManageTabs.worthOpening(admin), isTrue);
    });

    test('a single permission opens exactly its page', () {
      final inviter = UserPermissions(
        bits: 0.with_(ServerPermission.createInvite),
      );
      expect(
        ServerManageTabs.visible(inviter),
        contains(ServerManageTab.invites),
      );
      expect(
        ServerManageTabs.visible(inviter),
        isNot(contains(ServerManageTab.members)),
      );
      expect(ServerManageTabs.worthOpening(inviter), isTrue);
    });

    test('a channel manager gets members without the overview', () {
      const mod = UserPermissions(isChannelManager: true);
      final tabs = ServerManageTabs.visible(mod);
      expect(tabs, contains(ServerManageTab.members));
      expect(tabs, isNot(contains(ServerManageTab.overview)));
    });
  });
}
