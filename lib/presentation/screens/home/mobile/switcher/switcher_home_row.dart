import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/unread_badge.dart';
import '../../../../theme/theme_context.dart';
import 'switcher_row.dart';

/// Home — the central tier — at the top of the switcher, above every server,
/// because it is the one place that is yours rather than a server's.
class SwitcherHomeRow extends StatelessWidget {
  final bool selected;
  final int unread;
  final VoidCallback onTap;

  const SwitcherHomeRow({
    super.key,
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SwitcherRow(
      selected: selected,
      boxed: true,
      leading: Container(
        width: SwitcherRow.leadingSize,
        height: SwitcherRow.leadingSize,
        decoration: BoxDecoration(
          color: theme.primary,
          borderRadius: BorderRadius.circular(
            SwitcherRow.leadingSize * K.avatarRadiusRatio,
          ),
        ),
        child: Icon(Icons.forum_rounded, size: 19, color: theme.onPrimary),
      ),
      title: 'Home',
      subtitle: Text(
        'Your central DMs',
        style: SwitcherRow.subtitleStyle(theme),
      ),
      trailing: unread > 0 ? UnreadBadge(count: unread) : null,
      onTap: onTap,
    );
  }
}
