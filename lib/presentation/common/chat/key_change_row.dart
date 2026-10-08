import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../../logic/services/clock_time.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';

/// What a DM's list needs to draw the other person's key changes: whose key,
/// when each change was noticed, and the way to check the new one.
class KeyChangeLines {
  final String name;
  final List<DateTime> at;

  /// Open the safety code. Null leaves the line a statement.
  final VoidCallback? onCheck;

  const KeyChangeLines({required this.name, required this.at, this.onCheck});
}

/// The other person's safety key changed: one line between the messages, at
/// the time this device noticed, in the place a reader is already looking.
///
/// Amber, not red. It is usually a reinstall or a restored backup, and the
/// line cannot tell which — the safety code can, so the line leads there.
class KeyChangeRow extends StatelessWidget {
  final DateTime at;
  final KeyChangeLines lines;

  const KeyChangeRow({super.key, required this.at, required this.lines});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tint = theme.statusInk(CustomColors.warning);
    final check = lines.onCheck;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        spacing: 8,
        children: [
          Icon(Icons.key_rounded, size: K.iconRow, color: tint),
          Flexible(
            child: Text(
              '${lines.name}\'s safety key changed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.secondary.copyWith(color: theme.textSecondary),
            ),
          ),
          if (check != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: check,
                child: Text(
                  'Compare codes',
                  style: AppText.secondary.copyWith(color: tint),
                ),
              ),
            ),
          Text(
            formatClock(at.toLocal()),
            style: AppText.meta.copyWith(color: theme.textTertiary),
          ),
        ],
      ),
    );
  }
}
