import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/enums/home_surface.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../responsive/shell_scope.dart';
import 'rail_server_chip.dart';

/// The servers in the rail, in the order their owner put them in.
///
/// Reorderable, and that is the only reason this is a list rather than the
/// `Column` it used to be. The order is the user's — it rides in the vault
/// and syncs between their devices — so the rail has to be somewhere they
/// can state it.
///
/// The drag gesture differs by input, not by taste. A pointer drags
/// immediately, because a click that does not move is still a tap and the
/// gesture arena sorts that out. A finger has to press and hold, because an
/// immediate drag would eat the scroll and a rail full of servers scrolls.
class RailServerList extends StatelessWidget {
  /// Gap between chips, and below the last one.
  static const double gap = 8;

  const RailServerList({super.key});

  @override
  Widget build(BuildContext context) {
    // AppState churns on every mic/camera toggle, so the rail listens for the
    // one field it cares about rather than watching the whole cubit.
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.surface != b.surface,
      builder: (context, appState) {
        return BlocBuilder<ServerCubit, ServerState>(
          buildWhen: (a, b) =>
              a.servers != b.servers ||
              a.selectedServerId != b.selectedServerId,
          builder: (context, serverState) {
            return BlocBuilder<ServerNotificationsCubit, NotificationsState>(
              builder: (context, notifications) {
                return ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: _carried,
                  itemCount: serverState.servers.length,
                  onReorderItem: (from, to) =>
                      context.read<ServerCubit>().reorderServers(from, to),
                  itemBuilder: (context, index) {
                    final server = serverState.servers[index];
                    return _Draggable(
                      key: ValueKey(server.id),
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        // Centred, and loosely. A list hands every item the
                        // full cross-axis width as a *tight* constraint, so
                        // without this the chip's `Stack` is as wide as the
                        // rail, the avatar sits at the stack's default
                        // `topStart`, and the halo — `Positioned` to -4 on
                        // every side — stretches the whole width with the
                        // chip off-centre inside it. The `Column` this list
                        // replaced never showed it, because a column's
                        // cross-axis constraint is loose.
                        child: Center(
                          heightFactor: 1,
                          child: RailServerChip(
                            server: server,
                            // Opening Home doesn't leave the server, but it
                            // does mean the rail's selection is Home — two
                            // things can't both be current.
                            isSelected:
                                server.id == serverState.selectedServerId &&
                                appState.surface != HomeSurface.centralDms,
                            unreadCount: notifications.unreadForServer(
                              server.id,
                            ),
                            onTap: () => _open(context, server),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// Another server opens on its channels. The one already selected — the
  /// way back from Home — opens on whichever half was left, so a server DM
  /// is still there.
  static void _open(BuildContext context, Server server) {
    final app = context.read<AppCubit>();
    final servers = context.read<ServerCubit>();
    if (server.id == servers.state.selectedServerId) {
      app.backToServer();
    } else {
      app.setSurface(HomeSurface.server);
    }
    servers.selectServer(server);
  }

  /// The chip while it is being carried.
  ///
  /// Flutter's default wraps it in an elevated [Material], which paints a
  /// rectangle behind a chip whose whole shape is a squircle with a halo
  /// hanging off it. Scale says the same thing without drawing anything.
  static Widget _carried(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Transform.scale(
        scale: 1 + 0.08 * Curves.easeOut.transform(animation.value),
        child: child,
      ),
    );
  }
}

/// Whichever drag listener suits the pointer that is on the screen.
class _Draggable extends StatelessWidget {
  final int index;
  final Widget child;

  const _Draggable({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) {
      return ReorderableDelayedDragStartListener(index: index, child: child);
    }
    return ReorderableDragStartListener(index: index, child: child);
  }
}
