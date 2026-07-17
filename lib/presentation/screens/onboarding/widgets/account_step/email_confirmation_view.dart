import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../onboarding_page.dart';

class EmailConfirmationView extends StatelessWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;
  final VoidCallback onSignIn;

  const EmailConfirmationView({
    required this.state,
    required this.onBack,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return OnboardingPage(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.mark_email_unread_rounded,
              size: 32,
              color: theme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Check Your Inbox',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              'We sent a confirmation link to ${state.email ?? 'your email'}. '
              'Confirm it, then sign in to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 32),
          AppButton(
            label: 'I\'ve confirmed — sign in',
            onPressed: onSignIn,
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

