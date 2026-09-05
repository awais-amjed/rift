import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../data/constants.dart';

/// Small icon badge with tooltip used in member rows (admin, manager,
/// muted, deafened, ...).
class MemberBadge extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final ThemeState themeState;

  const MemberBadge({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }
}
