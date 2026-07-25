import 'package:flutter/material.dart';

import '../../logic/cubits/theme/theme_cubit.dart';

/// Accent pill showing an unread count (capped at "99+"). Used on channel tiles
/// and server rows.
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
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: themeState.primary,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: themeState.onPrimary,
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
