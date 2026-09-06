import '../../../../../data/classes/user_permissions.dart';
import '../../../../../data/enums/server_permission.dart';

/// The pages of the manage-server dialog, in nav order.
enum ServerManageTab {
  overview,
  roles,
  members,
  invites,
  bots,
  webhooks,
  danger,
}

/// Which pages somebody gets, decided on what they hold.
///
/// One place rather than a condition per nav row, because the same answer
/// decides whether the dialog is worth opening at all: the rail's menu offers
/// "Manage server" only to somebody who would see more than the way out.
class ServerManageTabs {
  const ServerManageTabs._();

  static List<ServerManageTab> visible(UserPermissions? permissions) {
    final p = permissions ?? const UserPermissions();
    return [
      if (p.isServerAdmin) ServerManageTab.overview,
      // Everybody may read the roles; editing them is gated inside.
      ServerManageTab.roles,
      if (p.isServerAdmin || p.isChannelManager) ServerManageTab.members,
      if (p.can(ServerPermission.createInvite)) ServerManageTab.invites,
      if (p.can(ServerPermission.manageBots)) ServerManageTab.bots,
      if (p.can(ServerPermission.manageWebhooks)) ServerManageTab.webhooks,
      ServerManageTab.danger,
    ];
  }

  /// Whether there is anything here beyond looking and leaving.
  static bool worthOpening(UserPermissions? permissions) => visible(
    permissions,
  ).any((t) => t != ServerManageTab.roles && t != ServerManageTab.danger);
}
