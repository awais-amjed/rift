import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/status_chip.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/chat_header_button.dart';
import '../../chat/widgets/header_back_button.dart';
import '../../pane_toggles/show_sidebar_button.dart';
import 'dm_surface.dart';

/// Header of an open DM conversation.
///
/// Carries two chips rather than one: which tier the conversation is on, and
/// that it's encrypted — the second of which opens the safety code, because
/// the claim and the way to check it belong together. The tier matters here in a way it doesn't in a
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

  /// Open the other person's profile. Null while nothing is open, and on a
  /// tier with no profile to show.
  final VoidCallback? onOpenProfile;

  /// Open the safety code for this conversation — the encryption chip's
  /// press. Null while there is nobody to compare keys with.
  final VoidCallback? onVerify;

  /// Their safety key changed and nobody has looked yet — see `SeenKey`.
  /// Turns the encryption chip amber, and keeps it on screen where it would
  /// otherwise be the first thing dropped.
  final bool keyChanged;

  /// Open the conversation's pinned messages; null hides the button.
  final void Function(BuildContext anchor)? onShowPins;

  /// Ring the other person; null hides the button — no call to make on this
  /// tier, with this person, or while already in one with them.
  final VoidCallback? onCall;

  const DmChatHeader({
    super.key,
    required this.title,
    required this.tierLabel,
    required this.tierIcon,
    required this.onClose,
    this.peerId,
    this.onOpenProfile,
    this.onVerify,
    this.keyChanged = false,
    this.onShowPins,
    this.onCall,
  });

  /// The peer's picture and name, opening their profile where there is one.
  Widget _identity(BuildContext context, ThemeState themeState) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        SquircleAvatar(name: title, seed: peerId, size: 30),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.panelTitle.copyWith(color: themeState.textPrimary),
          ),
        ),
      ],
    );
    final open = onOpenProfile;
    if (open == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: open, child: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;

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
              if (HeaderBackButton.shows(context)) const HeaderBackButton(),
              if (ShowSidebarButton.shows(context) && !DmListBeside.of(context))
                const ShowSidebarButton(),
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
                    // Avatar and name together, because they are one thing:
                    // the person this conversation is with. The chips beside
                    // them are about the conversation and stay inert.
                    Flexible(child: _identity(context, themeState)),
                    // Dropped in this order because the tier chip is the one
                    // that earns its width: it says whether this conversation
                    // is quota-limited, which changes what you do next. The
                    // encryption chip is true of every conversation, so it is
                    // the first thing to go — and on a phone it goes at any
                    // width, where the peer's name matters more than a fact
                    // the padlock in the composer already carries.
                    //
                    // Unless the key changed. Then the order flips: that is
                    // the one fact here that asks something of the reader,
                    // so it stays at any width and on a phone too, and the
                    // tier chip is what makes room.
                    if (width >=
                        (keyChanged
                            ? K.dmHeaderEncryptedChipMin
                            : K.dmHeaderTierChipMin))
                      StatusChip(
                        icon: tierIcon,
                        label: tierLabel,
                        color: themeState.accentBright,
                      ),
                    if (keyChanged)
                      StatusChip(
                        icon: Icons.key_rounded,
                        label: 'Key changed',
                        color: CustomColors.warning,
                        tooltip: StatusChip.keyChangedTooltip,
                        onTap: onVerify,
                      )
                    else if (!compact && width >= K.dmHeaderEncryptedChipMin)
                      StatusChip(
                        icon: Icons.lock_outline,
                        label: 'Encrypted',
                        color: CustomColors.success,
                        tooltip: onVerify == null
                            ? StatusChip.encryptedTooltip
                            : StatusChip.encryptedVerifyTooltip,
                        onTap: onVerify,
                      ),
                  ],
                ),
              ),
              if (onCall case final call?)
                ChatHeaderButton(
                  icon: Icons.call_outlined,
                  tooltip: 'Start a call',
                  onTap: call,
                ),
              if (onShowPins case final show?)
                // A Builder, so the list can hang from this button's own box.
                Builder(
                  builder: (button) => ChatHeaderButton(
                    icon: Icons.push_pin_outlined,
                    tooltip: 'Pinned messages',
                    onTap: () => show(button),
                  ),
                ),
              // On a phone back is the way out, so a close beside it would
              // be a second button for the same thing — the rule the
              // channel header already follows. Nothing takes the slot: a
              // conversation's one other destination is the person, and
              // tapping their name is how you get there.
              if (!compact)
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
