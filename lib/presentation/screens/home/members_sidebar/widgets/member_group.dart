import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// "ONLINE — 4" style heading above a group of member rows.
class MemberGroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final ThemeState themeState;

  const MemberGroupHeader({
    super.key,
    required this.label,
    required this.count,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Text(
        '$label — $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: themeState.textQuaternary,
        ),
      ),
    );
  }
}
