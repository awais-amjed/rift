import 'package:flutter/material.dart';

import '../../../../data/classes/message_reaction.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../emoji_text.dart';
import '../../../theme/theme_context.dart';

/// One emoji-reaction chip: the emoji, how many people picked it, and whether
/// you are one of them.
///
/// Moves twice, for two different facts. [isNew] pops the whole chip in, which
/// is the only sign you get that somebody reacted to a message already on
/// screen — without it a chip simply exists, and reactions to a message you
/// are looking at land silently. A count that changes bumps instead: the chip
/// stays put and the number swaps, because the chip was already there and
/// re-popping it would claim something arrived that didn't.
class ReactionChip extends StatefulWidget {
  final MessageReaction reaction;
  final VoidCallback onTap;

  /// Whether this chip appeared after the bar was first built. False for
  /// everything already on a message when it came into view — see
  /// [MessageReactionsBar], which does the deciding. Read once, when the chip
  /// is created, and never again.
  final bool isNew;

  const ReactionChip({
    super.key,
    required this.reaction,
    required this.onTap,
    required this.isNew,
  });

  @override
  State<ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<ReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: AppMotion.state,
    lowerBound: 0,
    upperBound: 0.12,
  );

  /// Whether to play the entrance, decided once.
  ///
  /// Read here rather than from `widget` at build time: the bar can only say
  /// "this is new" on the build that creates the chip, and re-reading it would
  /// tear the wrapper out mid-pop the next time anything rebuilt.
  late final bool _entering = widget.isNew;

  /// Which way the last change went, so the number can travel with it.
  bool _rose = true;

  @override
  void didUpdateWidget(ReactionChip old) {
    super.didUpdateWidget(old);
    // Only when the number actually moves. A rebuild for any other reason — a
    // theme change, the row re-laying out — must not make the chip twitch.
    if (old.reaction.count != widget.reaction.count) {
      _rose = widget.reaction.count > old.reaction.count;
      _bump.forward(from: 0).then((_) {
        if (mounted) _bump.reverse();
      });
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedBuilder(
      animation: _bump,
      builder: (context, child) =>
          Transform.scale(scale: 1 + _bump.value, child: child),
      child: _chip(),
    );

    if (!_entering) return chip;
    // One-shot: the end value never changes, so a later rebuild of the same
    // chip cannot replay it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.enter,
      curve: AppMotion.pop,
      builder: (context, t, child) => Transform.scale(
        scale: t,
        // Opacity trails the scale so the chip is legible for most of the
        // travel rather than fading in at the very end.
        child: Opacity(opacity: t.clamp(0, 1), child: child),
      ),
      child: chip,
    );
  }

  Widget _chip() {
    final themeState = context.theme;
    final mine = widget.reaction.mine;

    return Material(
      color: mine
          ? themeState.primary.withValues(alpha: 0.14)
          : themeState.bgHover,
      shape: StadiumBorder(
        side: BorderSide(
          // Your own reactions are ringed in the accent; everyone else's get
          // a hairline, so a glance says which ones you already pressed.
          color: mine
              ? themeState.primary.withValues(alpha: 0.35)
              : themeState.borderElevated,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.reaction.emoji,
                style: emojiRunStyle.copyWith(fontSize: 13),
              ),
              const SizedBox(width: 5),
              _count(themeState, mine),
            ],
          ),
        ),
      ),
    );
  }

  /// The number, swapped rather than redrawn. Counting up and counting down
  /// travel opposite ways, so the direction says which happened without
  /// anyone having to have been watching the old value.
  Widget _count(ThemeState themeState, bool mine) {
    return AnimatedSwitcher(
      duration: AppMotion.state,
      switchInCurve: AppMotion.settle,
      transitionBuilder: (child, animation) {
        // The arriving number comes from the side it is travelling *from*,
        // and the leaving one goes the opposite way — so a count going up
        // scrolls up and one going down scrolls down. The outgoing child runs
        // this same animation in reverse, which is what makes one tween do
        // both halves.
        final arriving = child.key == ValueKey(widget.reaction.count);
        final from = _rose ? 0.5 : -0.5;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: Offset(0, arriving ? from : -from),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        '${widget.reaction.count}',
        key: ValueKey(widget.reaction.count),
        style: AppText.figure.copyWith(
          color: mine ? themeState.accentBright : themeState.textSecondary,
        ),
      ),
    );
  }
}
