import 'package:flutter/material.dart';

import '../../../../../data/classes/server.dart';
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
/// The name and that claim are a label, not a button. Only the two icons act,
/// and each says which one it is — a whole row that silently opens settings
/// gives no clue what it will do before you commit to it.
class ServerHeader extends StatelessWidget {
  final Server server;

  /// Whether to offer the collapse chevron. False where this heads the
  /// *content* pane rather than the sidebar — there is no sidebar there to
  /// collapse, and a chevron that did something else would be a third meaning
  /// for the same mark.
  final bool showHideButton;

  /// Admin-only. Null hides the gear.
  final VoidCallback? onOpenSettings;

  const ServerHeader({
    super.key,
    required this.server,
    this.onOpenSettings,
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
            if (onOpenSettings != null) _buildSettingsButton(themeState),
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
            const Icon(
              Icons.lock_outline,
              size: 11,
              color: CustomColors.success,
            ),
            Flexible(
              child: Text(
                'End-to-end encrypted',
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

  Widget _buildSettingsButton(ThemeState themeState) {
    return IconButton(
      tooltip: 'Server settings',
      visualDensity: VisualDensity.compact,
      onPressed: onOpenSettings,
      icon: Icon(
        Icons.settings_outlined,
        size: 17,
        color: themeState.textTertiary,
      ),
    );
  }

  /// Hides the sidebar. Only ever points one way now — there is no pinned and
  /// unpinned any more, just shown and hidden, and [SidebarTab] is what brings
  /// it back. A button that changed into a pin depending on a mode you couldn't
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
        size: 18,
        color: themeState.textTertiary,
      ),
    );
  }
}
