import 'package:flutter/widgets.dart';

/// The phone shell's own navigation, for the widgets on its pages.
///
/// Most of the phone's navigation needs nothing from here: opening a chat or a
/// DM is the same cubit call as on a desktop, and the shell pushes the page
/// because it watches for it. What is left is the part with no cubit behind
/// it — bringing the call you are already in back to the front.
class MobileShellScope extends InheritedWidget {
  /// Puts the call page on top. The call itself is untouched; this is only
  /// about what is on screen.
  final VoidCallback openCall;

  /// Whether the call page is the one on screen, so the bar that stands in
  /// for it knows to step aside.
  final bool callOnTop;

  const MobileShellScope({
    super.key,
    required this.openCall,
    required this.callOnTop,
    required super.child,
  });

  /// Null outside the phone shell — on a desktop, and on screens with a
  /// layout of their own such as settings.
  static MobileShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileShellScope>();

  @override
  bool updateShouldNotify(MobileShellScope old) => callOnTop != old.callOnTop;
}
