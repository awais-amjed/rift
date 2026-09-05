import 'package:flutter/material.dart';

import '../../../../../theme/theme_context.dart';

/// The lock on a private channel's glyph.
///
/// Small and permanent, like the "Encrypted" chip in the header: it is a
/// standing fact about the room rather than a state that changes, so it does
/// not compete with the unread badge and does not animate with selection.
///
/// Ringed in the sidebar's own background so it reads as a badge sitting on the
/// glyph rather than a second icon crowding it.
class ChannelLockBadge extends StatelessWidget {
  const ChannelLockBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: themeState.bgSecondary,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.lock_rounded, size: 9, color: themeState.textTertiary),
    );
  }
}
