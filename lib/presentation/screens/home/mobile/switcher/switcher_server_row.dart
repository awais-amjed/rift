import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/unread_badge.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../servers/server_rail/widgets/server_chip_menu.dart';
import 'switcher_row.dart';

/// A server in the switcher.
///
/// Its second line is the rail's glance put into words: who is talking there
/// if anyone is, and otherwise the host you are joined to — the one thing about
/// a server that nobody can make up. Long-press opens the same menu a rail
/// chip does, so invite, settings and leave have a home on a phone too.
///
/// Which is why reordering is a [dragHandle] and not a long-press, the way it
/// is on a desktop: that gesture is already spoken for here, and a row that
/// answered a held finger with two different things would be a coin toss.
class SwitcherServerRow extends StatelessWidget {
  final Server server;
  final bool selected;
  final int unread;
  final bool muted;
  final VoidCallback onTap;

  /// The grip that picks this row up, if the list it is in reorders.
  final Widget? dragHandle;

  const SwitcherServerRow({
    super.key,
    required this.server,
    required this.selected,
    required this.unread,
    required this.muted,
    required this.onTap,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final live = _liveSummary(context);

    final Widget? trailing = selected
        ? Icon(
            Icons.check_circle_outline_rounded,
            size: 20,
            color: theme.accentBright,
          )
        : unread > 0
        ? UnreadBadge(count: unread, isMuted: muted)
        : muted
        ? Icon(
            Icons.notifications_off_outlined,
            size: 16,
            color: theme.textTertiary,
          )
        : null;

    return ContextMenuRegion(
      contextMenu: ServerChipMenu(server: server),
      child: SwitcherRow(
        selected: selected,
        leading: SquircleAvatar(
          name: server.name,
          seed: server.id,
          imageUrl: server.iconUrl,
          size: SwitcherRow.leadingSize,
        ),
        title: server.name,
        subtitle: Row(
          spacing: 5,
          children: [
            if (live != null)
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: CustomColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            Flexible(
              child: Text(
                live ?? Uri.tryParse(server.supabaseUrl)?.host ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SwitcherRow.subtitleStyle(theme),
              ),
            ),
          ],
        ),
        trailing: dragHandle == null
            ? trailing
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [?trailing, dragHandle!],
              ),
        onTap: onTap,
      ),
    );
  }

  /// "3 live in Standup", for the server whose voice channels this client is
  /// watching. Presence is only followed for the selected server, so any other
  /// row says nothing rather than something stale.
  String? _liveSummary(BuildContext context) {
    final isCurrent = context.select<ServerCubit, bool>(
      (c) => c.state.selectedServerId == server.id,
    );
    if (!isCurrent) return null;
    final presence = context.watch<ChannelPresenceCubit>().state;
    var busiest = (name: '', count: 0);
    var total = 0;
    for (final channel in server.channels) {
      final count = presence.usersIn(channel.id).length;
      total += count;
      if (count > busiest.count) busiest = (name: channel.name, count: count);
    }
    if (total == 0) return null;
    return '$total live in ${busiest.name}';
  }
}
