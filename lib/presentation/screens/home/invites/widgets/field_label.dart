import 'package:flutter/material.dart';
import '../../../../theme/app_text.dart';

/// The small caps label above a field in the invite and bot forms.
class FieldLabel extends StatelessWidget {
  final String label;
  final Color textColor;

  const FieldLabel({super.key, required this.label, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AppText.sectionLabel.copyWith(
        letterSpacing: 1.3,
        color: textColor,
      ),
    );
  }
}
