import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/unread_dot.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../sidebar/widgets/sidebar_header.dart';
import 'switcher_home_line.dart';
import 'switcher_home_mark.dart';
import 'switcher_server_line.dart';

/// The top of a phone's list: where you are, and the way to anywhere else.
///
/// An app bar, not a field. It used to be a bordered box with a stepper glyph,
/// which read as a settings dropdown and promised stepping through servers in
/// place when what opens is a panel from the side. Now the name is the bar's
/// title with a chevron against it — "this title is a menu" — and the whole
/// left group is the one tap that opens the switcher. At the panel title's
/// size: this bar is a header, and the redesign took the chrome off rather
/// than making the type bigger.
///
/// The line under the name says something rather than teaching the gesture:
/// how many people are online on a server, or which account Home belongs to,
/// the one place people check who they are messaging as.
///
/// A dot on the avatar is the only sign that something is happening
/// somewhere else, so it counts every tier that isn't on screen.
class SwitcherHeader extends StatelessWidget {
  const SwitcherHeader({super.key});

  static const double height = 56;
  static const double avatarSize = 36;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final surface = context.select<AppCubit, HomeSurface>(
      (c) => c.state.surface,
    );
    final server = context.select<ServerCubit, _ServerIdentity?>((c) {
      final s = c.state.selectedServer;
      return s == null ? null : _ServerIdentity(s.id, s.name, s.iconUrl);
    });
    final onHome = surface == HomeSurface.centralDms;
    final elsewhere = _unreadElsewhere(context, onHome ? null : server?.id);

    final title = onHome ? 'Home' : (server?.name ?? 'No server');

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.borderPrimary)),
      ),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                borderRadius: BorderRadius.circular(K.radiusRow),
                onTap: ShellScope.of(context).toggleSidebar,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          onHome || server == null
                              ? SwitcherHomeMark(isHome: onHome)
                              : SquircleAvatar(
                                  name: server.name,
                                  seed: server.id,
                                  imageUrl: server.iconUrl,
                                  size: avatarSize,
                                ),
                          if (elsewhere)
                            const Positioned(
                              top: -2,
                              right: -2,
                              child: UnreadDot(size: 9),
                            ),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 1,
                          children: [
                            // The chevron rides in the same row as the name,
                            // so it tracks the ellipsis instead of sitting at
                            // the far edge like a stepper.
                            Row(
                              spacing: 4,
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.panelTitle.copyWith(
                                      color: theme.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.expand_more_rounded,
                                  size: 19,
                                  color: theme.textTertiary,
                                ),
                              ],
                            ),
                            if (onHome)
                              const SwitcherHomeLine()
                            else if (server != null)
                              SwitcherServerLine(serverId: server.id)
                            else
                              Text(
                                'Join or create one',
                                style: AppText.label.copyWith(
                                  color: theme.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: K.touchTargetMin,
            child: IconButton(
              tooltip: 'Jump to a channel',
              onPressed: () => openQuickSwitcher(context),
              icon: Icon(
                Icons.search_rounded,
                size: 21,
                color: theme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Whether a tier other than the one on screen has something unread —
  /// another server, or Home while you are on a server.
  bool _unreadElsewhere(BuildContext context, String? currentServerId) {
    final otherServers = context.select<ServerNotificationsCubit, int>(
      (c) => c.state.totalUnreadExcept(currentServerId),
    );
    final home = context.select<CentralDmCubit, int>((c) => c.state.homeBadge);
    final onHome = context.select<AppCubit, bool>(
      (c) => c.state.surface == HomeSurface.centralDms,
    );
    return otherServers > 0 || (!onHome && home > 0);
  }
}

/// The server's identity as far as the header draws it, so a message arriving
/// on the server — which replaces the server object — doesn't rebuild it.
class _ServerIdentity {
  final String id;
  final String name;
  final String? iconUrl;

  const _ServerIdentity(this.id, this.name, this.iconUrl);

  @override
  bool operator ==(Object other) =>
      other is _ServerIdentity &&
      other.id == id &&
      other.name == name &&
      other.iconUrl == iconUrl;

  @override
  int get hashCode => Object.hash(id, name, iconUrl);
}
