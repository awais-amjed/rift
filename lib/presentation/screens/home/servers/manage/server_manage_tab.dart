import '../../../../../data/classes/user_permissions.dart';
import '../../../../../data/enums/server_permission.dart';

/// The pages of the manage-server dialog, in nav order.
enum ServerManageTab {
  overview,
  voice,
  limits,
  roles,
  members,
  bots,
  webhooks,
  soundboard,
  danger,
}

/// What each page is called.
///
/// On the enum rather than inside the nav, because the nav is no longer the
/// only thing that names a page: on a phone the page's own name is the
/// headline at the top of it.
extension ServerManageTabLabel on ServerManageTab {
  String get label => switch (this) {
    ServerManageTab.overview => 'Overview',
    ServerManageTab.voice => 'Regions',
    ServerManageTab.limits => 'Limits',
    ServerManageTab.roles => 'Roles',
    ServerManageTab.members => 'Members',
    ServerManageTab.bots => 'Bots',
    ServerManageTab.webhooks => 'Webhooks',
    ServerManageTab.soundboard => 'Soundboard',
    ServerManageTab.danger => 'Danger zone',
  };
}

/// Which pages somebody gets, decided on what they hold.
///
/// One place rather than a condition per nav row. The dialog is for the
/// people running the place: an administrator gets all of it, a channel
/// manager the members (and any bot or webhook page their bits open), and
/// the last page is the owner's alone. Inviting and leaving are not in here
/// at all — they are the rail menu's, as they always were, because they are
/// things a member does rather than things a server is managed by.
class ServerManageTabs {
  const ServerManageTabs._();

  static List<ServerManageTab> visible(UserPermissions? permissions) {
    final p = permissions ?? const UserPermissions();
    return [
      if (p.isServerAdmin) ServerManageTab.overview,
      if (p.isServerAdmin) ServerManageTab.voice,
      if (p.isServerAdmin) ServerManageTab.limits,
      if (p.isServerAdmin) ServerManageTab.roles,
      if (p.isServerAdmin || p.isChannelManager) ServerManageTab.members,
      if (p.can(ServerPermission.manageBots)) ServerManageTab.bots,
      if (p.can(ServerPermission.manageWebhooks)) ServerManageTab.webhooks,
      if (p.can(ServerPermission.manageSoundboard)) ServerManageTab.soundboard,
      if (p.isOwner) ServerManageTab.danger,
    ];
  }
}
