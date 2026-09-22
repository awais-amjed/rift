import 'package:flutter/material.dart';

import '../../../../../logic/services/connection_failure.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../common/empty_state.dart';
import '../../../../theme/theme_context.dart';

/// Shown when a voice channel could not be joined.
///
/// Three registers, largest first: what went wrong, what it means and what to
/// do, then the original error text kept quiet at the bottom. The last line is
/// there so a bug report still carries the real cause — the sentence above it
/// is an interpretation, and interpretations are sometimes wrong.
///
/// A failed join used to be a dead end: the channel stayed selected and the
/// only way out was joining a different channel and coming back. The actions
/// are that escape hatch made explicit.
class ErrorView extends StatelessWidget {
  final ConnectionFailure failure;

  /// Wired only where [ConnectionFailure.canRetry] holds; the view itself does
  /// not decide, so the caller can also withhold it.
  final VoidCallback? onRetry;

  /// Lets the user out of the channel without having to enter another one.
  final VoidCallback? onLeave;

  const ErrorView({
    super.key,
    required this.failure,
    this.onRetry,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      color: themeState.bgSecondary,
      child: EmptyState(
        icon: Icons.cloud_off_rounded,
        title: failure.title,
        message: failure.message,
        detail: failure.detail,
        action: onRetry == null && onLeave == null
            ? null
            : ButtonFooter(
                alignment: MainAxisAlignment.center,
                buttons: [
                  if (onLeave != null)
                    AppButton(
                      label: 'Leave channel',
                      variant: AppButtonVariant.secondary,
                      onPressed: onLeave,
                    ),
                  if (onRetry != null)
                    AppButton(label: 'Try again', onPressed: onRetry),
                ],
              ),
      ),
    );
  }
}
