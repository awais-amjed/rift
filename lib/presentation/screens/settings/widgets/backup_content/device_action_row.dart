import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One thing you can do to this device: a label, a line saying what it
/// costs, and the button that does it at the trailing edge.
///
/// The whole row is not the tap target — the button is. An action that wipes
/// an identity should be exactly as wide as the word for it.
class DeviceActionRow extends StatelessWidget {
  final String label;
  final String description;
  final Widget button;

  const DeviceActionRow({
    super.key,
    required this.label,
    required this.description,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      spacing: 16,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppText.row.copyWith(color: theme.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppText.secondary.copyWith(
                  height: 1.4,
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
        button,
      ],
    );
  }
}
