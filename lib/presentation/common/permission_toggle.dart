import 'package:flutter/material.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

class PermissionToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool value;

  /// Null disables the toggle (shows it locked/greyed out).
  final ValueChanged<bool>? onChanged;

  final ThemeState themeState;
  final bool isFirst;

  const PermissionToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.themeState,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    final double opacity = enabled ? 1.0 : 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isFirst) Divider(height: 1, color: themeState.borderPrimary),
        Opacity(
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: value
                        ? themeState.primary.withValues(alpha: 0.12)
                        : themeState.bgTertiary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 15,
                    color: value ? themeState.primary : themeState.textTertiary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppText.row.copyWith(
                          fontSize: 13,
                          color: themeState.textPrimary,
                        ),
                      ),
                      Text(
                        description,
                        style: AppText.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: themeState.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: themeState.primary,
                  activeTrackColor: themeState.primary.withValues(alpha: 0.4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
