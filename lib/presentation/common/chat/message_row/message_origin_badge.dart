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
      !message.isEncrypted || !message.origin.isMember || message.isEphemeral;

  /// Amber rather than red. An integration posting build results is working
  /// exactly as intended; the badge is a label, not an alarm, and colouring it
  /// like an error would teach people to ignore it.
  /// A private reply is not a caution, so it is not amber. It is a fact about
  /// who is looking, and it reads as one.
  Color get _color =>
      message.isEphemeral ? themeState.textTertiary : CustomColors.warning;

  /// "Only you" comes first when both are true. A private reply is already
  /// unencrypted by construction, and the surprising half — that nobody else
  /// is seeing this — is the one worth the pill.
  String get _label => message.isEphemeral
      ? 'ONLY YOU'
      : switch (message.origin) {
          MessageOrigin.webhook => 'WEBHOOK',
          // Not the server's name — that is already the author line beside
          // it, and a badge that repeats what it sits next to is spending the
          // one glance this design gets on nothing.
          MessageOrigin.system => 'SYSTEM',
          MessageOrigin.member => 'NOT ENCRYPTED',
        };

  String get _tooltip => switch (message.origin) {
    MessageOrigin.webhook =>
      // The break is at the sentence, not left to the wrap: two facts, one a
      // line. The width cap in `tooltipTheme` is the backstop, not the shape.
      'Posted by an integration, not a member.\n'
          'Unencrypted — the server can read it.',
    MessageOrigin.system =>
      'Written by this server, not by anybody in it.\n'
          'Unencrypted — the server can read it.',
    MessageOrigin.member => 'Unencrypted — the server can read it.',
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
            Text(_label, style: AppText.roleChip.copyWith(color: _color)),
          ],
        ),
      ),
    );
  }
}
