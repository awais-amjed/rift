import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/supabase_auth_form_state.dart';
import '../onboarding_page.dart';
import '../password_strength_indicator.dart';
import '../../../../common/feature_header.dart';
import '../../../../theme/app_text.dart';

/// The account step's form: sign in, or create an account.
///
/// It opens on **sign in**. Onboarding is reached whenever there is no local
/// vault, and that is as often a reinstall or a second device as it is a
/// genuinely new account — for the first group, creating a second account is
/// the one thing they must not do, because the vault they are trying to reach
/// is behind the first one. Someone with no account has "New here? Create an
/// account" a line below and loses two seconds; someone who signs up twice
/// loses their servers.
class AuthView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const AuthView({super.key, required this.state, required this.onBack});

  @override
  State<AuthView> createState() => AuthViewState();
}

class AuthViewState extends State<AuthView>
    with SupabaseAuthFormState<AuthView> {
  final _confirmController = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    // `isSignUp` starts false in the shared mixin, and is left alone here: the
    // form opens on sign in, including on the way back from "check your inbox",
    // where the account already exists by definition.
    //
    // Coming back from there, prefill the address they used.
    emailController.text = widget.state.email ?? '';
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  /// Onboarding validates before handing over to the shared submit — it's the
  /// only surface where the account is being created from scratch.
  void _submit() {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _validationError = 'Enter a valid email address');
      return;
    }
    if (password.length < 8) {
      setState(
        () => _validationError = 'Password must be at least 8 characters',
      );
      return;
    }
    if (isSignUp && password != _confirmController.text) {
      setState(() => _validationError = 'Passwords do not match');
      return;
    }
    setState(() => _validationError = null);

    submitCredentials();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final isProcessing = widget.state.isProcessing;

    return OnboardingPage(
      step: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FeatureHeader(
            icon: isSignUp
                ? Icons.person_add_rounded
                : Icons.cloud_sync_rounded,
            title: isSignUp ? 'Create Your Account' : 'Sign In to Rift',
            subtitle: isSignUp
                ? 'One password for everything. It also protects your '
                      'encrypted backup and never leaves this device.'
                : 'Sign in and your encrypted vault is restored automatically.',
            themeState: theme,
          ),

          const SizedBox(height: 32),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  hint: isSignUp
                      ? 'Choose a strong password'
                      : 'Enter your password',
                  obscureText: true,
                  enabled: !isProcessing,
                  onChanged: isSignUp ? (_) => setState(() {}) : null,
                  onEditingComplete: (isSignUp || isProcessing)
                      ? null
                      : _submit,
                ),

                if (isSignUp) ...[
                  const SizedBox(height: 12),
                  PasswordStrengthIndicator(password: passwordController.text),
                  const SizedBox(height: 20),
                  AppTextField(
                    controller: _confirmController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    obscureText: true,
                    enabled: !isProcessing,
                    onEditingComplete: isProcessing ? null : _submit,
                    onChanged: (_) {
                      if (_validationError != null) {
                        setState(() => _validationError = null);
                      }
                    },
                  ),
                ],

                if (_validationError != null || widget.state.error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(
                    message: _validationError ?? widget.state.error!,
                    kind: MessageBannerKind.error,
                  ),
                ],

                if (isSignUp) ...[
                  const SizedBox(height: 16),
                  const MessageBanner(
                    message:
                        'Your password protects your encrypted backup. '
                        'Resetting it later means old backups can\'t be '
                        'restored — keep it safe.',
                    kind: MessageBannerKind.info,
                  ),
                ],

                const SizedBox(height: 24),

                Row(
                  children: [
                    AppButton(
                      label: 'Back',
                      variant: AppButtonVariant.secondary,
                      onPressed: isProcessing ? null : widget.onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: isSignUp ? 'Create Account' : 'Sign In',
                        expanded: true,
                        isLoading: isProcessing,
                        onPressed: isProcessing ? null : _submit,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Only on sign in. Offering "recover your account" to
                // somebody creating one is an invitation to reset an account
                // they do not have.
                if (!isSignUp)
                  TextButton(
                    onPressed: isProcessing
                        ? null
                        : () => context
                              .read<SupabaseBackupCubit>()
                              .startAccountRecovery(
                                email: emailController.text.trim(),
                              ),
                    child: Text(
                      'Forgotten your password?',
                      style: AppText.secondary.copyWith(
                        color: theme.textTertiary,
                      ),
                    ),
                  ),

                TextButton(
                  onPressed: isProcessing
                      ? null
                      : () => setState(() {
                          isSignUp = !isSignUp;
                          _validationError = null;
                        }),
                  child: Text(
                    isSignUp
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                    style: AppText.secondary.copyWith(color: theme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
