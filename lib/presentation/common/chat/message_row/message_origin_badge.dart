import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/enums/message_origin.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../badge_explainer.dart';

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
/// **Tappable**, because the pill on its own only works for somebody who
/// already knows what it means. A tooltip does not close that gap either: it
/// needs a mouse, so a phone never sees one, and it needs you to already
/// suspect there is something to find.
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

  String get _title => switch (message.origin) {
    MessageOrigin.webhook => 'Posted by an integration',
    MessageOrigin.member => 'Not encrypted',
  };

  /// What it means *for this message*. It never says the channel is unsafe,
  /// because it isn't — everything else in it is still sealed, and a warning
  /// that overstates itself is one people learn to skip past.
  String get _body => switch (message.origin) {
    MessageOrigin.webhook =>
      'An outside service posted this through a webhook, so it is not '
          'encrypted and the server can read it. Nobody in this server sent '
          'it. Every other message here is still end-to-end encrypted.',
    MessageOrigin.member =>
      'This message is not encrypted, so the server can read it. Every other '
          'message here is still end-to-end encrypted.',
  };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'What does this mean?',
      waitDuration: const Duration(milliseconds: 400),
      child: Builder(
        // Its own context, so the popover anchors to the pill rather than to
        // whatever ancestor happened to build this row.
        builder: (badgeContext) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => showBadgeExplainer(
              badgeContext,
              icon: Icons.lock_open_rounded,
              iconColor: _color,
              title: _title,
              body: _body,
            ),
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
          ),
        ),
      ),
    );
  }
}
