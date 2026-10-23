import 'package:flutter/widgets.dart';

/// Set over a conversation that has its list beside it.
///
/// The list's header carries the button that brings a hidden sidebar back.
/// A conversation alone — on Home, where the list is the sidebar itself, or
/// in a window too narrow for both — has to carry it in its own header, or a
/// hidden sidebar has no way back from there.
class DmListBeside extends InheritedWidget {
  const DmListBeside({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DmListBeside>() != null;

  @override
  bool updateShouldNotify(DmListBeside old) => false;
}
