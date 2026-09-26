import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../message_markup_text.dart';
import '../message_row/guarded_message_text.dart';
import 'pinned_attachments_line.dart';
import 'pinned_poll_summary.dart';

/// What a pinned message says: its words with their markup, then what it
/// carries — a poll, files — each as a line of its own.
///
/// The words go through the same sensitive-text guard the conversation uses.
/// The list is another way of reading the same message, and a filter that
/// only held in one of the two places would not be a filter.
class PinnedMessagePreview extends StatelessWidget {
  final ChatMessage message;

  /// `@username` → display name, for the mentions in the text.
  final Map<String, String> displayNames;

  /// Enough to recognise a message by, and to read most of them whole.
  static const int maxLines = 6;

  const PinnedMessagePreview({
    super.key,
    required this.message,
    this.displayNames = const {},
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    if (message.isLocked) {
      return _Note(
        icon: Icons.lock_outline_rounded,
        text: 'Locked — this device has no key for it yet',
      );
    }

    final forwarded = message.forwarded;
    final text = message.text.trim().isNotEmpty
        ? message.text
        : (forwarded?.text ?? '');
    final attachments = message.attachments.isNotEmpty
        ? message.attachments
        : (forwarded?.attachments ?? const []);
    final poll = message.poll;

    final children = <Widget>[
      if (forwarded != null && message.text.trim().isEmpty)
        const _Note(icon: Icons.shortcut_rounded, text: 'Forwarded'),
      if (text.trim().isNotEmpty)
        GuardedMessageText(
          messageId: message.id,
          text: text,
          child: Text.rich(
            messageMarkupSpan(
              text,
              base: AppText.body.copyWith(color: themeState.textSecondary),
              theme: themeState,
              displayNames: displayNames,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (poll != null) PinnedPollSummary(poll: poll),
      if (attachments.isNotEmpty)
        PinnedAttachmentsLine(attachments: attachments),
    ];
    if (children.isEmpty) {
      return const _Note(
        icon: Icons.chat_bubble_outline_rounded,
        text: 'Message',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: children,
    );
  }
}

/// A quiet line saying what something is when there are no words to show.
class _Note extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Row(
      spacing: 6,
      children: [
        Icon(icon, size: K.iconInline, color: themeState.textTertiary),
        Flexible(
          child: Text(
            text,
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        ),
      ],
    );
  }
}
