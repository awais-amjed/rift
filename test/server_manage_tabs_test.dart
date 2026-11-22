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
        ServerManageTab.reports,
        ServerManageTab.bots,
        ServerManageTab.webhooks,
        ServerManageTab.soundboard,
      ]);
    });

    test('reviewing reports alone opens the reports page and nothing else', () {
      final reviewer = UserPermissions(
        bits: ServerPermission.reviewReports.mask,
      );
      expect(ServerManageTabs.visible(reviewer), [ServerManageTab.reports]);
    });

    test('the owner gets the last page too, in nav order', () {
      const owner = UserPermissions(isServerAdmin: true, isOwner: true);
      expect(ServerManageTabs.visible(owner), ServerManageTab.values);
    });

    test('a channel manager gets members, not the overview or roles', () {
      // A server from before the bits: Manage channels is all there is, and
      // it is what the server asks of webhooks.
      const mod = UserPermissions(isChannelManager: true);
      expect(ServerManageTabs.visible(mod), [
        ServerManageTab.members,
        ServerManageTab.webhooks,
      ]);
    });

    test('kicking or banning alone opens members, where a ban is lifted', () {
      final banner = UserPermissions(bits: ServerPermission.banMembers.mask);
      expect(ServerManageTabs.visible(banner), [ServerManageTab.members]);
      final kicker = UserPermissions(bits: ServerPermission.kickMembers.mask);
      expect(ServerManageTabs.visible(kicker), [ServerManageTab.members]);
    });

    test('webhooks need Manage channels too, which the server asks', () {
      final hooksOnly = UserPermissions(
        bits: ServerPermission.manageWebhooks.mask,
      );
      expect(
        ServerManageTabs.visible(hooksOnly),
        isNot(contains(ServerManageTab.webhooks)),
      );
      final both = UserPermissions(
        isChannelManager: true,
        bits: ServerPermission.manageWebhooks.mask.with_(
          ServerPermission.manageChannels,
        ),
      );
      expect(
        ServerManageTabs.visible(both),
        contains(ServerManageTab.webhooks),
      );
      final channelsOnly = UserPermissions(
        isChannelManager: true,
        bits: ServerPermission.manageChannels.mask,
      );
      expect(
        ServerManageTabs.visible(channelsOnly),
        isNot(contains(ServerManageTab.webhooks)),
      );
    });

    test('inviting alone opens no page: that is the rail menu\'s', () {
      final inviter = UserPermissions(
        bits: 0.with_(ServerPermission.createInvite),
      );
      expect(ServerManageTabs.visible(inviter), isEmpty);
    });
  });
}
