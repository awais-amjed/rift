import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';
import '../../loading_dots.dart';
import 'message_origin_badge.dart';

/// The author + timestamp line that opens a group of messages.
///
/// The timestamp is where a message reports on itself. In flight it is a
/// "Sending…" spinner; failed, it is "Not sent" and the way to try again. Both
/// live here rather than beside the text because this is the line the eye
/// already checks to see when something was said.
class MessageRowHeader extends StatelessWidget {
  final ChatMessage message;

  /// Send this message again. Null where the surface has no outbox — the row
  /// still says it did not send, it just cannot offer to fix it.
  final VoidCallback? onRetry;

  /// Open the author's profile. Null when there is nobody behind the name —
  /// a webhook's row carries a name it was handed, not an account.
  final VoidCallback? onOpenProfile;

  const MessageRowHeader({
    super.key,
    required this.message,
    this.onRetry,
    this.onOpenProfile,
  });

  static String _timeLabel(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: _name(themeState)),
          // Between the name and the time, so a skim down the left edge of the
          // list cannot miss it — a badge at the end of the row would sit
          // wherever the name happened to end.
          if (MessageOriginBadge.isNeededFor(message)) ...[
            const SizedBox(width: 6),
            MessageOriginBadge(message: message),
          ],
          const SizedBox(width: 8),
          if (message.sendFailed)
            _failedLabel(context)
          else if (message.isPending)
            _sendingLabel(context)
          else
            Text(
              _timeLabel(message.sentAt),
              // Mono so timestamps form a column down the message list
              // instead of jittering with the digits.
              style: AppText.meta.copyWith(color: themeState.textTertiary),
            ),
        ],
      ),
    );
  }

  /// The author's name, which opens their profile where there is one.
  ///
  /// No underline and no colour of its own: this line is read far more often
  /// than it is clicked, and a wall of links down the left of the history
  /// would be louder than the messages. The cursor says it is pressable to
  /// anybody who goes looking.
  Widget _name(ThemeState themeState) {
    final label = Text(
      message.authorName,
      overflow: TextOverflow.ellipsis,
      style: AppText.row.copyWith(
        fontWeight: FontWeight.w700,
        // Your own name in the accent — the cheapest way to find yourself in
        // a wall of messages.
        color: message.isMine
            ? themeState.accentBright
            : themeState.textPrimary,
      ),
    );
    final open = onOpenProfile;
    if (open == null) return label;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: open, child: label),
    );
  }

  /// What a message that did not get out says about itself.
  ///
  /// It states the fact first and offers the remedy second, and it is the only
  /// thing on the row that has changed — the text is still there, in place,
  /// where it was typed. That is the whole point: the message was not lost, it
  /// is waiting.
  ///
  /// In the warning colour rather than the error one. Nothing has gone wrong
  /// with the message; it is a note about the network, and painting it as a
  /// failure of the sentence overstates it.
  Widget _failedLabel(BuildContext context) {
    final themeState = context.theme;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 11,
          color: themeState.statusInk(CustomColors.warning),
        ),
        const SizedBox(width: 4),
        Text(
          'Not sent',
          style: AppText.meta.copyWith(
            color: themeState.statusInk(CustomColors.warning),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 6),
          Text(
            'Try again',
            style: AppText.meta.copyWith(
              color: themeState.accentBright,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
    if (onRetry == null) return label;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onRetry, child: label),
    );
  }

  Widget _sendingLabel(BuildContext context) {
    final themeState = context.theme;
    return Row(
      children: [
        LoadingDots(color: themeState.textQuaternary, dotSize: 3),
        const SizedBox(width: 5),
        Text(
          'Sending…',
          style: AppText.meta.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
