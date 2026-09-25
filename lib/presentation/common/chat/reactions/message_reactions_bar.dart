import 'package:flutter/material.dart';

import '../../../../data/classes/message_reaction.dart';
import '../../../../data/constants.dart';
import '../../../theme/theme_context.dart';
import 'reaction_chip.dart';

/// The row of emoji-reaction chips shown under a message, plus a small "add
/// reaction" button. Tapping a chip toggles the local user's reaction; the "+"
/// opens the quick picker, anchored to the button that was tapped.
///
/// Stateful only to remember which chips it has already shown. A reaction
/// arriving is worth a small pop — it is the only sign anything happened to a
/// message already on screen — but scrolling a chat backwards past a hundred
/// old reactions must not set them all off. So the first build primes: whatever
/// is on the message when the bar appears is simply there, and only what turns
/// up afterwards animates.
class MessageReactionsBar extends StatefulWidget {
  final List<MessageReaction> reactions;

  /// Null where this member's role does not let them react: the chips are
  /// still drawn and still say who reacted, they simply do not answer a tap,
  /// and the "+" that adds one is not offered.
  final void Function(String emoji)? onToggle;
  final void Function(BuildContext anchorContext)? onAdd;

  const MessageReactionsBar({
    super.key,
    required this.reactions,
    this.onToggle,
    this.onAdd,
  });

  @override
  State<MessageReactionsBar> createState() => _MessageReactionsBarState();
}

class _MessageReactionsBarState extends State<MessageReactionsBar> {
  /// What was on the message last time. Whatever is here on the first build is
  /// the backlog; a reaction taken off the message leaves, so if it comes back
  /// it is an arrival again — which it is, by any reading somebody watching
  /// would give it.
  Set<String> _shown = const {};

  /// Emoji that were not here a build ago. Only has to be right on the build
  /// that creates the chip — [ReactionChip] captures the answer once and stops
  /// asking, so this going empty on the next rebuild cannot cut a pop short.
  Set<String> _arrived = const {};

  @override
  void initState() {
    super.initState();
    // Primed here rather than in a `late` field initialiser. A `late` field is
    // built on first *access*, and the first access is the `didUpdateWidget`
    // below — by which point `widget` already holds the new list, so the
    // priming would swallow the very first arrival it exists to let through.
    _shown = {for (final r in widget.reactions) r.emoji};
  }

  @override
  void didUpdateWidget(MessageReactionsBar old) {
    super.didUpdateWidget(old);
    final now = {for (final r in widget.reactions) r.emoji};
    _arrived = now.difference(_shown);
    _shown = now;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final r in widget.reactions)
            ReactionChip(
              // Keyed by emoji so a chip's state follows its own reaction when
              // one before it is removed — without this the pop and the bump
              // would land on whichever chip shuffled into that slot.
              key: ValueKey(r.emoji),
              reaction: r,

              onTap: widget.onToggle == null
                  ? null
                  : () => widget.onToggle!(r.emoji),
              isNew: _arrived.contains(r.emoji),
            ),
          if (widget.onAdd case final onAdd?) _AddReactionButton(onTap: onAdd),
        ],
      ),
    );
  }
}

class _AddReactionButton extends StatelessWidget {
  final void Function(BuildContext anchorContext) onTap;

  const _AddReactionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Material(
      color: themeState.bgHover,
      shape: StadiumBorder(side: BorderSide(color: themeState.borderElevated)),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        // The tapped button's context anchors the picker popover.
        onTap: () => onTap(context),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(
            Icons.add_reaction_outlined,
            size: K.iconInline,
            color: themeState.textTertiary,
          ),
        ),
      ),
    );
  }
}
