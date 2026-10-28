import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../logic/services/window_dim.dart';

/// Where Escape reaches the [LiveBar] from something focused in the chat.
///
/// Wraps the whole chat, history and composer both, so a key from a field
/// there bubbles through whatever is on the way first: a message being edited
/// cancels and the bar stays open, while the message box, which has no Escape
/// of its own, lets it through to fold the bar. With nothing focused the bar
/// hears Escape itself.
class LiveBarEscape extends StatefulWidget {
  final Widget child;

  const LiveBarEscape({super.key, required this.child});

  static LiveBarEscapeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<LiveBarEscapeState>();

  @override
  State<LiveBarEscape> createState() => LiveBarEscapeState();
}

class LiveBarEscapeState extends State<LiveBarEscape> {
  /// The bar's fold, answering whether it had a line open to fold.
  bool Function()? _fold;

  void attach(bool Function() fold) => _fold = fold;

  void detach(bool Function() fold) {
    if (identical(_fold, fold)) _fold = null;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    // The overlaid member list is over the chat, so its Escape comes first.
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        WindowDim.overlay.value) {
      return KeyEventResult.ignored;
    }
    return (_fold?.call() ?? false)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}
