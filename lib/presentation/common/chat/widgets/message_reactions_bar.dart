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
  final VoidCallback onAdd;

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
  final VoidCallback onTap;

  const _AddReactionButton({required this.themeState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: themeState.bgTertiary,
      shape: StadiumBorder(side: BorderSide(color: themeState.borderPrimary)),
      child: InkWell(
        onTap: onTap,
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

/// Show a small popover of quick reactions; calls [onSelected] with the chosen
/// emoji (and closes).
Future<void> showReactionPicker(
  BuildContext context,
  ThemeState themeState,
  void Function(String emoji) onSelected,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => Center(
      child: Material(
        color: themeState.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        elevation: 8,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final e in quickReactionEmojis)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(e);
                  },
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
  );
}
