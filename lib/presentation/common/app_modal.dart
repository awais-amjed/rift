import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import 'app_button_height.dart';
import 'app_modal_header.dart';
import 'button_footer.dart';
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
        SingleActivator(LogicalKeyboardKey.escape): () =>
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

/// Base modal used for every dialog in the app.
///
/// A dialog is either a form, which goes in [content] and scrolls as a whole
/// when the window is short, or a list, which goes in [body] and scrolls
/// itself. The shell — surface, radius, header, footer — is the same either
/// way, which is the point: a dialog that hand-rolls its chrome because its
/// body scrolls is a second dialog design.
class AppModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleIcon;

  /// A figure beside the title. See [AppModalHeader.count].
  final int? count;

  /// Icon buttons in the header, before the close button.
  final List<Widget> headerActions;

  /// A form: padded, and scrolled as a whole when there is not room for it.
  /// Exactly one of [content] and [body] is given.
  final Widget? content;

  /// A body that owns its own scrolling — a `ListView` with a search row
  /// above it, say. Given the remaining height and no padding; what is inside
  /// decides both.
  final Widget? body;

  final List<Widget>? actions;
  final double maxWidth;

  /// Where a long form stops growing and starts scrolling.
  ///
  /// Defaults to [_maxHeightFraction] of the window rather than a fixed number
  /// of pixels: the point of the cap is to leave the app visible around the
  /// dialog, and how much room there is to leave is a property of the window,
  /// not of the form. A fixed cap made the create-server form scroll on a
  /// screen with several hundred pixels to spare.
  final double? maxHeight;

  /// How much of the window a modal may fill before it starts scrolling.
  static const _maxHeightFraction = 0.85;

  /// Keeps the centred dialog on a phone, where every other modal fills the
  /// screen. For a confirmation: a question with two answers is exactly what a
  /// dialog is for, and a sheet would be too easy to dismiss by accident.
  final bool staysDialogOnPhone;

  const AppModal({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    this.count,
    this.headerActions = const [],
    this.content,
    this.body,
    this.actions,
    this.maxWidth = 448,
    this.maxHeight,
    this.staysDialogOnPhone = false,
  }) : assert(
         (content == null) != (body == null),
         'Give a modal a content form or a self-scrolling body, not both',
       );

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact && !staysDialogOnPhone) {
      return _buildForPhone(context);
    }
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final borderColor = themeState.borderPrimary;

        return Dialog(
          // The design puts dialogs on the *panel* surface, with the shadow
          // doing the lifting — elevated is reserved for menus and popovers,
          // which open on top of dialogs and need to out-rank them.
          backgroundColor: themeState.bgSecondary,
          // Flutter's default inset is 40 a side, which is a tenth of a phone
          // spent on margin before the dialog's own padding starts. [maxWidth]
          // still decides the size wherever there is room for it; this only
          // changes what "no room" leaves behind.
          insetPadding: EdgeInsets.symmetric(
            horizontal: context.layoutMode.isCompact ? K.panelGutter * 1.6 : 40,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(K.radiusCard),
            side: BorderSide(color: themeState.borderElevated),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight:
                  maxHeight ??
                  MediaQuery.sizeOf(context).height * _maxHeightFraction,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppModalHeader(
                  title: title,
                  subtitle: subtitle,
                  titleIcon: titleIcon,
                  count: count,
                  actions: headerActions,
                ),
                Divider(height: 1, color: borderColor),
                Flexible(
                  child:
                      body ??
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        child: content,
                      ),
                ),
                if (actions != null) ...[
                  Divider(height: 1, color: borderColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: ButtonFooter(buttons: actions!),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// A phone: the whole screen, less a margin, with the footer pinned where a
  /// thumb is.
  ///
  /// A 448px dialog in a 390px window has no margins left to float in, and a
  /// form sized to its content leaves its buttons wherever the last field
  /// happened to end. Filling the screen puts the commit at the bottom every
  /// time, at the taller thumb height, and gives a long form one scroll.
  Widget _buildForPhone(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final borderColor = themeState.borderPrimary;
    final safe = MediaQuery.paddingOf(context);
    const margin = 10.0;

    return Dialog(
      backgroundColor: themeState.bgSecondary,
      insetPadding: EdgeInsets.fromLTRB(
        margin,
        margin + safe.top,
        margin,
        margin + safe.bottom,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(K.radiusCard),
        side: BorderSide(color: themeState.borderElevated),
      ),
      child: SizedBox.expand(
        child: Column(
          children: [
            AppModalHeader(
              title: title,
              subtitle: subtitle,
              titleIcon: titleIcon,
              count: count,
              actions: headerActions,
            ),
            Divider(height: 1, color: borderColor),
            Expanded(
              child:
                  body ??
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: content,
                  ),
            ),
            if (actions != null) ...[
              Divider(height: 1, color: borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: AppButtonHeight(
                  height: K.thumbCtaHeight,
                  child: ButtonFooter(buttons: actions!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
