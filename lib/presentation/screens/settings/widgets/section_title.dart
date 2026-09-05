import 'package:flutter/material.dart';

import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The heading above a group of settings. Every tab uses this, so the one
/// place to change how a settings heading looks is here.
class SectionTitle extends StatelessWidget {
  final String label;
  const SectionTitle({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Text(
      label,
      style: AppText.sectionTitle.copyWith(color: themeState.textPrimary),
    );
  }
}
