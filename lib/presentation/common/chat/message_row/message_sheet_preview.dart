import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// Which message the sheet is about — the author and the start of what they
/// said — since the row itself is under the scrim.
class MessageSheetPreview extends StatelessWidget {
  final ChatMessage message;

  const MessageSheetPreview({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = message.text.isEmpty ? 'Attachment' : message.text;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            message.authorName,
            style: AppText.strong.copyWith(color: theme.textPrimary),
          ),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.secondary.copyWith(color: theme.textSecondary),
          ),
        ],
      ),
    );
  }
}
