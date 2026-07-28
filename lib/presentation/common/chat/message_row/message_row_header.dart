import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';

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
          if (message.isPending)
            _sendingLabel()
          else
            Text(
              _timeLabel(message.sentAt),
              style: TextStyle(fontSize: 11, color: themeState.textQuaternary),
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
          style: TextStyle(fontSize: 11, color: themeState.textQuaternary),
        ),
      ],
    );
  }
}
