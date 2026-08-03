import 'package:flutter/material.dart';

import '../../../../data/classes/message_reaction.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../emoji_text.dart';

/// The row of emoji-reaction chips shown under a message, plus a small "add
/// reaction" button. Tapping a chip toggles the local user's reaction; the "+"
/// opens the quick picker, anchored to the button that was tapped.
class MessageReactionsBar extends StatelessWidget {
  final List<MessageReaction> reactions;
  final ThemeState themeState;
  final void Function(String emoji) onToggle;
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
              Text(reaction.emoji, style: emojiRunStyle.copyWith(fontSize: 14)),
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
        // The tapped button's context anchors the picker popover.
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
