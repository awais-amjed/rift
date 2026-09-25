import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../message_row/message_row_avatar.dart';

/// One pinned message in the pinned list: who said it, when, and enough of
/// what they said to recognise it. Pressing it goes to the message.
///
/// A summary rather than the full row. The list is for finding a message,
/// and the full row — attachments loading, reactions, a poll to vote in — is
/// one press away in the conversation itself.
class PinnedMessageTile extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onJump;

  /// Take the pin down. Null where the reader may not.
  final VoidCallback? onUnpin;

  const PinnedMessageTile({
    super.key,
    required this.message,
    this.onJump,
    this.onUnpin,
  });

  /// What the message is, in a line or a few: its words, or what it carries
  /// when it has none.
  static ({IconData? icon, String text}) summaryOf(ChatMessage message) {
    if (message.isLocked) {
      return (icon: Icons.lock_outline_rounded, text: 'Locked message');
    }
    if (message.poll case final poll?) {
      return (icon: Icons.poll_outlined, text: poll.question);
    }
    if (message.text.trim().isNotEmpty) return (icon: null, text: message.text);
    if (message.forwarded case final forwarded?
        when forwarded.text.trim().isNotEmpty) {
      return (icon: Icons.shortcut_rounded, text: forwarded.text);
    }
    final files = message.attachments.length;
    if (files > 0) {
      return (
        icon: Icons.attach_file_rounded,
        text: files == 1 ? '1 attachment' : '$files attachments',
      );
    }
    return (icon: null, text: 'Message');
  }

  static String _dateLabel(DateTime at) {
    final local = at.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final summary = summaryOf(message);
    return Material(
      color: themeState.bgTertiary,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        onTap: onJump,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              SizedBox(
                width: K.messageGutter,
                child: MessageRowAvatar(
                  authorName: message.authorName,
                  authorId: message.authorId,
                  avatarPath: message.authorAvatarPath,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Row(
                      spacing: 8,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            message.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.row.copyWith(
                              fontWeight: FontWeight.w700,
                              color: themeState.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          _dateLabel(message.sentAt),
                          style: AppText.meta.copyWith(
                            color: themeState.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        if (summary.icon case final icon?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              icon,
                              size: K.iconInline,
                              color: themeState.textTertiary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            summary.text,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(
                              color: themeState.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onUnpin != null)
                IconButton(
                  tooltip: 'Unpin',
                  iconSize: K.iconRow,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: K.iconButtonSmall,
                    height: K.iconButtonSmall,
                  ),
                  padding: EdgeInsets.zero,
                  color: themeState.textTertiary,
                  onPressed: onUnpin,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
