import 'package:flutter/material.dart';

import '../../../../../logic/ptt/desktop_shortcut_settings.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// What the push-to-talk section shows where the desktop has the say over
/// the key: while Rift is waiting to hear it, or once it is known.
///
/// Waiting replaces the key controls rather than sitting beside them. The
/// desktop answers with the key it keeps, so a key picked in the meantime
/// would be quietly swapped out — better not to offer the choice at all.
/// A mouse button is the exception: the desktop never sees one, so switching
/// to a button stays Rift's to offer ([onUseMouse]).
class DesktopKeyNotice extends StatelessWidget {
  /// True while the desktop has not answered yet.
  final bool pending;

  /// Starts or stops listening for a mouse button to use instead.
  final VoidCallback onUseMouse;

  /// Whether that listening is on.
  final bool capturingMouse;

  const DesktopKeyNotice({
    super.key,
    required this.pending,
    required this.onUseMouse,
    required this.capturingMouse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final canOpen = DesktopShortcutSettings.canOpen;
    final String message;
    if (pending) {
      message =
          'Checking your push-to-talk key with your computer. If it asks, '
          'choose to allow it.';
    } else if (canOpen) {
      message =
          'This key works even while you are in other apps. To use a '
          'different key, click Change key.';
    } else {
      message =
          'This key works even while you are in other apps. To use a '
          "different key, open your computer's settings and look for "
          "Rift's keyboard shortcuts.";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
        const SizedBox(height: 10),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            if (pending || canOpen)
              AppButton(
                label: 'Change key',
                isLoading: pending,
                onPressed: pending ? null : DesktopShortcutSettings.open,
                variant: AppButtonVariant.secondary,
              ),
            if (!pending)
              AppButton(
                label: capturingMouse ? 'Cancel' : 'Use a mouse button',
                onPressed: onUseMouse,
                variant: AppButtonVariant.secondary,
              ),
          ],
        ),
      ],
    );
  }
}
