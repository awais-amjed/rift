import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/custom_colors.dart';
import 'app_button.dart';
import 'app_modal.dart';
import '../theme/app_text.dart';

/// Ask the user to confirm one action, and answer `true` only if they did.
///
/// Dismissing (Escape, Cancel) answers `false`, never null, so callers can
/// write `if (!await showConfirmDialog(...)) return;`. Set [isDestructive] for
/// anything that deletes or signs out — it turns the badge and the confirm
/// button red.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool isDestructive = false,
}) async {
  final confirmed = await showCustomDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      isDestructive: isDestructive,
    ),
  );
  return confirmed ?? false;
}

/// The body of [showConfirmDialog]. Private — the function is the API, so no
/// call site can forget the "dismiss means no" default.
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool isDestructive;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    required this.isDestructive,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final accent = isDestructive ? CustomColors.error : themeState.primary;
        return Dialog(
          backgroundColor: themeState.bgPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppText.sectionTitle.copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: themeState.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: cancelLabel,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop(false),
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: confirmLabel,
                          variant: isDestructive
                              ? AppButtonVariant.danger
                              : AppButtonVariant.primary,
                          icon: Icon(icon, size: 15, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(true),
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
