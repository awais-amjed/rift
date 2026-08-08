import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// Accent pill showing an unread count (capped at "99+"). Used on channel
/// tiles, DM rows and server rows.
///
/// There is one style on purpose. A solid accent pill is the sidebar's loudest
/// mark and it always means the same thing — messages you haven't read — so
/// nothing else in the app is allowed to borrow the shape for a plain tally.
class UnreadBadge extends StatelessWidget {
  final int count;
  final ThemeState themeState;

  const UnreadBadge({
    super.key,
    required this.count,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: themeState.primary,
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        // The count is knocked *out* of the accent rather than written on it, so
        // the ink is the canvas the pill floats over — near-black in dark,
        // near-white in light. `onPrimary` is white in both, which turns the
        // dark palette's bright accent into a low-contrast smudge.
        style: AppText.badge.copyWith(
          height: 1.2,
          color: themeState.bgPrimary,
        ),
      ),
    );
  }
}

/// Small accent dot — a presence-only unread hint (e.g. "another server has
/// activity") where a number would be noise.
class UnreadDot extends StatelessWidget {
  final ThemeState themeState;
  final double size;

  const UnreadDot({super.key, required this.themeState, this.size = 8});

  @override
  Widget build(BuildContext context) {
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
