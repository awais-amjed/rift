import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/feature_header.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/resend_confirmation_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../onboarding_footer.dart';
import '../onboarding_page.dart';

/// Onboarding's "check your inbox" step, after an account is created and before
/// its address is confirmed.
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
    void back() {
      context.read<SupabaseBackupCubit>().clearMessage();
      onBack();
    }

    return OnboardingPage(
      onBack: back,
      footer: OnboardingFooter(
        onBack: back,
        // Short enough to survive the pair. ButtonFooter gives both buttons
        // the widest label's width and ellipsises when that will not fit, so
        // "I've confirmed — sign in" beside Back rendered as
        // "I've confirmed — sig…" — half of the only action on the step. The
        // subtitle above already says signing in is what comes next.
        primary: AppButton(label: 'I\'ve confirmed', onPressed: onSignIn),
        // Under the commit rather than beside Back: it belongs to the
        // confirming, not to going back.
        secondary: ResendConfirmationButton(
          availableAt: state.resendAvailableAt,
          isProcessing: state.isProcessing,
          asLink: true,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FeatureHeader(
            icon: Icons.mark_email_unread_rounded,
            title: 'Check your inbox',
            subtitle: 'Open the confirmation link we sent, then sign in.',
          ),
          if (state.email case final email?) ...[
            const SizedBox(height: 16),
            _Address(email),
          ],
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
        ],
      ),
    );
  }
}

/// Where the link went, on a line of its own: run into the sentence, a long
/// address broke it in two wherever it happened to wrap.
class _Address extends StatelessWidget {
  final String email;

  const _Address(this.email);

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusPill),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Text(
        email,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.secondaryStrong.copyWith(color: theme.textPrimary),
      ),
    );
  }
}
