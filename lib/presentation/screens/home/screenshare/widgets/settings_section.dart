import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A labeled section container for grouping related settings
class SettingsSection extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.sectionLabel.copyWith(
            letterSpacing: 1.3,
            color: themeState.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}
