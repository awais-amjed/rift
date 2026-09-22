import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// The unread count riding on a server chip's corner.
///
/// It carries a ring in the rail's own background colour so it stays legible
/// where it overlaps the avatar beneath it.
class RailUnreadBadge extends StatelessWidget {
  final int count;

  /// Counts above this show as "N+" — past a point the exact number stops
  /// being information and the badge just needs to stay one chip wide.
  static const int max = 99;

  const RailUnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: themeState.primary,
        borderRadius: BorderRadius.circular(K.radiusPill),
        border: Border.all(color: themeState.bgSecondary, width: 2),
      ),
      child: Text(
        count > max ? '$max+' : '$count',
        textAlign: TextAlign.center,
        style: AppText.badge.copyWith(color: themeState.onPrimary),
      ),
    );
  }
}
