import 'dart:math' show max, min;

import 'package:flutter/material.dart';

/// A selection row of the share dialog: equal columns, which go onto more rows
/// where the window is too narrow for [columns] of them at [minWidth].
///
/// Worked out by hand rather than with flexes, so that the bitrate's custom box
/// ([lastSpan]) covers exactly the columns above it, the gap between them too.
class ShareChoiceGrid extends StatelessWidget {
  final int columns;
  final double minWidth;
  final List<Widget> children;

  /// How many columns the last child takes.
  final int lastSpan;

  const ShareChoiceGrid({
    super.key,
    required this.columns,
    required this.children,
    this.minWidth = 64,
    this.lastSpan = 1,
  });

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        final fit = ((room + _gap) / (minWidth + _gap)).floor();
        final across = min(columns, max(fit, 1));
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
