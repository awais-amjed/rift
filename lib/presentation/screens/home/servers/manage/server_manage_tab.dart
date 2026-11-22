import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/user_permissions.dart';
import '../../../../../data/enums/server_permission.dart';

/// The pages of the manage-server dialog, in nav order.
enum ServerManageTab {
  overview,
  voice,
  limits,
  roles,
  members,
  invites,
  reports,
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
    ServerManageTab.invites => 'Invites',
    ServerManageTab.reports => 'Reports',
    ServerManageTab.bots => 'Bots',
    ServerManageTab.webhooks => 'Webhooks',
    ServerManageTab.soundboard => 'Soundboard',
    ServerManageTab.danger => 'Danger zone',
  };

  IconData get icon => switch (this) {
    ServerManageTab.overview => Icons.tune_rounded,
    ServerManageTab.voice => Icons.public_rounded,
    ServerManageTab.limits => Icons.speed_rounded,
    ServerManageTab.roles => Icons.shield_outlined,
    ServerManageTab.members => Icons.group_outlined,
    ServerManageTab.invites => Icons.link_rounded,
    ServerManageTab.reports => Icons.flag_outlined,
    ServerManageTab.bots => Icons.smart_toy_outlined,
    ServerManageTab.webhooks => Icons.webhook_rounded,
    ServerManageTab.soundboard => Icons.campaign_rounded,
    ServerManageTab.danger => Icons.warning_amber_rounded,
  };
}

/// Which pages somebody gets, decided on what they hold.
///
/// One place rather than a condition per nav row. The dialog is for the
/// people running the place: an administrator gets all of it, a channel
/// manager the members (and any bot or webhook page their bits open), and
/// the last page is the owner's alone. Making an invite and leaving are not in
/// here — they are the rail menu's, as they always were, because they are
/// things a member does rather than things a server is managed by. The list
/// of links already made, and revoking one, is an administrator's page.
class ServerManageTabs {
  const ServerManageTabs._();

  static List<ServerManageTab> visible(UserPermissions? permissions) {
    final p = permissions ?? const UserPermissions();
    return [
      if (p.isServerAdmin) ServerManageTab.overview,
      if (p.isServerAdmin) ServerManageTab.voice,
      if (p.isServerAdmin) ServerManageTab.limits,
      if (p.isServerAdmin) ServerManageTab.roles,
      // The ban list is where a ban is lifted, so kicking or banning alone
      // opens it too.
      if (p.isServerAdmin ||
          p.isChannelManager ||
          p.can(ServerPermission.kickMembers) ||
          p.can(ServerPermission.banMembers))
        ServerManageTab.members,
      // Every link on the server is an administrator's to see and revoke
      // (`invites_select_admin`); a member reaches only their own.
      if (p.isServerAdmin) ServerManageTab.invites,
      if (p.can(ServerPermission.reviewReports)) ServerManageTab.reports,
      if (p.can(ServerPermission.manageBots)) ServerManageTab.bots,
      if (p.mayManageWebhooks) ServerManageTab.webhooks,
      if (p.can(ServerPermission.manageSoundboard)) ServerManageTab.soundboard,
      if (p.isOwner) ServerManageTab.danger,
    ];
  }
}
