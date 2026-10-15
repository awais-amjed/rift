import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// A checkbox with its sentence beside it, pressed anywhere on the row.
///
/// The box alone is an 18px target; the sentence is what people aim at.
class CheckboxRow extends StatelessWidget {
  /// How tall the compact, shrink-wrapped [Checkbox] is laid out.
  static final double boxHeight =
      kMinInteractiveDimension -
      8 +
      VisualDensity.compact.baseSizeAdjustment.dy;

  static const _style = AppText.body;

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CheckboxRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // The first line centred on the box, not the whole sentence, so a label
    // that wraps keeps the box beside where it starts.
    final line = _style.fontSize! * _style.height!;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: (boxHeight - line) / 2),
                child: Text(
                  label,
                  style: _style.copyWith(color: themeState.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
