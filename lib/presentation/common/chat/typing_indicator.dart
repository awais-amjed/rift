import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';

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

  String get _label {
    switch (names.length) {
      case 0:
        return '';
      case 1:
        return '${names[0]} is typing';
      case 2:
        return '${names[0]} and ${names[1]} are typing';
      case 3:
        return '${names[0]}, ${names[1]} and ${names[2]} are typing';
      default:
        return 'Several people are typing';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
      child: Row(
        children: [
          _TypingDots(color: themeState.textTertiary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
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
                  width: 5,
                  height: 5,
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
