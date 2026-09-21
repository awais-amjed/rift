import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import 'switcher_server_row.dart';

/// The servers in the switcher, in the order their owner put them in.
///
/// A sliver rather than a plain list because the rows it reorders sit between
/// two things that do not move — Home above, "Add a server" below — and the
/// order has to be theirs to state on a phone as much as on a desktop.
///
/// Press and hold to pick a row up. Not an immediate drag, the way the
/// desktop rail allows: this list scrolls under a finger, and a drag that
/// started on contact would take the scroll with it.
class SwitcherServerList extends StatelessWidget {
  final List<Server> servers;
  final String? selectedServerId;
  final bool onHome;
  final NotificationsState notifications;
  final void Function(Server server) onOpen;

  const SwitcherServerList({
    super.key,
    required this.servers,
    required this.selectedServerId,
    required this.onHome,
    required this.notifications,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: servers.length,
      proxyDecorator: _carried,
      onReorderItem: (from, to) =>
          context.read<ServerCubit>().reorderServers(from, to),
      itemBuilder: (context, index) {
        final server = servers[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(server.id),
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SwitcherServerRow(
              server: server,
              selected: server.id == selectedServerId && !onHome,
              unread: notifications.unreadForServer(server.id),
              muted: notifications.serverLevel(server.id).isMuted,
              onTap: () => onOpen(server),
            ),
          ),
        );
      },
    );
  }

  /// The row while it is being carried.
  ///
  /// Flutter's default lifts it onto an elevated [Material], which paints its
  /// own opaque rectangle over a row that already has a shape and a fill.
  /// Scale says "this one is in your hand" without drawing anything new.
  static Widget _carried(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Transform.scale(
        scale: 1 + 0.03 * Curves.easeOut.transform(animation.value),
        child: child,
      ),
    );
  }
}
