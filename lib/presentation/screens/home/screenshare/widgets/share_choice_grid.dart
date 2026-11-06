import 'dart:math' show max, min;

import 'package:flutter/material.dart';

/// A selection row of the share dialog: equal columns, which go onto more rows
/// where the window is too narrow for [columns] of them at [minWidth], rather
/// than squeezing the words out of them.
///
/// Worked out by hand rather than with flexes, so that the bitrate's custom box
/// ([lastSpan]) covers exactly the columns above it, the gap between them too.
class ShareChoiceGrid extends StatelessWidget {
  final int columns;

  /// The narrowest a one-column child can be, at the app's own text size. A
  /// larger system text size asks for more.
  final double minWidth;
  final List<Widget> children;

  /// How many columns the last child takes.
  final int lastSpan;

  const ShareChoiceGrid({
    super.key,
    required this.columns,
    required this.children,
    this.minWidth = 72,
    this.lastSpan = 1,
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
          units: children.length + lastSpan - 1,
          columns: columns,
          room: room,
          minWidth: minWidth * MediaQuery.textScalerOf(context).scale(1),
        );
        final unit = (room - _gap * (across - 1)) / across;

        final rows = <List<Widget>>[[]];
        var used = 0;
        for (var i = 0; i < children.length; i++) {
          final span = i == children.length - 1 ? min(lastSpan, across) : 1;
          if (used + span > across) {
            rows.add([]);
            used = 0;
          }
          rows.last.add(
            SizedBox(
              width: unit * span + _gap * (span - 1),
              child: children[i],
            ),
          );
          used += span;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          spacing: _gap,
          children: [for (final row in rows) Row(spacing: _gap, children: row)],
        );
      },
    );
  }
}
