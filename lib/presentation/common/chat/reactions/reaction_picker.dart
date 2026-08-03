import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../emoji_text.dart';

/// Curated quick-reaction emojis. A compact popup — not the full picker — since
/// reactions are usually one of a common handful.
const List<String> quickReactionEmojis = [
  '👍', '❤️', '😂', '🎉', '😮', '😢', '🙏', '🔥', //
  '👀', '✅', '😍', '💯', '👏', '🤔', '😅', '🚀',
];

/// Show a small popover of quick reactions anchored to [anchorContext] (the
/// button that was tapped), calling [onSelected] with the chosen emoji.
///
/// Uses [showMenu] so the popover appears next to the message and auto-clamps
/// to the screen edges, instead of floating in the centre.
Future<void> showReactionPicker(
  BuildContext anchorContext,
  ThemeState themeState,
  void Function(String emoji) onSelected,
) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;

  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;

  final selected = await showMenu<String>(
    context: anchorContext,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    color: themeState.bgElevated,
    // Kill the Material-3 elevation surface tint — it darkens the popover.
    surfaceTintColor: Colors.transparent,
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: themeState.borderPrimary),
    ),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
    items: [
      PopupMenuItem<String>(
        padding: EdgeInsets.zero,
        child: Builder(builder: _emojiGrid),
      ),
    ],
  );

  if (selected != null) onSelected(selected);
}

Widget _emojiGrid(BuildContext menuContext) {
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final e in quickReactionEmojis)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(menuContext).pop(e),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Text(e, style: emojiRunStyle.copyWith(fontSize: 22)),
            ),
          ),
      ],
    ),
  );
}
