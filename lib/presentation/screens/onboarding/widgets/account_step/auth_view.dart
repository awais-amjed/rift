import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/supabase_auth_form_state.dart';
import '../../../../theme/custom_colors.dart';
import '../onboarding_page.dart';
import '../password_strength_indicator.dart';
import '../../../../common/feature_header.dart';

class AuthView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;
  final bool initialSignUp;

  const AuthView({
    super.key,
    required this.state,
    required this.onBack,
    this.initialSignUp = true,
  });

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
    isSignUp = widget.initialSignUp;
    // Coming back from "check your inbox" — prefill the address they used.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FeatureHeader(
            icon: isSignUp
                ? Icons.person_add_rounded
                : Icons.cloud_sync_rounded,
            title: isSignUp ? 'Create Your Account' : 'Welcome Back',
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
                    isError: true,
                  ),
                ],

                if (isSignUp) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CustomColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: CustomColors.warning.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: CustomColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your password protects your encrypted backup. '
                            'Resetting it later means old backups can\'t be '
                            'restored — keep it safe.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: theme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                    style: TextStyle(fontSize: 12, color: theme.primary),
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
