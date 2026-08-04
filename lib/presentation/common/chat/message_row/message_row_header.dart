import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';

/// The author + timestamp line that opens a group of messages. While a message
/// is still in flight the timestamp is replaced by a "Sending…" spinner.
class MessageRowHeader extends StatelessWidget {
  final ChatMessage message;
  final ThemeState themeState;

  const MessageRowHeader({
    super.key,
    required this.message,
    required this.themeState,
  });

  static String _timeLabel(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              message.authorName,
              overflow: TextOverflow.ellipsis,
              style: AppText.row.copyWith(
                fontWeight: FontWeight.w700,
                // Your own name in the accent — the cheapest way to find
                // yourself in a wall of messages.
                color: message.isMine
                    ? themeState.accentBright
                    : themeState.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (message.isPending)
            _sendingLabel()
          else
            Text(
              _timeLabel(message.sentAt),
              // Mono so timestamps form a column down the message list
              // instead of jittering with the digits.
              style: AppText.meta.copyWith(color: themeState.textQuaternary),
            ),
        ],
      ),
    );
  }

  Widget _sendingLabel() {
    return Row(
      children: [
        SizedBox(
          width: 9,
          height: 9,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            color: themeState.textQuaternary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          'Sending…',
          style: AppText.meta.copyWith(color: themeState.textQuaternary),
        ),
      ],
    );
  }
}
