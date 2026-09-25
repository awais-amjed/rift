import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Sections of a form that sit side by side when there is room for them and
/// stack when there isn't, with a rule between either way.
///
/// A settings form is a handful of independent groups, not one long list, so
/// the only reason to run it down the page is that there is nowhere to put it
/// beside. A wide dialog that scrolls has it backwards — it is spending height
/// it doesn't have on width it isn't using.
class ModalColumns extends StatelessWidget {
  /// One widget per column, in reading order. Each should be a
  /// `mainAxisSize: min` [Column]; this widget supplies the spacing and rules
  /// between them and nothing else.
  final List<Widget> children;

  /// How much room a column needs before it is worth having. Under this the
  /// fields get too narrow to read and the layout stacks instead.
  final double minColumnWidth;

  /// Space either side of the rule. The same number is used above and below it
  /// when stacked, so the two layouts breathe alike.
  static const _gutter = 24.0;

  /// The rule plus both gutters, which is what [VerticalDivider.width] and
  /// [Divider.height] each want.
  static const _ruleExtent = _gutter * 2 + 1;

  const ModalColumns({
    super.key,
    required this.children,
    this.minColumnWidth = 300,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final rule = themeState.borderPrimary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final needed =
            minColumnWidth * children.length +
            _ruleExtent * (children.length - 1);
        return constraints.maxWidth >= needed
            ? _sideBySide(rule)
            : _stacked(rule);
      },
    );
  }

  /// [IntrinsicHeight] so the rule runs the full height of the taller column
  /// rather than stopping where the shorter one ends — or further, to the
  /// minimum height it was given, which is how a page runs it to its foot.
  Widget _sideBySide(Color rule) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              VerticalDivider(width: _ruleExtent, thickness: 1, color: rule),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }

  Widget _stacked(Color rule) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: _ruleExtent, thickness: 1, color: rule),
          children[i],
        ],
      ],
    );
  }
}
