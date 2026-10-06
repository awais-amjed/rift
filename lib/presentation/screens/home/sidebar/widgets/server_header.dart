import 'package:flutter/material.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import 'sidebar_peek_scope.dart';

/// The selected server's identity at the top of the sidebar column.
///
/// It states the encryption guarantee under the name rather than hiding it in
/// settings: end-to-end encryption is the reason Rift exists, and a claim you
/// can see at all times is worth more than one you have to go looking for.
///
/// The name and that claim are a label, not a button. Only the icons act,
/// and each says which one it is — a whole row that silently opens settings
/// gives no clue what it will do before you commit to it.
///
/// No settings gear: with invite and hide beside the name a third icon was
/// one too many, and settings is a rare trip — the rail chip's menu has it,
/// with the open-report count.
class ServerHeader extends StatelessWidget {
  final Server server;

  /// Whether to offer the collapse chevron. False where this heads the
  /// *content* pane rather than the sidebar — there is no sidebar there to
  /// collapse, and a chevron that did something else would be a third meaning
  /// for the same mark.
  final bool showHideButton;

  /// For whoever may make invites. Null hides the button.
  final VoidCallback? onInvite;

  const ServerHeader({
    super.key,
    required this.server,
    this.onInvite,
    this.showHideButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // Material for the icon buttons' ink — the panel around this brings
    // none of its own.
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
        child: Row(
          spacing: 11,
          children: [
            SquircleAvatar(
              name: server.name,
              seed: server.id,
              imageUrl: server.iconUrl,
              size: 38,
            ),
            Expanded(child: _buildIdentity(themeState)),
            if (onInvite != null) _buildInviteButton(themeState),
            if (showHideButton) _buildHideButton(context, themeState),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentity(ThemeState themeState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          server.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.panelTitle.copyWith(color: themeState.textPrimary),
        ),
        const SizedBox(height: 1),
        Row(
          spacing: 5,
          children: [
            Icon(
              Icons.lock_outline,
              size: K.iconTiny,
              color: themeState.statusInk(CustomColors.success),
            ),
            Flexible(
              // One word, because the sidebar is a fixed width and the
              // header spends it on a name and the buttons beside it:
              // "End-to-end encrypted" came out as "End-to-end encryp…" on a
              // 1500px window, which is a claim cut off halfway through
              // making it. The padlock beside it carries the rest, and
              // "Encrypted" is the word the chat header's own chip uses.
              child: Text(
                'Encrypted',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: themeState.textTertiary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Here rather than only on the rail's menu: asking somebody in is the
  /// first thing a new server needs, and a right-click is not where anyone
  /// looks for it.
  Widget _buildInviteButton(ThemeState themeState) {
    return IconButton(
      tooltip: 'Invite people',
      visualDensity: VisualDensity.compact,
      onPressed: onInvite,
      icon: Icon(
        Icons.person_add_outlined,
        size: K.iconButton,
        color: themeState.textTertiary,
      ),
    );
  }

  /// Hides the sidebar. Only ever points one way now — there is no pinned and
  /// unpinned any more, just shown and hidden, and `ShowSidebarButton` in the
  /// pane's header is what brings it back. A button that changed into a pin depending on a mode you couldn't
  /// see was describing a distinction that no longer exists.
  ///
  /// Through the shell rather than straight to [AppCubit]: overlaid, this is
  /// the drawer's own close button and has to shut the drawer, not quietly
  /// rewrite the docking preference for windows wide enough to have one.
  ///
  /// In a peek the sidebar is already hidden, so the same place offers the
  /// opposite: keep it open, which docks it and ends the peek.
  Widget _buildHideButton(BuildContext context, ThemeState themeState) {
    final peek = SidebarPeekScope.isPeek(context);
    return IconButton(
      tooltip: peek ? 'Keep sidebar open' : 'Hide sidebar',
      visualDensity: VisualDensity.compact,
      onPressed: ShellScope.of(context).toggleSidebar,
      icon: Icon(
        peek ? Icons.push_pin_outlined : Icons.chevron_left_rounded,
        size: K.iconButton,
        color: themeState.textTertiary,
      ),
    );
  }
}
