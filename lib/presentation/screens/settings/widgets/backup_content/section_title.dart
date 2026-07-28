import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';

class SectionTitle extends StatelessWidget {
  final String label;
  final ThemeState themeState;

  const SectionTitle({required this.label, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: themeState.textPrimary,
      ),
    );
  }
}
