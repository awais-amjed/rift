import 'dart:math' show max, min;

import 'package:material_ui/material_ui.dart';

/// The first page's quality chips: equal columns, which go onto more rows where
/// the window is too narrow for [columns] of them at [minWidth], rather than
/// squeezing the words out of them.
class ShareChoiceGrid extends StatelessWidget {
  final int columns;

  /// The narrowest a one-column child can be, at the app's own text size. A
  /// larger system text size asks for more.
  final double minWidth;
  final List<Widget> children;

  const ShareChoiceGrid({
    super.key,
    required this.columns,
    required this.minWidth,
    required this.children,
  });

  static const _gap = 6.0;

  /// How many columns [units] one-column children go in. The rows are evened
  /// out: five that fit four to a row go three and two, not four and one.
  static int acrossFor({
    required int units,
    required int columns,
    required double room,
    required double minWidth,
  }) {
    final fit = max(((room + _gap) / (minWidth + _gap)).floor(), 1);
    final rows = (units / min(columns, fit)).ceil();
    return (units / rows).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        final across = acrossFor(
          units: children.length,
          columns: columns,
          room: room,
          minWidth: minWidth * MediaQuery.textScalerOf(context).scale(1),
        );
        final unit = (room - _gap * (across - 1)) / across;

        final rows = [
          for (var i = 0; i < children.length; i += across)
            [
              for (final child in children.skip(i).take(across))
                SizedBox(width: unit, child: child),
            ],
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          spacing: _gap,
          children: [for (final row in rows) Row(spacing: _gap, children: row)],
        );
      },
    );
  }
}
