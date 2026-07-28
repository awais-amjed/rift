import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../onboarding_page.dart';
import '../../../../common/feature_header.dart';

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
          FeatureHeader(
            icon: Icons.mark_email_unread_rounded,
            title: 'Check Your Inbox',
            subtitle:
                'We sent a confirmation link to ${state.email ?? 'your email'}. '
                'Confirm it, then sign in to continue.',
            themeState: theme,
          ),
          const SizedBox(height: 32),
          AppButton(label: 'I\'ve confirmed — sign in', onPressed: onSignIn),
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
