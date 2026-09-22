import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../emoji_text.dart';
import '../../popover_surface.dart';

/// Curated quick-reaction emojis. A compact popup — not the full picker — since
/// reactions are usually one of a common handful.
const List<String> quickReactionEmojis = [
  '👍', '❤️', '😂', '🎉', '😮', '😢', '🙏', '🔥', //
  '👀', '✅', '😍', '💯', '👏', '🤔', '😅', '🚀',
];

/// Two rows of eight. Fixed rather than wrapped: the set is curated and its
/// shape is part of the design, so it must not reflow with the popover width.
const int _columns = 8;
const double _cellSize = 29;
const double _popoverWidth = _columns * _cellSize + 20;

/// Show a small popover of quick reactions anchored to [anchorContext] (the
/// button that was tapped), calling [onSelected] with the chosen emoji.
///
/// Uses [showMenu] for positioning and dismissal only — it auto-clamps to the
/// screen edges — while the chrome comes from [PopoverSurface], so this looks
/// like the app's other popovers rather than a Material menu.
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
    // The surface below paints the fill, ring and shadow; Material must not
    // paint a second, differently-coloured one behind it.
    color: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    constraints: const BoxConstraints(
      minWidth: _popoverWidth,
      maxWidth: _popoverWidth,
    ),
    items: [
      const PopupMenuItem<String>(
        padding: EdgeInsets.zero,
        child: Builder(builder: _grid),
      ),
    ],
  );

  if (selected != null) onSelected(selected);
}

Widget _grid(BuildContext menuContext) {
  return PopoverSurface(
    padding: const EdgeInsets.all(10),
    child: GridView.count(
      crossAxisCount: _columns,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: [
        for (final emoji in quickReactionEmojis)
          _EmojiCell(
            emoji: emoji,
            onTap: () => Navigator.of(menuContext).pop(emoji),
          ),
      ],
    ),
  );
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiCell({required this.emoji, required this.onTap});

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
