import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';

/// The lock on a private channel's glyph.
///
/// Small and permanent, like the "Encrypted" chip in the header: it is a
/// standing fact about the room rather than a state that changes, so it does
/// not compete with the unread badge and does not animate with selection.
///
/// Ringed in the sidebar's own background so it reads as a badge sitting on the
/// glyph rather than a second icon crowding it.
class ChannelLockBadge extends StatelessWidget {
  final ThemeState themeState;

  const ChannelLockBadge({super.key, required this.themeState});

  @override
  Widget build(BuildContext context) {
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
