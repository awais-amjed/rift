import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../emoji_text.dart';
import '../reactions/reaction_picker.dart';

/// The row of one-tap reactions across the top of a phone's message sheet.
class MessageSheetQuickReactions extends StatelessWidget {
  final ValueChanged<String> onPick;

  const MessageSheetQuickReactions({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.radiusRow);
    return GridView.count(
      crossAxisCount: 8,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final emoji in quickReactionEmojis)
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: radius,
              onTap: () => onPick(emoji),
              child: Center(child: Text(emoji, style: EmojiSize.sheet)),
            ),
          ),
      ],
    );
  }
}
