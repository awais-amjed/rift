import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/context_menu/context_menu_sheet.dart';
import '../../../../common/status_chip.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../channels/channel_list/widgets/channel_context_menu.dart';
import '../../profile/person/verification/show_channel_encryption.dart';
import 'channel_listeners_chip.dart';
import 'chat_header_button.dart';
import 'chat_phone_title.dart';
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

  /// Open the channel's pinned messages. Null hides the button — before the
  /// channel has opened there is nothing to list.
  final void Function(BuildContext anchor)? onShowPins;

  const ChatHeader({super.key, this.onShowPins});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // Selected, not watched: the chat state changes with every message and
    // every keystroke someone else types, and all this needs is which channel.
    final channelId = context.select((ChannelChatCubit c) => c.state.channelId);
    final channels =
        context.select((ServerCubit c) => c.state.selectedServer?.channels) ??
        const [];
    final channel = channels.where((c) => c.id == channelId).firstOrNull;
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
                    size: K.iconButton,
                    color: themeState.accentBright,
                  ),
                  Flexible(
                    child: compact
                        ? ChatPhoneTitle(
                            channel: channel,
                            name: name ?? 'channel',
                          )
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
                    StatusChip(
                      icon: Icons.lock_outline,
                      label: 'Encrypted',
                      color: CustomColors.success,
                      tooltip: StatusChip.encryptedVerifyTooltip,
                      // A channel has more than one other person in it, so
                      // the chip opens the list rather than one code.
                      onTap: () => showChannelEncryption(
                        context,
                        channelName: name ?? 'channel',
                      ),
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
          if (onShowPins case final show?)
            // A Builder, so the list can hang from this button's own box.
            Builder(
              builder: (button) => ChatHeaderButton(
                icon: Icons.push_pin_outlined,
                tooltip: 'Pinned messages',
                onTap: () => show(button),
              ),
            ),
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
