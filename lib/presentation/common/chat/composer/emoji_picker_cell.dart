import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../emoji_text.dart';

/// One emoji in the picker grid.
class EmojiPickerCell extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const EmojiPickerCell({super.key, required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.radiusRow);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Center(child: Text(emoji, style: EmojiSize.grid)),
      ),
    );
  }
}
