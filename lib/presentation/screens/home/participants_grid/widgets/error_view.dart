import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/services/connection_failure.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../../data/constants.dart';

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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 44,
                    color: themeState.textQuaternary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    failure.title,
                    textAlign: TextAlign.center,
                    style: AppText.sectionTitle.copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    failure.message,
                    textAlign: TextAlign.center,
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                  if (failure.detail != null) ...[
                    const SizedBox(height: 14),
                    _buildDetail(themeState),
                  ],
                  if (onRetry != null || onLeave != null) ...[
                    const SizedBox(height: 22),
                    _buildActions(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetail(ThemeState themeState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: themeState.bgPrimary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: themeState.borderPrimary),
      ),
      child: Text(
        failure.detail!,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: AppText.figure.copyWith(color: themeState.textTertiary),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
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
    );
  }
}
