import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The heart on a directory row: the count, and whether this account is one
/// of it.
///
/// It is the only control in the browser that writes to somebody else's
/// listing, and the only ranking signal the directory has. The count sits
/// beside the heart rather than inside a tooltip because it is what the
/// ordering is made of — a row that is first should be able to say why.
///
/// The filled state waits for central. A like can be refused (an account with
/// no handle claimed cannot vote), and a heart that fills and then empties is
/// worse than one that takes a moment — see `PublicBotsCubit.toggleLike`.
class BotLikeButton extends StatelessWidget {
  final int count;
  final bool liked;

  /// True while this bot's like is in flight. The control stays put and stops
  /// answering rather than swapping in a spinner: it is 24 pixels wide, and
  /// anything that changes size here moves the row under the cursor.
  final bool busy;

  /// Null when there is nobody to like as — signed out of the central
  /// account. The count still shows, because it is still true.
  final VoidCallback? onTap;

  const BotLikeButton({
    super.key,
    required this.count,
    required this.liked,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final enabled = onTap != null && !busy;
    // The accent, not a red heart: `CustomColors` is for success, warning and
    // error, and a like is none of those — borrowing error-rose for it would
    // make "I like this" the same colour as "this went wrong".
    final colour = liked
        ? theme.accentBright
        : (enabled ? theme.textTertiary : theme.textQuaternary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(K.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.react,
                // Scaled rather than faded: the heart is the thing that
                // changed, and a crossfade between two glyphs of the same
                // shape reads as a flicker.
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  key: ValueKey(liked),
                  size: K.iconRow,
                  color: colour,
                ),
              ),
              Text(
                '$count',
                style: AppText.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
