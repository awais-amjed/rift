import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../common/supabase_auth_form_state.dart';
import '../../../../../common/feature_header.dart';

/// Sign-up / sign-in form shown when the user is not yet authenticated.
///
/// Handles three sub-states:
///   1. Normal auth form (sign-in or sign-up)
///   2. Email confirmation pending — show "check your inbox" notice
class AuthView extends StatefulWidget {
  final SupabaseBackupState state;

  const AuthView({super.key, required this.state});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView>
    with SupabaseAuthFormState<AuthView> {
  @override
  Widget build(BuildContext context) {
    // Show confirmation-pending screen when server requires email verification.
    if (widget.state.needsEmailConfirmation) {
      return _EmailConfirmationView(email: widget.state.email);
    }

    final theme = context.read<ThemeCubit>().state;
    final isProcessing = widget.state.isProcessing;

    return Column(
      children: [
        FeatureHeader(
          icon: Icons.cloud_upload_rounded,
          title: isSignUp ? 'Create Backup Account' : 'Sign In to Cloud Backup',
          subtitle: isSignUp
              ? 'Your encrypted backup is stored on our central server. '
                    'Only you can decrypt it.'
              : 'Sign in to upload or restore your encrypted backup.',
          themeState: theme,
          titleSize: 20,
          subtitleMaxWidth: double.infinity,
        ),

        const SizedBox(height: 32),

        AppTextField(
          controller: emailController,
          label: 'Email',
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          enabled: !isProcessing,
          autofocus: true,
        ),

        const SizedBox(height: 16),

        AppTextField(
          controller: passwordController,
          label: 'Password',
          hint: 'Enter your password',
          obscureText: true,
          enabled: !isProcessing,
          onEditingComplete: isProcessing ? null : submitCredentials,
        ),

        if (widget.state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(message: widget.state.error!, isError: true),
        ],

        const SizedBox(height: 24),

        AppButton(
          label: isSignUp ? 'Create Account' : 'Sign In',
          expanded: true,
          isLoading: isProcessing,
          onPressed: isProcessing ? null : submitCredentials,
        ),

        const SizedBox(height: 16),

        TextButton(
          onPressed: isProcessing ? null : toggleAuthMode,
          child: Text(
            isSignUp
                ? 'Already have an account? Sign in'
                : "Don't have an account? Sign up",
            style: TextStyle(fontSize: 13, color: theme.primary),
          ),
        ),
      ],
    );
  }
}

// ── Email confirmation pending ────────────────────────────────────────────────

class _EmailConfirmationView extends StatelessWidget {
  final String? email;

  const _EmailConfirmationView({this.email});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final cubit = context.read<SupabaseBackupCubit>();

    return Column(
      children: [
        FeatureHeader(
          icon: Icons.mark_email_unread_rounded,
          title: 'Check Your Email',
          subtitle: email != null
              ? 'A confirmation link was sent to $email.\n'
                    'Click the link then sign in below.'
              : 'A confirmation link was sent to your email.\n'
                    'Click the link then sign in below.',
          themeState: theme,
          titleSize: 20,
          subtitleMaxWidth: double.infinity,
        ),

        const SizedBox(height: 32),

        AppButton(
          label: 'Sign In After Confirming',
          expanded: true,
          onPressed: () => cubit.clearMessage(),
        ),
      ],
    );
  }
}
