import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../responsive/shell_scope.dart';

/// The message body: selectable where there is a cursor, plain where there is
/// a finger.
///
/// [SelectableText] installs its own long-press recognizer, and it wins the
/// gesture arena against the row's. On a phone that means long-pressing a
/// message starts a text selection instead of opening the menu — and since
/// long-press *is* the touch right-click, that took every action a message has
/// with it.
///
/// Dropping selection on touch loses very little. Dragging selection handles
/// around a chat bubble is fiddly on the best day, and the thing it is nearly
/// always in service of — copying the message — is the first entry in the menu
/// that now opens instead.
///
/// It claims the *secondary* tap for the same reason, which cost the same
/// thing on desktop: right-clicking a message opened Flutter's "Select all"
/// toolbar rather than the message menu, and since the text is the largest
/// target in the row, that is where most right-clicks land. [Listener] is the
/// way back — it sees pointer events before the arena is resolved, so it fires
/// whether or not the selection recognizer wins — and the native toolbar is
/// suppressed so the two menus can't both answer.
class MessageText extends StatelessWidget {
  final TextSpan span;

  /// Opens the message menu at the pointer, for the desktop right-click the
  /// selection recognizer would otherwise swallow.
  final void Function(Offset position) onSecondaryTap;

  const MessageText({
    super.key,
    required this.span,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return Text.rich(span);

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryButton) onSecondaryTap(event.position);
      },
      child: SelectableText.rich(
        span,
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      ),
    );
  }
}
