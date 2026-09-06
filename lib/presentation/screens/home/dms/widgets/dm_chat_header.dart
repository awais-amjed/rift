import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/status_chip.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/chat_header_button.dart';
import '../../chat/widgets/header_pane_buttons.dart';

/// Header of an open DM conversation.
///
/// Carries two chips rather than one: which tier the conversation is on, and
/// that it's encrypted. The tier matters here in a way it doesn't in a
/// channel — a central DM is quota-limited and a server DM isn't, and that's
/// worth saying before someone starts typing.
class DmChatHeader extends StatelessWidget {
  final String title;

  /// The peer's id, so their avatar matches the conversation list.
  final String? peerId;

  /// Which tier this conversation is on — "Central", or the server's name.
  final String tierLabel;

  final IconData tierIcon;
  final VoidCallback onClose;

  const DmChatHeader({
    super.key,
    required this.title,
    required this.tierLabel,
    required this.tierIcon,
    required this.onClose,
    this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    final compact = context.layoutMode.isCompact;

    return Container(
      height: ChatHeader.height,
      padding: EdgeInsets.fromLTRB(compact ? 6 : 18, 0, compact ? 6 : 10, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      // Measured, not inferred. The window's `LayoutMode` says how many panes
      // are docked, not how much room is left for the last one: a medium
      // window docks the sidebar *and* the DM list, leaving this header
      // narrower than the same header gets on a phone. Sizing the chips by
      // mode is what made it overflow there — a chip has no `Flexible` to
      // give, so the excess became a stripe instead of an ellipsis.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return Row(
            spacing: 10,
            children: [
              const HeaderSidebarButton(),
              // The identity is one flexible group, so the close button sits
              // hard against the panel edge. A `Flexible` title beside a
              // `Spacer` splits the free space with it instead: the title
              // takes only what it needs and the rest of its share is left
              // stranded *after* the last child, parking the button in the
              // middle of the bar.
              Expanded(
                child: Row(
                  spacing: 10,
                  children: [
                    SquircleAvatar(name: title, seed: peerId, size: 30),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.panelTitle.copyWith(
                          color: themeState.textPrimary,
                        ),
                      ),
                    ),
                    // Dropped in this order because the tier chip is the one
                    // that earns its width: it says whether this conversation
                    // is quota-limited, which changes what you do next. The
                    // encryption chip is true of every conversation, so it is
                    // the first thing to go — and on a phone it goes at any
                    // width, where the peer's name matters more than a fact
                    // the padlock in the composer already carries.
                    if (width >= K.dmHeaderTierChipMin)
                      StatusChip(
                        icon: tierIcon,
                        label: tierLabel,
                        color: themeState.accentBright,
                      ),
                    if (!compact && width >= K.dmHeaderEncryptedChipMin)
                      const StatusChip(
                        icon: Icons.lock_outline,
                        label: 'Encrypted',
                        color: CustomColors.success,
                        tooltip: StatusChip.encryptedTooltip,
                      ),
                  ],
                ),
              ),
              ChatHeaderButton(
                icon: Icons.close_rounded,
                tooltip: 'Close conversation',
                onTap: onClose,
              ),
            ],
          );
        },
      ),
    );
  }
}
