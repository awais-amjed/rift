import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/resend_confirmation_button.dart';
import '../onboarding_page.dart';
import '../../../../common/feature_header.dart';

class EmailConfirmationView extends StatelessWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;
  final VoidCallback onSignIn;

  const EmailConfirmationView({
    super.key,
    required this.state,
    required this.onBack,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingPage(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FeatureHeader(
            icon: Icons.mark_email_unread_rounded,
            title: 'Check your inbox',
            subtitle:
                'We sent a confirmation link to ${state.email ?? 'your email'}. '
                'Confirm it, then sign in to continue.',
          ),
          if (state.successMessage != null) ...[
            const SizedBox(height: 24),
            MessageBanner(
              message: state.successMessage!,
              kind: MessageBannerKind.success,
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 24),
            MessageBanner(message: state.error!, kind: MessageBannerKind.error),
          ],
          const SizedBox(height: 32),
          AppButton(label: 'I\'ve confirmed — sign in', onPressed: onSignIn),
          // Between the two actions rather than below them: it belongs to the
          // confirming, not to going back.
          ResendConfirmationButton(
            availableAt: state.resendAvailableAt,
            isProcessing: state.isProcessing,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Back',
            variant: AppButtonVariant.secondary,
            onPressed: () {
              context.read<SupabaseBackupCubit>().clearMessage();
              onBack();
            },
          ),
        ],
      ),
    );
  }
}
