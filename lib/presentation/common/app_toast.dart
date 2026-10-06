import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';
import '../theme/theme_context.dart';

/// The card every toast is drawn in.
///
/// Toastification's own styles are a separate design — a white card with its
/// own type and radius — so on a dark palette an error arrived as the one
/// bright rectangle in the app, and on any palette it was the one surface
/// that had not been themed. This is the same popover the rest of Rift uses:
/// [ThemeState.bgElevated] over [AppShadows.popover], [K.radiusCard], the
/// [AppText] scale, and the status colour for the type.
class AppToast extends StatelessWidget {
  /// The widest a toast gets. Narrower than toastification's 400 because the
  /// text is the app's, not the package's.
  static const double maxWidth = 360;

  final String title;
  final String description;
  final ToastificationType type;

  /// Dismiss, from the item this was built for.
  final VoidCallback onClose;

  /// Set when clicking the card should do something (and dismiss it). Null
  /// leaves the card inert apart from its close button, and its words
  /// selectable — an error is often something to paste somewhere. A card
  /// that is a button can't be both: a click on its text would start a
  /// selection instead of pressing it.
  final VoidCallback? onTap;

  /// Told when the mouse comes onto the card and leaves it, so the toast can
  /// hold still while it is being read or its text selected.
  final ValueChanged<bool>? onHover;

  const AppToast({
    super.key,
    required this.title,
    required this.description,
    required this.type,
    required this.onClose,
    this.onTap,
    this.onHover,
  });

  /// The status colour for [type]. Info has no status colour of its own —
  /// it is not a status — so it takes the palette's accent.
  Color _accent(BuildContext context) => switch (type) {
    ToastificationType.success => CustomColors.success,
    ToastificationType.warning => CustomColors.warning,
    ToastificationType.error => CustomColors.error,
    // `ToastificationType` is a class of constants rather than an enum, so
    // the compiler cannot see that those are all of them.
    _ => context.theme.primary,
  };

  IconData get _icon => switch (type) {
    ToastificationType.success => Icons.check_circle_rounded,
    ToastificationType.warning => Icons.warning_amber_rounded,
    ToastificationType.error => Icons.error_rounded,
    _ => Icons.info_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final accent = _accent(context);

    // toastification lays every toast out in a column [maxWidth] wide
    // against the window's right margin, and this one shrinks to its text —
    // so left to itself a short toast sat at the column's left, up to a
    // hundred pixels in from where the margin says toasts go. Held to the
    // column's end, every toast's right edge lines up with the margin.
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: _Clickable(
          onTap: onTap,
          onHover: onHover,
          child: Container(
            decoration: BoxDecoration(
              color: theme.bgElevated,
              borderRadius: BorderRadius.circular(K.radiusCard),
              border: Border.all(color: theme.borderElevated),
              boxShadow: AppShadows.popover,
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: K.iconButton, color: accent),
                const SizedBox(width: 10),
                Flexible(child: _selectable(_words(theme))),
                const SizedBox(width: 8),
                _CloseButton(onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _words(ThemeState theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: AppText.strong.copyWith(color: theme.textPrimary)),
      const SizedBox(height: 2),
      Text(
        description,
        style: AppText.row.copyWith(color: theme.textSecondary),
      ),
    ],
  );

  Widget _selectable(Widget words) =>
      onTap == null ? SelectionArea(child: words) : words;
}

class _Clickable extends StatelessWidget {
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final Widget child;

  const _Clickable({
    required this.onTap,
    required this.onHover,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: onTap == null
          ? child
          : GestureDetector(onTap: onTap, child: child),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.close_rounded,
            size: K.iconRow,
            color: theme.textTertiary,
          ),
        ),
      ),
    );
  }
}
