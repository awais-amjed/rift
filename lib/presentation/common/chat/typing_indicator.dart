import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text.dart';

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
          _TypingDots(color: themeState.accentBright),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: who,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: themeState.textSecondary,
                    ),
                  ),
                  TextSpan(text: phrase),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              style: AppText.secondary.copyWith(
                fontSize: 11.5,
                color: themeState.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three dots that pulse in sequence.
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot lags the previous by a third of the cycle.
            final phase = (_controller.value - i * 0.2) % 1.0;
            // Ease up then back down over the phase for a gentle pulse.
            final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
              child: Opacity(
                opacity: 0.3 + 0.7 * t,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
