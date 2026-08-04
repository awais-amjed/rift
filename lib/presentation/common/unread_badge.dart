import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// Accent pill showing an unread count (capped at "99+"). Used on channel tiles
/// and server rows.
class UnreadBadge extends StatelessWidget {
  final int count;
  final ThemeState themeState;

  const UnreadBadge({super.key, required this.count, required this.themeState});

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
        style: AppText.badge.copyWith(height: 1.2, color: themeState.onPrimary),
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
