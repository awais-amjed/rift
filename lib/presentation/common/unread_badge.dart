import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// Accent pill showing an unread count (capped at "99+"). Used on channel
/// tiles, DM rows and server rows.
///
/// There is one style on purpose. A solid accent pill is the sidebar's loudest
/// mark and it always means the same thing — messages you haven't read — so
/// nothing else in the app is allowed to borrow the shape for a plain tally.
///
/// It pops when the number goes *up*, and only then. A badge is a claim that
/// something happened, so it should move when something does — but a sidebar
/// of them all popping the moment the app opens would be claiming a dozen
/// arrivals that are really just the first paint. So the first build is
/// silent, and a count going down (you read some of it) is silent too: nothing
/// arrived.
class UnreadBadge extends StatefulWidget {
  final int count;

  /// A muted conversation still counts what arrived in it — muting is not
  /// pretending nothing happened — but it stops shouting about it. The pill
  /// drops to a quiet outline, so the number is still there to read and no
  /// longer competes with the ones that asked for attention.
  final bool isMuted;

  const UnreadBadge({super.key, required this.count, this.isMuted = false});

  @override
  State<UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<UnreadBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: AppMotion.state,
    lowerBound: 0,
    upperBound: 0.18,
  );

  @override
  void didUpdateWidget(UnreadBadge old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) {
      _pop.forward(from: 0).then((_) {
        if (mounted) _pop.reverse();
      });
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) =>
          Transform.scale(scale: 1 + _pop.value, child: child),
      child: _pill(),
    );
  }

  Widget _pill() {
    final themeState = context.theme;
    final isMuted = widget.isMuted;

    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isMuted ? Colors.transparent : themeState.primary,
        border: isMuted
            ? Border.all(color: themeState.textTertiary.withValues(alpha: 0.45))
            : null,
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.count > 99 ? '99+' : '${widget.count}',
        // The count is knocked *out* of the accent rather than written on it, so
        // the ink is the canvas the pill floats over — near-black in dark,
        // near-white in light. `onPrimary` is white in both, which turns the
        // dark palette's bright accent into a low-contrast smudge.
        style: AppText.badge.copyWith(
          height: 1.2,
          color: isMuted ? themeState.textTertiary : themeState.bgPrimary,
        ),
      ),
    );
  }
}

/// Small accent dot — a presence-only unread hint (e.g. "another server has
/// activity") where a number would be noise.
class UnreadDot extends StatelessWidget {
  final double size;

  const UnreadDot({super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: themeState.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}
