import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';
import 'switcher_header.dart';

/// Home's mark, in the slot a server's avatar takes — or, with no server at
/// all, a plus that says where joining one starts.
class SwitcherHomeMark extends StatelessWidget {
  final bool isHome;

  const SwitcherHomeMark({super.key, required this.isHome});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      width: SwitcherHeader.avatarSize,
      height: SwitcherHeader.avatarSize,
      decoration: BoxDecoration(
        color: isHome ? theme.primary : theme.bgActive,
        borderRadius: BorderRadius.circular(
          SwitcherHeader.avatarSize * K.avatarRadiusRatio,
        ),
      ),
      child: Icon(
        isHome ? Icons.forum_rounded : Icons.add_rounded,
        size: K.iconButton,
        color: isHome ? theme.onPrimary : theme.textSecondary,
      ),
    );
  }
}
