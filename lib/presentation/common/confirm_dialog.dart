import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/custom_colors.dart';
import '../theme/theme_context.dart';
import 'app_button.dart';
import 'app_modal.dart';
import 'checkbox_row.dart';
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
  final answer = await _show(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    icon: icon,
    isDestructive: isDestructive,
  );
  return answer.confirmed;
}

/// [showConfirmDialog] with a "Don't ask again" box under the message.
///
/// [dontAskAgain] is only ever true alongside [confirmed]: ticking the box and
/// then cancelling is not a choice to stop being asked, and treating it as one
/// would turn off the question for the very action that was just declined.
Future<({bool confirmed, bool dontAskAgain})> showConfirmDialogWithOptOut({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  String optOutLabel = "Don't ask again",
  IconData icon = Icons.help_outline_rounded,
}) {
  return _show(
    context: context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    icon: icon,
    isDestructive: false,
    optOutLabel: optOutLabel,
  );
}

Future<({bool confirmed, bool dontAskAgain})> _show({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  required IconData icon,
  required bool isDestructive,
  String? optOutLabel,
}) async {
  final dismissMenu = ContextMenuScope.of(context);
  final dialogContext = dismissMenu == null
      ? context
      : Navigator.of(context).context;
  dismissMenu?.call();

  final answer = await showCustomDialog<({bool confirmed, bool dontAskAgain})>(
    context: dialogContext,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      isDestructive: isDestructive,
      optOutLabel: optOutLabel,
    ),
  );
  return answer ?? (confirmed: false, dontAskAgain: false);
}

/// The body of [showConfirmDialog]. Private — the function is the API, so no
/// call site can forget the "dismiss means no" default.
class _ConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool isDestructive;

  /// The "Don't ask again" box's label, or null for no box.
  final String? optOutLabel;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    required this.isDestructive,
    this.optOutLabel,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final accent = widget.isDestructive
        ? CustomColors.error
        : themeState.primary;
    final optOutLabel = widget.optOutLabel;
    final text = Text(
      widget.message,
      style: AppText.body.copyWith(color: themeState.textSecondary),
    );
    return AppModal(
      staysDialogOnPhone: true,
      title: widget.title,
      // The icon once, in the header badge; it used to be here and on
      // the confirm button both.
      titleIcon: IconTile.title(icon: widget.icon, color: accent),
      // Wide enough that a two-word confirm ("Delete channel", "Sign
      // out") fits beside Cancel at the same width, rather than being
      // ellipsised down to something the button no longer explains.
      maxWidth: 400,
      content: optOutLabel == null
          ? text
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(height: 12),
                CheckboxRow(
                  label: optOutLabel,
                  value: _dontAskAgain,
                  onChanged: (v) => setState(() => _dontAskAgain = v),
                ),
              ],
            ),
      actions: [
        AppButton(
          label: widget.cancelLabel,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(
            context,
          ).pop((confirmed: false, dontAskAgain: false)),
        ),
        AppButton(
          label: widget.confirmLabel,
          variant: widget.isDestructive
              ? AppButtonVariant.danger
              : AppButtonVariant.primary,
          onPressed: () => Navigator.of(
            context,
          ).pop((confirmed: true, dontAskAgain: _dontAskAgain)),
        ),
      ],
    );
  }
}
