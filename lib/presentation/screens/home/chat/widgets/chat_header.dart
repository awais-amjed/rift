import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu/context_menu_sheet.dart';
import '../../../../common/status_chip.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../channels/channel_list/widgets/channel_context_menu.dart';
import 'channel_listeners_chip.dart';
import 'chat_header_button.dart';
import 'header_back_button.dart';
import 'header_members_button.dart';

/// The chat panel's top bar: which channel you're in, that it's encrypted, and
/// the controls that change what the panel shows.
///
/// The encryption chip is stated in green rather than left as a lock icon —
/// it's the product's central claim, and a chip you can read beats a glyph
/// you have to hover.
class ChatHeader extends StatelessWidget {
  static const double height = K.paneHeaderHeight;

  const ChatHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final chatState = context.watch<ChannelChatCubit>().state;
    final channels =
        context.watch<ServerCubit>().state.selectedServer?.channels ?? [];
    final channel = channels
        .where((c) => c.id == chatState.channelId)
        .firstOrNull;
    final name = channel?.name;

    // The drawer button takes the place of the leading padding, so the title
    // starts where it always did rather than being pushed along by it.
    final compact = context.layoutMode.isCompact;

    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(compact ? 6 : 18, 0, compact ? 6 : 10, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        spacing: 10,
        children: [
          const HeaderBackButton(),
          // The identity is one flexible group, so the controls sit hard
          // against the panel edge. A `Flexible` title beside a `Spacer`
          // splits the free space with it instead: the title takes only what
          // it needs and the rest of its share is left stranded *after* the
          // last child, parking the buttons in the middle of the bar.
          // The channel's own actions — settings, delete — hang off its name
          // here as well as off its row in the sidebar. On a desktop that row
          // is always on screen and a right-click reaches it; on a phone the
          // sidebar is a drawer, so the channel you are *in* is the one place
          // its settings have to be reachable from. Long-press and right-click
          // both open it, and a member who cannot manage channels gets no
          // menu rather than a menu of refusals.
          Expanded(
            child: _WithChannelMenu(
              channel: channel,
              child: Row(
                spacing: 10,
                children: [
                  Icon(
                    Icons.tag_rounded,
                    size: 18,
                    color: themeState.accentBright,
                  ),
                  Flexible(
                    child: compact
                        ? _PhoneTitle(channel: channel, name: name ?? 'channel')
                        : Text(
                            name ?? 'channel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.panelTitle.copyWith(
                              color: themeState.textPrimary,
                            ),
                          ),
                  ),
                  // Dropped on a phone. It is the product's central claim, but
                  // it is a claim about every channel equally, and spending 90px
                  // restating it leaves the one thing that differs between them
                  // — the channel's name — squeezed to nothing.
                  if (!compact)
                    const StatusChip(
                      icon: Icons.lock_outline,
                      label: 'Encrypted',
                      color: CustomColors.success,
                      tooltip: StatusChip.encryptedTooltip,
                    ),
                  // Both of these are shown at every width, including the
                  // one where "Encrypted" is dropped for room. That chip
                  // restates something true of every channel; these two are
                  // true of *this* one, and nobody would think to look for
                  // them.
                  // A phone says it in the line under the name instead.
                  if (!compact && (channel?.isPrivate ?? false))
                    const StatusChip(
                      icon: Icons.group_rounded,
                      label: 'Private',
                      color: CustomColors.success,
                      tooltip: StatusChip.privateTooltip,
                    ),
                  ChannelListenersChip(
                    listeners: context
                        .watch<ChannelChatCubit>()
                        .state
                        .botListeners,
                  ),
                ],
              ),
            ),
          ),
          // No members toggle here at the sizes where the list has an edge tab
          // — a third control for the same flag only made it ambiguous which
          // one you were meant to reach for. On a phone there is no edge tab,
          // so this is the only one.
          const HeaderMembersButton(),
          // On a phone back is the way out, so a close beside it would be a
          // second button for the same thing. The channel's menu takes the
          // slot instead: there is no sidebar row there to long-press.
          if (compact && channel != null)
            ChatHeaderButton(
              icon: Icons.more_vert_rounded,
              tooltip: 'Channel options',
              onTap: () => showContextMenuSheet(
                context,
                ChannelContextMenu(channel: channel),
              ),
            )
          else if (!compact)
            ChatHeaderButton(
              icon: Icons.close_rounded,
              tooltip: 'Close chat',
              onTap: () => context.read<ChannelChatCubit>().closeChannel(),
            ),
        ],
      ),
    );
  }
}

/// Hangs the channel context menu off the header's identity group.
///
/// A separate widget because [ChannelContextMenu.wrap] reads the server's
/// permissions and returns its child untouched when they do not allow
/// anything — so this is either a menu region or nothing at all, decided per
/// build, and a null channel (the header renders before one is resolved) is
/// nothing too.
class _WithChannelMenu extends StatelessWidget {
  final Channel? channel;
  final Widget child;

  const _WithChannelMenu({required this.channel, required this.child});

  @override
  Widget build(BuildContext context) {
    final channel = this.channel;
    if (channel == null) return child;
    return ChannelContextMenu.wrap(
      context: context,
      channel: channel,
      child: child,
    );
  }
}

/// The channel's name with the line under it that a phone's header carries:
/// the server it belongs to — so a channel opened from a notification still
/// says where you are — and how many people are in it, or that it's private.
class _PhoneTitle extends StatelessWidget {
  final Channel? channel;
  final String name;

  const _PhoneTitle({required this.channel, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeCubit>().state;
    final server = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServer?.name,
    );
    final members = context.select<ServerMembersCubit, int?>(
      (c) => c.state.loaded ? c.state.peopleCount : null,
    );
    final private = channel?.isPrivate ?? false;
    final detail = [
      ?server,
      if (private)
        'private'
      else if (members != null)
        '$members ${members == 1 ? 'member' : 'members'}',
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 5,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.panelTitle.copyWith(color: theme.textPrimary),
              ),
            ),
            if (private)
              Icon(Icons.lock_outline, size: 13, color: theme.textTertiary),
          ],
        ),
        if (detail.isNotEmpty)
          Row(
            spacing: 4,
            children: [
              if (!private)
                const Icon(
                  Icons.lock_outline,
                  size: 11,
                  color: CustomColors.success,
                ),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: theme.textTertiary),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
