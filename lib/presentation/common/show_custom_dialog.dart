import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import 'app_sheet.dart';
import 'context_menu/context_menu_scope.dart';
import 'server_scope.dart';

/// Shows a dialog that closes on Escape and on a click outside it — every
/// dialog, so nobody has to learn which ones do. Some once kept a click
/// outside out, to save a half-filled form from a stray one; but Escape closed
/// those all along, and the dialogs that did and did not answer a click
/// outside read as random. A dialog that must not close mid-way — a save
/// under way — says so with a [PopScope], which both answer to.
///
/// The dialog is about the server [context] is about ([ServerScope.carry]).
///
/// [build] runs **once, here, before the route exists**, and the route is
/// handed the finished widget. That is the whole reason it is not called
/// `builder`: a `WidgetBuilder` handed to [showDialog] is re-invoked every
/// time the route rebuilds, and a route rebuilds for reasons that have nothing
/// to do with the dialog — **resizing the window is enough**. Nearly every
/// dialog here opens with `BlocProvider.value(value: context.read<Foo>())`,
/// which is a lookup through the *caller's* element; re-running it after the
/// caller has been unmounted throws, and in a release build the whole app goes
/// grey. Building once, while the caller is certainly still mounted, is what
/// stops that, so [build] must stay a one-shot.
Future<T?> showCustomDialog<T>({
  required BuildContext context,
  required WidgetBuilder build,
}) {
  // Built about the server [context] is about: the route is outside the tree
  // it opens from, and would otherwise know of no server.
  final dialog = ServerScope.carry(context, build(context));
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    // A scope of its own that answers Escape, rather than a shortcut on a
    // node inside the route. When the focused control goes away — a Save
    // button disabling itself once the save lands — focus falls back to the
    // nearest scope, and a handler below that scope never heard the key
    // again: the dialog stopped closing on Escape after the first save.
    builder: (ctx) => FocusScope(
      autofocus: true,
      onKeyEvent: (_, event) => closeOnEscape(ctx, event),
      child: _Entrance(child: dialog),
    ),
  );
}

/// Escape pops the route [context] is in — with maybePop, so a dialog that
/// has put a [PopScope] in the way gets to answer: a plain pop closes the
/// whole dialog out from under a page whose Escape should have been one step
/// back.
KeyEventResult closeOnEscape(BuildContext context, KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
    return KeyEventResult.ignored;
  }
  Navigator.of(context).maybePop();
  return KeyEventResult.handled;
}

/// The last few percent of a dialog's arrival.
///
/// The route already fades the dialog in; this adds the scale, which is what
/// makes it read as opening *over* the app rather than being cross-faded with
/// it. Small on purpose — a dialog is something you are about to type into, so
/// the whole move has to be over before you could have reached it.
///
/// One-shot, and only on the way in. Dismissal is the route's fade alone: you
/// have already decided to close it, and watching it shrink is watching
/// nothing.
class _Entrance extends StatelessWidget {
  final Widget child;

  const _Entrance({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: AppMotion.state,
      // Settling, not [AppMotion.pop] — an overshoot on something this large
      // reads as a wobble rather than as a pop.
      curve: AppMotion.settle,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

/// Helper to show an AppModal as a dialog.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required Widget modal,
}) {
  return showCustomDialog<T>(context: context, build: (_) => modal);
}

/// Opens a dialog from inside a context menu.
///
/// [showCustomDialog] already builds once rather than per rebuild, which is
/// what keeps a `context.read` inside a dialog safe. A menu needs one thing
/// more: it is an overlay entry rather than a route, so it dismisses itself
/// before the dialog opens, and its [BuildContext] is deactivated the moment
/// it does. So [build] runs here, **before** the dismissal, while the menu is
/// still mounted. The navigator is captured for the same reason: it outlives
/// the overlay entry, and the menu's context won't.
///
/// [sheetOnPhone] opens it as a bottom sheet on a phone, for a modal that is
/// one there (`AppModal.sheetOnPhone`), as it is wherever else it opens.
Future<T?> showDialogFromMenu<T>({
  required BuildContext context,
  required Widget Function(BuildContext) build,
  bool sheetOnPhone = false,
}) {
  final dismiss = ContextMenuScope.of(context);
  final dialog = ServerScope.carry(context, build(context));
  final navigator = Navigator.of(context);
  final asSheet = sheetOnPhone && context.layoutMode.isCompact;
  dismiss?.call();
  if (asSheet) return showAppSheet<T>(navigator.context, dialog);
  return showCustomDialog<T>(context: navigator.context, build: (_) => dialog);
}
