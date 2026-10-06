import 'package:flutter/material.dart';

import '../../../responsive/shell_scope.dart';

/// A message row's selection: the whole row, not the strip of glyphs.
///
/// The body used to be a `SelectableText`, which only answers inside the
/// box its words fill. A drag that began in the row's padding, beside the
/// last word of a short line or in the gap above the first had nothing
/// under it, so selecting a whole message meant landing the press exactly on
/// the edge of its first or last letter. Over the row, a drag from anywhere
/// in it starts at the nearest letter, the way it does in a browser.
///
/// Its own menu is suppressed: the row's right-click opens the message menu
/// (with Copy first), and both answering would stack two menus. The row
/// listens for that click with a `Listener`, which sees it whether or not
/// this region wins the gesture.
///
/// Not on a phone. A selection takes the long press, and the long press *is*
/// the touch right-click — it would take every action a message has with
/// it — while dragging handles around a chat bubble is fiddly on the best day
/// and nearly always in service of copying, which the menu does.
class MessageSelectionArea extends StatelessWidget {
  final Widget child;

  const MessageSelectionArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return child;
    return SelectionArea(
      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      child: child,
    );
  }
}
