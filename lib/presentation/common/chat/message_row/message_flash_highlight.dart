import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';

/// The tint left on a message after jumping to it.
///
/// Jumping moves the page under the reader, so the row they asked for is
/// somewhere on a screen they did not choose the shape of. Without a mark
/// the jump reads as having landed somewhere arbitrary — the answer is
/// there and nothing says which line it is.
///
/// [token] changes on every jump rather than naming the row, because the
/// same quote tapped twice has to flash twice: an animation keyed by *what*
/// it points at has already finished, and would sit there doing nothing on
/// the second press. Null means no jump has landed here.
class MessageFlashHighlight extends StatelessWidget {
  final int? token;

  const MessageFlashHighlight({super.key, this.token});

  @override
  Widget build(BuildContext context) {
    if (token == null) return const SizedBox.shrink();
    final theme = context.theme;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        // Keyed by the token so a second jump to the same row starts over
        // instead of resuming a tween that has already run out.
        key: ValueKey(token),
        tween: Tween(begin: 1, end: 0),
        duration: AppMotion.linger,
        curve: AppMotion.settle,
        builder: (context, t, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: 0.16 * t),
            border: Border(
              left: BorderSide(
                color: theme.primary.withValues(alpha: t),
                width: K.messageFlashRule,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
