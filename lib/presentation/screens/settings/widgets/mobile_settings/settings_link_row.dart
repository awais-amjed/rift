import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A row in a phone's settings list that opens a section: its name, what is
/// behind it, and a chevron — at least a thumb tall, taller with a subtitle.
class SettingsLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// A line under the label saying what the section holds.
  final String? subtitle;

  /// The section's current value, set against the chevron — "Indigo · Dark".
  final String? value;

  final VoidCallback onTap;

  const SettingsLinkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 20, color: theme.accentBright),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppText.row.copyWith(color: theme.textPrimary),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(
                            color: theme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: AppText.meta.copyWith(color: theme.textTertiary),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.textQuaternary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
