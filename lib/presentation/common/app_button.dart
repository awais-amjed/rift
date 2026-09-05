import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';

enum AppButtonVariant { primary, secondary, danger }

/// Themed button used throughout the app.
///
/// The three variants differ only in how they carry weight: primary is the
/// flat accent, danger is a flat red, and secondary is a hairline ring over
/// a barely-there fill so it recedes beside either of them. No gradient and
/// no glow on the primary — the accent is the ornament.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
  final bool expanded;

  /// Defaults to a standalone button, which is what a dialog footer is. Pass
  /// [K.fieldHeight] only for a button standing *among* fields, so it lines up
  /// with them rather than with the buttons elsewhere in the app.
  final double height;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.expanded = false,
    this.height = K.controlHeight,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;
    final isPrimary = variant == AppButtonVariant.primary;
    final enabled = !isLoading && onPressed != null;

    final fgColor = switch (variant) {
      AppButtonVariant.primary => Colors.white,
      AppButtonVariant.secondary => themeState.textSecondary,
      AppButtonVariant.danger => Colors.white,
    };

    Widget child = isLoading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 7)],
              // Flexible, so a label longer than the width it was given
              // ellipsises instead of overflowing. Callers hand these buttons
              // a hard width all the time — a dialog's action row divides its
              // width evenly — and a button has no say in that, so it must not
              // be able to break the layout it's put in.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.row.copyWith(
                    // Secondary is the quiet option, and carrying less weight
                    // is most of what makes it read that way.
                    fontWeight: variant == AppButtonVariant.secondary
                        ? FontWeight.w600
                        : FontWeight.w700,
                    color: fgColor,
                  ),
                ),
              ),
            ],
          );

    Widget button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (isPrimary) {
            return states.contains(WidgetState.hovered)
                ? themeState.accentBright
                : themeState.primary;
          }
          if (variant == AppButtonVariant.danger) {
            return states.contains(WidgetState.hovered)
                ? CustomColors.errorDark
                : CustomColors.error;
          }
          return states.contains(WidgetState.hovered)
              ? themeState.bgActive
              : themeState.bgHover;
        }),
        foregroundColor: WidgetStatePropertyAll(fgColor),
        // The variants already carry their own hover fill above; Material's
        // extra wash on top would only mud them.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        // Pinned top and bottom rather than via `fixedSize`, which would also
        // stretch the width to infinity.
        minimumSize: WidgetStatePropertyAll(Size(0, height)),
        maximumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
        // Material otherwise pads every button out to a 48px tap target,
        // which would quietly undo the height above.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(K.radiusRow),
          ),
        ),
        side: variant == AppButtonVariant.secondary
            ? WidgetStatePropertyAll(
                BorderSide(color: themeState.borderElevated),
              )
            : null,
      ),
      child: child,
    );

    // Dimmed as a whole rather than by swapping the fill, so a disabled button
    // keeps its shape instead of turning into a different-looking control.
    if (!enabled) button = Opacity(opacity: 0.45, child: button);

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
