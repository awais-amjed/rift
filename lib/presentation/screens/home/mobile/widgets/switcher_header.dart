import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/unread_badge.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../sidebar/widgets/sidebar_header.dart';

/// The top of a phone's list: where you are, and the way to anywhere else.
///
/// The whole identity card is the switcher — there is no rail and no tab bar,
/// so this is the one door out of the server you are standing in. It says so
/// in words ("tap to switch") rather than trusting a chevron to, because it is
/// the only way to reach every other server and Home.
///
/// A dot on the avatar is the only sign that something is happening
/// somewhere else, so it counts every tier that isn't on screen.
class SwitcherHeader extends StatelessWidget {
  const SwitcherHeader({super.key});

  static const double _avatarSize = 36;

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

    final (title, subtitle) = onHome
        ? ('Home', 'Central · tap to switch')
        : server == null
        ? ('No server', 'Tap to join or create one')
        : (server.name, 'Encrypted · tap to switch');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.borderPrimary)),
      ),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: Material(
              color: theme.bgHover,
              borderRadius: BorderRadius.circular(K.radiusCard),
              child: InkWell(
                borderRadius: BorderRadius.circular(K.radiusCard),
                onTap: ShellScope.of(context).toggleSidebar,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(K.radiusCard),
                    border: Border.all(color: theme.borderElevated),
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          onHome || server == null
                              ? _HomeMark(isHome: onHome)
                              : SquircleAvatar(
                                  name: server.name,
                                  seed: server.id,
                                  imageUrl: server.iconUrl,
                                  size: _avatarSize,
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.panelTitle.copyWith(
                                color: theme.textPrimary,
                              ),
                            ),
                            Row(
                              spacing: 4,
                              children: [
                                if (!onHome && server != null)
                                  const Icon(
                                    Icons.lock_outline,
                                    size: 11,
                                    color: CustomColors.success,
                                  ),
                                Flexible(
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.label.copyWith(
                                      color: theme.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 18,
                        color: theme.textTertiary,
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
                size: 22,
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

/// Home's mark, in the slot a server's avatar takes — or, with no server at
/// all, a plus that says where joining one starts.
class _HomeMark extends StatelessWidget {
  final bool isHome;

  const _HomeMark({required this.isHome});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      width: SwitcherHeader._avatarSize,
      height: SwitcherHeader._avatarSize,
      decoration: BoxDecoration(
        color: isHome ? theme.primary : theme.bgActive,
        borderRadius: BorderRadius.circular(
          SwitcherHeader._avatarSize * K.avatarRadiusRatio,
        ),
      ),
      child: Icon(
        isHome ? Icons.forum_rounded : Icons.add_rounded,
        size: 19,
        color: isHome ? theme.onPrimary : theme.textSecondary,
      ),
    );
  }
}
