import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text.dart';
import '../loading_dots.dart';

/// A slim "… is typing" strip shown just above the composer. Renders nothing
/// when [names] is empty, so callers can place it unconditionally.
class TypingIndicator extends StatelessWidget {
  final List<String> names;
  final ThemeState themeState;

  const TypingIndicator({
    super.key,
    required this.names,
    required this.themeState,
  });

  /// Who is typing, and the verb phrase that follows them — kept apart so the
  /// names can carry weight while the phrase stays quiet.
  (String, String) get _parts {
    switch (names.length) {
      case 0:
        return ('', '');
      case 1:
        return (names[0], ' is typing');
      case 2:
        return ('${names[0]} and ${names[1]}', ' are typing');
      case 3:
        return ('${names[0]}, ${names[1]} and ${names[2]}', ' are typing');
      default:
        return ('Several people', ' are typing');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Grows and collapses rather than appearing and vanishing. It sits between
    // the message list and the composer, so every time somebody started or
    // stopped typing the whole conversation jumped by the height of this row —
    // motion nobody asked for, caused by having none. Anchored to the bottom,
    // so it slides out from behind the composer and back under it.
    return AnimatedSize(
      duration: AppMotion.state,
      curve: AppMotion.settle,
      alignment: Alignment.bottomLeft,
      child: names.isEmpty ? const SizedBox(width: double.infinity) : _row(),
    );
  }

  Widget _row() {
    final (who, phrase) = _parts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
      child: Row(
        children: [
          // Accent-tinted rather than grey: the dots are the one moving thing
          // above the composer, and the design has them read as live.
          LoadingDots(color: themeState.accentBright),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: who,
                    style: AppText.secondaryStrong.copyWith(
                      color: themeState.textSecondary,
                    ),
                  ),
                  TextSpan(text: phrase),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              style: AppText.secondary.copyWith(color: themeState.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
