import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/enums/message_origin.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';

/// Says a message was not encrypted, and that no person sent it.
///
/// This is the one visual affordance the whole webhook design leans on
/// (BOTS.md §3). Every other message in the channel was sealed before it left
/// the sender's device and the server holds only ciphertext; this one the
/// server read, stored and could hand to anybody. That difference has to be
/// legible at a glance, from a skim, without hovering — so it is a filled pill
/// with a word in it rather than a subtle tint or an icon alone.
///
/// It cannot be turned off, and there is deliberately no setting for it.
///
/// The tooltip is the explanation, and it is short on purpose: the pill is
/// already the signal, and a paragraph is something people learn to dismiss
/// without reading. It surfaces fast — a long wait on a small target reads as
/// nothing being there at all.
class MessageOriginBadge extends StatelessWidget {
  final ChatMessage message;
  final ThemeState themeState;

  const MessageOriginBadge({
    super.key,
    required this.message,
    required this.themeState,
  });

  /// Whether [message] needs one at all. A member's sealed message — every
  /// message before migration 013 — does not.
  static bool isNeededFor(ChatMessage message) =>
      !message.isEncrypted || !message.origin.isMember;

  /// Amber rather than red. An integration posting build results is working
  /// exactly as intended; the badge is a label, not an alarm, and colouring it
  /// like an error would teach people to ignore it.
  Color get _color => CustomColors.warning;

  String get _label => switch (message.origin) {
    MessageOrigin.webhook => 'WEBHOOK',
    MessageOrigin.member => 'NOT ENCRYPTED',
  };

  String get _tooltip => switch (message.origin) {
    MessageOrigin.webhook =>
      'Posted by an integration, not a member.\n'
          'Unencrypted — the server can read this message.',
    MessageOrigin.member => 'Unencrypted — the server can read this message.',
  };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      // Look and delay both come from `tooltipTheme` in AppTheme, so this
      // matches every other tooltip in the app rather than setting its own.
      message: _tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            Icon(Icons.lock_open_rounded, size: 10, color: _color),
            Text(
              _label,
              style: AppText.meta.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: _color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
