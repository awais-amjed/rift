import 'package:flutter/material.dart';

import '../../../../data/classes/message_reaction.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';

/// The row of emoji-reaction chips shown under a message, plus a small "add
/// reaction" button. Tapping a chip toggles the local user's reaction; the "+"
/// opens a quick emoji picker.
class MessageReactionsBar extends StatelessWidget {
  final List<MessageReaction> reactions;
  final ThemeState themeState;
  final void Function(String emoji) onToggle;

  /// Opens the quick picker, anchored to the tapped "add" button.
  final void Function(BuildContext anchorContext) onAdd;

  const MessageReactionsBar({
    super.key,
    required this.reactions,
    required this.themeState,
    required this.onToggle,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final r in reactions)
            _ReactionChip(
              reaction: r,
              themeState: themeState,
              onTap: () => onToggle(r.emoji),
            ),
          _AddReactionButton(themeState: themeState, onTap: onAdd),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final MessageReaction reaction;
  final ThemeState themeState;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.reaction,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mine = reaction.mine;
    return Material(
      color: mine
          ? themeState.primary.withValues(alpha: 0.16)
          : themeState.bgTertiary,
      shape: StadiumBorder(
        side: BorderSide(
          color: mine ? themeState.primary : themeState.borderPrimary,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reaction.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Text(
                '${reaction.count}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: mine ? themeState.primary : themeState.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddReactionButton extends StatelessWidget {
  final ThemeState themeState;
  final void Function(BuildContext anchorContext) onTap;

  const _AddReactionButton({required this.themeState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: themeState.bgTertiary,
      shape: StadiumBorder(side: BorderSide(color: themeState.borderPrimary)),
      child: InkWell(
        onTap: () => onTap(context),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(
            Icons.add_reaction_outlined,
            size: 15,
            color: themeState.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Curated quick-reaction emojis. A compact popup — not the full picker — since
/// reactions are usually one of a common handful.
const List<String> quickReactionEmojis = [
  '👍', '❤️', '😂', '🎉', '😮', '😢', '🙏', '🔥',
  '👀', '✅', '😍', '💯', '👏', '🤔', '😅', '🚀',
];

/// Show a small popover of quick reactions anchored to [anchorContext] (the
/// button that was tapped), calling [onSelected] with the chosen emoji.
///
/// Uses [showMenu] so the popover appears next to the message and auto-clamps to
/// the screen edges, instead of floating in the center.
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
  final position = RelativeRect.fromRect(anchor, Offset.zero & overlay.size);

  final selected = await showMenu<String>(
    context: anchorContext,
    position: position,
    color: themeState.bgElevated,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: themeState.borderPrimary),
    ),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: Builder(
          builder: (menuContext) => Padding(
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
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  if (selected != null) onSelected(selected);
}
