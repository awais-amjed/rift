import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';
import 'app_button.dart';
import 'app_modal.dart';
import 'context_menu_region.dart';
import 'icon_tile.dart';

/// Ask the user to confirm one action, and answer `true` only if they did.
///
/// Dismissing (Escape, Cancel) answers `false`, never null, so callers can
/// write `if (!await showConfirmDialog(...)) return;`. Set [isDestructive] for
/// anything that deletes or signs out — it turns the badge and the confirm
/// button red.
///
/// Safe to call from inside a context menu. The menu has to be dismissed
/// before the dialog opens — it is an overlay entry, and it takes the dialog
/// down with it otherwise — so this detects the menu and steps out to the
/// navigator first, which is what `showDialogFromMenu` does by hand. Callers
/// don't have to know which case they are in; the guarantee is only useful if
/// it is the default.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool isDestructive = false,
}) async {
  final dismissMenu = ContextMenuScope.of(context);
  final dialogContext = dismissMenu == null
      ? context
      : Navigator.of(context).context;
  dismissMenu?.call();

  final confirmed = await showCustomDialog<bool>(
    context: dialogContext,
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
        return AppModal(
          title: title,
          // The icon once, in the header badge; it used to be here and on
          // the confirm button both.
          titleIcon: IconTile(
            icon: icon,
            color: accent,
            size: 36,
            radius: K.radiusRow,
            iconSize: 18,
          ),
          // Wide enough that a two-word confirm ("Delete channel", "Sign
          // out") fits beside Cancel at the same width, rather than being
          // ellipsised down to something the button no longer explains.
          maxWidth: 400,
          content: Text(
            message,
            style: AppText.body.copyWith(color: themeState.textSecondary),
          ),
          actions: [
            AppButton(
              label: cancelLabel,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton(
              label: confirmLabel,
              variant: isDestructive
                  ? AppButtonVariant.danger
                  : AppButtonVariant.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }
}
