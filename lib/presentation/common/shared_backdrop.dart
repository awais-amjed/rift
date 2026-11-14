import 'package:material_ui/material_ui.dart';

/// Lets the frosted badges and buttons over one picture read what is under
/// them once, instead of once each.
///
/// Every `BackdropFilter.grouped` below it shares a backdrop. The first one
/// painted takes a copy of everything painted so far, and the rest reuse that
/// copy and one blur of it (Impeller's `Canvas::SaveLayer`). Each blur on its
/// own ends the frame's drawing so far and copies the picture, which over a
/// stream tile with six of them was six copies a frame.
///
/// So only filters with nothing painted between them belong in one: the
/// picture first, then the glass. Anything painted after the first filter is
/// missing from the copy. Wrap what paints later in a [SharedBackdrop] of its
/// own: a camera over the stream, or a panel that opens in the overlay, which
/// would otherwise still find this one through the widget tree. Filters that
/// overlap each other must not share one either.
///
/// Holds its key for as long as it lives. A bare [BackdropGroup] makes a new
/// key every time it is built, which repaints every filter under it.
class SharedBackdrop extends StatefulWidget {
  final Widget child;

  const SharedBackdrop({super.key, required this.child});

  @override
  State<SharedBackdrop> createState() => _SharedBackdropState();
}

class _SharedBackdropState extends State<SharedBackdrop> {
  final BackdropKey _key = BackdropKey();

  @override
  Widget build(BuildContext context) =>
      BackdropGroup(backdropKey: _key, child: widget.child);
}
