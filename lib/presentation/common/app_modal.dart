import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/constants.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'app_button_height.dart';
import 'app_modal_header.dart';
import 'back_chevron_button.dart';
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

  /// The same, for a sheet — a little more, because what is above a sheet is
  /// the screen it came from and is worth keeping a strip of.
  static const _sheetMaxFraction = 0.88;

  /// Keeps the centred dialog on a phone, where every other modal fills the
  /// screen. For a confirmation: a question with two answers is exactly what a
  /// dialog is for, and a sheet would be too easy to dismiss by accident.
  final bool staysDialogOnPhone;

  /// Shows a phone a page rather than a card: the screen edge to edge, an
  /// arrow for the way back, the title set large, and only the commit in the
  /// footer. For a step in a flow — adding a server — where each step is a
  /// place you move between rather than a box over the app.
  ///
  /// When a page has more than one action, the first is taken to be the way
  /// back and is left to the arrow; a single action is the way back itself.
  final bool pageOnPhone;

  /// Renders as the body of a **bottom sheet** on a phone: a grabber, the
  /// header, and content only as tall as it needs to be, up to
  /// [_sheetMaxFraction] of the window.
  ///
  /// For a modal that is a *glance* rather than a task — a profile, which is
  /// five facts and two buttons. The full-screen phone branch would leave
  /// that as a header at the top of 400px of nothing, and it would cover the
  /// message you opened it from, which is the thing that made you curious.
  /// Opening it as a sheet is the caller's job ([showModalBottomSheet]
  /// supplies the surface and the radius); this only draws what goes inside.
  final bool sheetOnPhone;

  /// What the arrow does on a [pageOnPhone] page. Closes the modal if null.
  final VoidCallback? onBack;

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
    this.pageOnPhone = false,
    this.sheetOnPhone = false,
    this.onBack,
  }) : assert(
         (content == null) != (body == null),
         'Give a modal a content form or a self-scrolling body, not both',
       );

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact && !staysDialogOnPhone) {
      if (sheetOnPhone) return _buildSheetForPhone(context);
      return pageOnPhone
          ? _buildPageForPhone(context)
          : _buildForPhone(context);
    }
    final themeState = context.theme;
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
  }

  /// A phone: the whole screen, less a margin, with the footer pinned where a
  /// thumb is.
  ///
  /// A 448px dialog in a 390px window has no margins left to float in, and a
  /// form sized to its content leaves its buttons wherever the last field
  /// happened to end. Filling the screen puts the commit at the bottom every
  /// time, at the taller thumb height, and gives a long form one scroll.
  Widget _buildForPhone(BuildContext context) {
    final themeState = context.theme;
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

  /// See [sheetOnPhone].
  ///
  /// No [Dialog] and no surface of its own: the sheet route paints both, so
  /// drawing another here would be a card inside a card.
  Widget _buildSheetForPhone(BuildContext context) {
    final themeState = context.theme;
    final borderColor = themeState.borderPrimary;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _sheetMaxFraction,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The grabber says the whole sheet is draggable, which is the
          // gesture that dismisses it — there is no other affordance for
          // that, and a sheet you can only close by reaching for the X is a
          // dialog wearing a rounded top.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: themeState.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
            ),
          ),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  // Everything pressable in here is under a thumb, and the
                  // buttons are the reason the sheet was opened.
                  child: AppButtonHeight(
                    height: K.thumbCtaHeight,
                    child: content!,
                  ),
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
    );
  }

  /// See [pageOnPhone].
  Widget _buildPageForPhone(BuildContext context) {
    final themeState = context.theme;
    final actions = this.actions ?? const <Widget>[];
    final commit = actions.length >= 2 ? actions.last : null;

    final onBack = this.onBack;
    return PopScope(
      // The system back gesture is the arrow: a step goes back a step rather
      // than closing the whole flow out from under it.
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: Dialog.fullscreen(
        backgroundColor: themeState.bgSecondary,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BackChevronButton(
                    onPressed: onBack ?? () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      title,
                      style: AppText.pageTitle.copyWith(
                        color: themeState.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppText.body.copyWith(
                          color: themeState.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child:
                    body ??
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: content,
                    ),
              ),
              if (commit != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: AppButtonHeight(
                    height: K.thumbCtaHeight,
                    child: SizedBox(width: double.infinity, child: commit),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
