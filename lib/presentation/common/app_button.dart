import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
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
        bgColor = CustomColors.primary;
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ],
          );

    final button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        disabledBackgroundColor: bgColor.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: child,
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
