import 'package:flutter/material.dart';

/// The actions at the end of a panel or dialog: gathered at the trailing
/// edge, every button the width of the widest label.
///
/// Never one stretched across the row. Dividing the footer between a Cancel
/// and the thing it cancels sizes Cancel by how many buttons there happen to
/// be, and a lone primary filling the width reads as a form's submit rather
/// than one of two choices. Equal widths at the widest label is what makes a
/// pair read as a pair.
///
/// The width comes from [IntrinsicWidth]: a row's intrinsic width with
/// flexible children is the widest child times the number of children, so
/// each [Expanded] lands on the widest label.
class ButtonFooter extends StatelessWidget {
  final List<Widget> buttons;

  /// Trailing by default, which is right for a dialog: the buttons sit at
  /// the corner the eye ends on. Start-aligned in a settings pane, where a
  /// form is left-aligned in a panel that can be twice as wide as it is and
  /// a button at the far edge reads as belonging to nothing.
  final MainAxisAlignment alignment;

  const ButtonFooter({
    super.key,
    required this.buttons,
    this.alignment = MainAxisAlignment.end,
  });

  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignment,
      children: [
        // Flexible, so the pair is bounded by the row: a Row hands a plain
        // child infinite width, and two long labels would then overflow
        // rather than share what there is and ellipsise.
        Flexible(
          child: IntrinsicWidth(
            child: Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(child: buttons[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
