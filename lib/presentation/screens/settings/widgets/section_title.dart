import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';

/// The heading above a group of settings. Every tab uses this, so the one
/// place to change how a settings heading looks is here.
class SectionTitle extends StatelessWidget {
  final String label;
  final ThemeState themeState;

  const SectionTitle({
    super.key,
    required this.label,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: themeState.textPrimary,
      ),
    );
  }
}
