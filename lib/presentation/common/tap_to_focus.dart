import 'package:flutter/material.dart';

/// Makes the whole box it wraps focus [focusNode], not just the text inside it.
///
/// A text field only claims the strip its glyphs sit on. Drawn inside something
/// taller — the composer bar, a search row with a magnifier beside it — that
/// leaves most of what *looks* like the field inert: the padding above the
/// line, the gap under it, the icon at the left, the space between the
/// buttons. Clicking there does nothing, and the only reliable way to find the
/// part that works is to aim at the placeholder text. Somebody who knows there
/// is a `TextField` in there can explain that; nobody else should have to.
///
/// So the painted box gets wrapped in this, and the target becomes the shape
/// the eye was already aiming at. Controls inside keep their own taps: a tap is
/// claimed by the innermost recogniser that wants it, so the attach button is
/// still a button and dragging across the text still selects it. Same for the
/// pointer — a nested [MouseRegion] wins, so buttons keep their click cursor
/// while the dead space reads as text.
///
/// Wrapped in a [TextFieldTapRegion] as well, so a tap on the bar counts as a
/// tap *inside* the field rather than one outside it — otherwise the field's
/// own tap-outside handler unfocuses on the way down and this refocuses on the
/// way up, for a caret that blinks off and on for no reason.
class TapToFocus extends StatelessWidget {
  final FocusNode focusNode;

  /// Off while there is nothing to type into — a disabled composer, a bar
  /// showing something else — so it doesn't take a caret the keyboard can
  /// never reach.
  final bool enabled;

  final Widget child;

  const TapToFocus({
    super.key,
    required this.focusNode,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return TextFieldTapRegion(
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          // Opaque rather than deferring to the child: the gaps between the
          // controls are exactly the dead spots this exists to close, and
          // deferring would hand them straight back.
          behavior: HitTestBehavior.opaque,
          onTap: focusNode.requestFocus,
          child: child,
        ),
      ),
    );
  }
}
