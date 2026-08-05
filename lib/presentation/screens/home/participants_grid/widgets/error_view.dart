import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/app_text.dart';

/// Error view shown when connection fails.
///
/// A failed join used to be a dead end — the channel stayed selected and the
/// only way out was to join a different channel and come back. The two actions
/// below are that escape hatch made explicit.
class ErrorView extends StatelessWidget {
  final String error;

  /// Offered only where a fresh attempt could plausibly succeed. The screen's
  /// own precondition failures — no account, no LiveKit URL — pass nothing,
  /// since retrying those would just reprint the same sentence.
  final VoidCallback? onRetry;

  /// Lets the user out of the channel without having to enter another one.
  final VoidCallback? onLeave;

  const ErrorView({super.key, required this.error, this.onRetry, this.onLeave});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: AppText.dialogTitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    error,
                    style: AppText.rowQuiet.copyWith(
                      fontSize: 14,
                      color: CustomColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (onRetry != null || onLeave != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      if (onLeave != null)
                        AppButton(
                          label: 'Leave channel',
                          variant: AppButtonVariant.secondary,
                          onPressed: onLeave,
                        ),
                      if (onRetry != null)
                        AppButton(
                          label: 'Try again',
                          icon: const Icon(
                            Icons.refresh_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          onPressed: onRetry,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
