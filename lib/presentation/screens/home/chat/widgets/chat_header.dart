import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/status_chip.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import 'chat_header_button.dart';

/// The chat panel's top bar: which channel you're in, that it's encrypted, and
/// the controls that change what the panel shows.
///
/// The encryption chip is stated in green rather than left as a lock icon —
/// it's the product's central claim, and a chip you can read beats a glyph
/// you have to hover.
class ChatHeader extends StatelessWidget {
  static const double height = 52;

  const ChatHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final chatState = context.watch<ChannelChatCubit>().state;
    final channels =
        context.watch<ServerCubit>().state.selectedServer?.channels ?? [];
    final name = channels
        .where((c) => c.id == chatState.channelId)
        .map((c) => c.name)
        .firstOrNull;

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        spacing: 10,
        children: [
          // The identity is one flexible group, so the controls sit hard
          // against the panel edge. A `Flexible` title beside a `Spacer`
          // splits the free space with it instead: the title takes only what
          // it needs and the rest of its share is left stranded *after* the
          // last child, parking the buttons in the middle of the bar.
          Expanded(
            child: Row(
              spacing: 10,
              children: [
                Icon(
                  Icons.tag_rounded,
                  size: 18,
                  color: themeState.accentBright,
                ),
                Flexible(
                  child: Text(
                    name ?? 'channel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.panelTitle.copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                const StatusChip(
                  icon: Icons.lock_outline,
                  label: 'Encrypted',
                  color: CustomColors.success,
                ),
              ],
            ),
          ),
          // No members toggle here: the members sidebar carries its own, and
          // shows one in either state — a chevron in its header when open, a
          // people icon in the collapsed strip when closed. A third control for
          // the same flag only made it ambiguous which one you were meant to
          // reach for.
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
