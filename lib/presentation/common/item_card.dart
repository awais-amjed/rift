import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';

/// One item in a short managed list — a voice region, a soundboard clip, a
/// webhook: an inset card with a hairline, its text on the left and its
/// actions on the right.
///
/// Shared because the three were drawn three ways on neighbouring pages of
/// one dialog: a fill with no line, a line in one colour, a line in another,
/// each with its own padding. Long lists of people (members, roles) are plain
/// rows instead; a card per person would be a wall of boxes.
class ItemCard extends StatelessWidget {
  final Widget child;

  /// Ringed in the selection colour, for an item being edited in place.
  final bool selected;

  /// Room on the right is the trailing icon buttons' own padding, so the last
  /// glyph sits as far from the edge as the text does on the left.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(12, 8, 6, 8);

  const ItemCard({super.key, required this.child, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(
          color: selected ? theme.channelActiveBorder : theme.borderPrimary,
        ),
      ),
      child: child,
    );
  }
}
