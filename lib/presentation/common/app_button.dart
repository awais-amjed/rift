import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';

enum AppButtonVariant { primary, secondary, danger }

/// Themed button used throughout the app.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
  final bool expanded;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;

    Color bgColor;
    Color fgColor;

    switch (variant) {
      case AppButtonVariant.primary:
        bgColor = themeState.primary;
        fgColor = Colors.white;
        break;
      case AppButtonVariant.secondary:
        bgColor = themeState.bgTertiary;
        fgColor = themeState.textSecondary;
        break;
      case AppButtonVariant.danger:
        bgColor = CustomColors.error;
        fgColor = Colors.white;
        break;
    }

    Widget child = isLoading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 6)],
              Text(
                label,
                style: AppText.row.copyWith(fontSize: 14, color: fgColor),
              ),
            ],
          );

    final isPrimary = variant == AppButtonVariant.primary;

    Widget button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        // Primary buttons paint their gradient behind the button, so the
        // button itself stays transparent — a solid fill would cover it.
        backgroundColor: isPrimary ? Colors.transparent : bgColor,
        foregroundColor: fgColor,
        disabledBackgroundColor: isPrimary
            ? Colors.transparent
            : bgColor.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(K.radiusCard),
        ),
        elevation: 0,
      ),
      child: child,
    );

    if (isPrimary) {
      final enabled = !isLoading && onPressed != null;
      button = DecoratedBox(
        decoration: BoxDecoration(
          gradient: themeState.actionGradient,
          borderRadius: BorderRadius.circular(K.radiusCard),
          boxShadow: enabled
              ? AppShadows.accentGlow(themeState.primary, blurRadius: 20, dy: 4)
              : null,
        ),
        // Dimmed as a whole rather than by swapping the fill, so a disabled
        // primary button keeps its shape instead of turning into a
        // different-looking control.
        child: Opacity(opacity: enabled ? 1 : 0.5, child: button),
      );
    }

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
