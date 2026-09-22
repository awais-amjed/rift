import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import 'context_menu_region.dart';

/// Shows a dialog that:
/// - Cannot be dismissed by tapping the barrier, unless [barrierDismissible]
///   — right for a form, where a stray click outside would lose what was
///   typed, and wrong for a picker like the quick switcher, which holds
///   nothing and should go away when the eye moves on
/// - CAN be dismissed by pressing Escape
Future<T?> showCustomDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(ctx).pop(),
      },
      child: Focus(autofocus: true, child: _Entrance(child: builder(ctx))),
    ),
  );
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
  return showCustomDialog<T>(context: context, builder: (_) => modal);
}

/// Opens a dialog from inside a context menu.
///
/// A menu is an overlay entry rather than a route, so it has to dismiss itself
/// before the dialog opens — and its [BuildContext] is deactivated the moment
/// it does. That makes the obvious spelling a trap:
///
/// ```dart
/// dismiss?.call();
/// showCustomDialog(context: menu, builder: (_) => BlocProvider.value(
///   value: menu.read<ServerCubit>(), child: const SomeDialog()));
/// ```
///
/// The `read` runs inside the *route's* builder, which Flutter re-invokes
/// whenever the route rebuilds — and a route rebuilds for reasons that have
/// nothing to do with the dialog. **Resizing the window is enough.** So it
/// works on the first build and throws "Looking up a deactivated widget's
/// ancestor" on the next.
///
/// [build] is therefore called **once, here, while the menu is still mounted**,
/// and the route is handed the finished widget. The navigator is captured for
/// the same reason: it outlives the overlay entry, and the menu's context
/// won't.
Future<T?> showDialogFromMenu<T>({
  required BuildContext context,
  required Widget Function(BuildContext) build,
}) {
  final dismiss = ContextMenuScope.of(context);
  final dialog = build(context);
  final navigator = Navigator.of(context);
  dismiss?.call();
  return showCustomDialog<T>(
    context: navigator.context,
    builder: (_) => dialog,
  );
}
