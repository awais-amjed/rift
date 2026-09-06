import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/button_footer.dart';
import '../../../../../common/feature_header.dart';
import '../../../../../common/handle_field.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../common/resend_confirmation_button.dart';
import '../../../../../common/segmented_control.dart';
import '../../../../../common/supabase_auth_form_state.dart';

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
      return _EmailConfirmationView(state: widget.state);
    }

    final isProcessing = widget.state.isProcessing;

    return Column(
      children: [
        SegmentedControl<bool>(
          value: isSignUp,
          onChanged: isProcessing
              ? null
              : (signUp) => setState(() => isSignUp = signUp),
          options: const [
            SegmentOption(value: false, label: 'Sign in'),
            SegmentOption(value: true, label: 'Create account'),
          ],
        ),

        const SizedBox(height: 24),

        FeatureHeader(
          icon: Icons.cloud_upload_rounded,
          title: isSignUp
              ? 'Create a backup account'
              : 'Sign in to cloud backup',
          subtitle: isSignUp
              ? 'Your encrypted backup is stored on our central server. '
                    'Only you can decrypt it.'
              : 'Sign in to upload or restore your encrypted backup.',

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
          onEditingComplete: (isProcessing || isSignUp)
              ? null
              : submitCredentials,
        ),

        if (isSignUp) ...[
          const SizedBox(height: 16),
          HandleField(
            controller: handleController,
            enabled: !isProcessing,
            onEditingComplete: isProcessing ? null : submitCredentials,
          ),
        ],

        if (widget.state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(
            message: widget.state.error!,
            kind: MessageBannerKind.error,
          ),
        ],

        const SizedBox(height: 24),

        ButtonFooter(
          buttons: [
            AppButton(
              label: isSignUp ? 'Create account' : 'Sign in',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : submitCredentials,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Email confirmation pending ────────────────────────────────────────────────

class _EmailConfirmationView extends StatelessWidget {
  final SupabaseBackupState state;

  const _EmailConfirmationView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final email = state.email;

    return Column(
      children: [
        FeatureHeader(
          icon: Icons.mark_email_unread_rounded,
          title: 'Check your email',
          subtitle: email != null
              ? 'A confirmation link was sent to $email.\n'
                    'Click the link then sign in below.'
              : 'A confirmation link was sent to your email.\n'
                    'Click the link then sign in below.',

          subtitleMaxWidth: double.infinity,
        ),

        if (state.successMessage != null) ...[
          const SizedBox(height: 20),
          MessageBanner(
            message: state.successMessage!,
            kind: MessageBannerKind.success,
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 20),
          MessageBanner(message: state.error!, kind: MessageBannerKind.error),
        ],

        const SizedBox(height: 32),

        // Sign in is what almost everybody is here to do; Resend is the
        // fallback for the one whose first email never arrived.
        ButtonFooter(
          buttons: [
            ResendConfirmationButton(
              availableAt: state.resendAvailableAt,
              isProcessing: state.isProcessing,
            ),
            AppButton(label: 'Sign in', onPressed: () => cubit.clearMessage()),
          ],
        ),
      ],
    );
  }
}
