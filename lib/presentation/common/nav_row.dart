import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// The sidebar's one row shape — channels, DM entries, anything navigable.
///
/// Three states, and they are not interchangeable: *selected* is where you
/// are, *unread* is where something happened, at rest is everything else.
/// Selected takes the accent gradient with a ring; unread only brightens the
/// text and adds a count, so a long list still reads as one selected row
/// among many rather than a wall of highlights.
class NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isUnread;

  /// Trailing widget — an unread count, a member tally.
  final Widget? trailing;

  final VoidCallback? onTap;

  const NavRow({
    super.key,
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isUnread = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final radius = BorderRadius.circular(K.radiusRow);

        return Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            hoverColor: themeState.bgHover,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: radius,
                // The gradient fades left-to-right so the row reads as lit
                // from its leading edge, not filled like a button.
                gradient: isSelected ? themeState.activeRowGradient : null,
                border: isSelected
                    ? Border.all(color: themeState.channelActiveBorder)
                    : null,
              ),
              child: Row(
                spacing: 9,
                children: [
                  Icon(icon, size: 16, color: _iconColor(themeState)),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle(themeState),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _iconColor(ThemeState themeState) {
    if (isSelected) return themeState.accentBright;
    if (isUnread) return themeState.textPrimary;
    return themeState.textQuaternary;
  }

  TextStyle _labelStyle(ThemeState themeState) {
    if (isSelected) {
      return AppText.row.copyWith(color: themeState.channelActiveText);
    }
    if (isUnread) {
      return AppText.row.copyWith(color: themeState.textPrimary);
    }
    return AppText.rowQuiet.copyWith(color: themeState.textSecondary);
  }
}
