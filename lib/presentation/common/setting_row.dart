import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// A setting: what it is, a line saying what it does, and the one control
/// that changes it at the trailing edge.
///
/// One recipe, because there was nearly two. A switch row and a button row
/// are the same row — the same label over the same explanation with the same
/// gap before the same trailing control — and having both spelled separately
/// is how they drift apart. [SettingToggleRow] is this with a switch in it;
/// anything else passes its own [control].
///
/// The row is not the tap target; the control is. An action that wipes an
/// identity should be exactly as wide as the word for it.
class SettingRow extends StatelessWidget {
  final String title;
  final String description;
  final Widget control;

  const SettingRow({
    super.key,
    required this.title,
    required this.description,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.row.copyWith(color: themeState.textPrimary),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: AppText.secondary.copyWith(
                  height: 1.4,
                  color: themeState.textTertiary,
                ),
              ),
            ],
          ),
        ),
        control,
      ],
    );
  }
}
