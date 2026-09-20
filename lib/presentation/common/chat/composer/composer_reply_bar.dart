import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/message_excerpt.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The strip above the composer while a reply is being written.
///
/// It sits *outside* the bar rather than inside it, for the same reason the
/// staged-attachment chips do: the bar's height is pinned so the controls
/// stay on one centre line, and anything that grows it moves every one of
/// them. It is also the only place the reply can be called off, so the ✕ is
/// part of the answer to "what is this row for", not a decoration on it.
class ComposerReplyBar extends StatelessWidget {
  final ChatMessage replyingTo;
  final VoidCallback onCancel;

  /// Whether sending will also ring the author, and the control that flips
  /// it. Null on a surface where there is nobody to ring — a DM already
  /// wakes the one person in it.
  final bool? pinging;
  final ValueChanged<bool>? onTogglePing;

  const ComposerReplyBar({
    super.key,
    required this.replyingTo,
    required this.onCancel,
    this.pinging,
    this.onTogglePing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final ping = pinging;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: theme.bgTertiary,
          borderRadius: BorderRadius.circular(K.radiusRow),
          border: Border.all(color: theme.borderElevated),
        ),
        child: Row(
          children: [
            Icon(Icons.reply_rounded, size: 14, color: theme.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Replying to ',
                      style: AppText.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: theme.textTertiary,
                      ),
                    ),
                    TextSpan(
                      text: replyingTo.authorName,
                      style: AppText.chip.copyWith(color: theme.textSecondary),
                    ),
                    TextSpan(
                      text: '  ${MessageExcerpt.of(replyingTo)}',
                      style: AppText.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: theme.textTertiary,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (ping != null && onTogglePing != null)
              _PingToggle(on: ping, onChanged: onTogglePing!),
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 15),
              color: theme.textTertiary,
              tooltip: 'Cancel reply',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the reply rings its author, as a word you can press rather than a
/// switch: it is off-by-exception, and a switch on a strip this size reads as
/// the strip's main control instead of a footnote on it.
class _PingToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;

  const _PingToggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Tooltip(
      message: on ? 'They will be notified' : 'They will not be notified',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!on),
          borderRadius: BorderRadius.circular(K.radiusRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: Text(
              on ? '@ on' : '@ off',
              style: AppText.chip.copyWith(
                color: on ? theme.primary : theme.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
