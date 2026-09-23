import 'package:flutter/material.dart';
import '../theme/app_text.dart';

/// The small caps label above a field.
///
/// The one recipe, because a panel that spells its own label reaches for a
/// different style and ends up with sentence case beside small caps on the
/// same screen. [AppTextField] draws this shape for the fields that have a
/// label of their own; this is for the controls that do not.
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
