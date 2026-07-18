import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../chat_message.dart';

/// One message in the chat list — flat Discord-style row, not a bubble.
///
/// [showHeader] rows carry the avatar + author name + timestamp; continuation
/// rows (same author, small gap) show only the indented text.
class ChatMessageRow extends StatelessWidget {
  static const double _avatarSize = 34;
  static const double _gutterWidth = 48;

  final ChatMessage message;
  final bool showHeader;
  final ThemeState themeState;

  const ChatMessageRow({
    super.key,
    required this.message,
    required this.showHeader,
    required this.themeState,
  });

  String _timeLabel(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final hm = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return hm;
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: message.isPending ? 0.5 : 1.0,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: showHeader ? 10 : 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _gutterWidth,
              child: showHeader ? _buildAvatar() : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              message.authorName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: message.isMine
                                    ? themeState.primary
                                    : themeState.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _timeLabel(message.sentAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: themeState.textQuaternary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: themeState.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        color: themeState.bgActive,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        message.authorName.isNotEmpty
            ? message.authorName[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: themeState.textSecondary,
        ),
      ),
    );
  }
}
