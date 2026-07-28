import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/custom_colors.dart';
import '../onboarding_page.dart';
import '../password_strength_indicator.dart';
import '../../../../common/feature_header.dart';

class AuthView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;
  final bool initialSignUp;

  const AuthView({
    required this.state,
    required this.onBack,
    this.initialSignUp = true,
  });

  @override
  State<AuthView> createState() => AuthViewState();
}

class AuthViewState extends State<AuthView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  late bool _isSignUp = widget.initialSignUp;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    // Coming back from "check your inbox" — prefill the address they used.
    _emailController.text = widget.state.email ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

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
    if (_isSignUp && password != _confirmController.text) {
      setState(() => _validationError = 'Passwords do not match');
      return;
    }
    setState(() => _validationError = null);

    final cubit = context.read<SupabaseBackupCubit>();
    if (_isSignUp) {
      cubit.signUp(email: email, password: password);
    } else {
      cubit.signIn(email: email, password: password);
    }
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
            icon: _isSignUp
                ? Icons.person_add_rounded
                : Icons.cloud_sync_rounded,
            title: _isSignUp ? 'Create Your Account' : 'Welcome Back',
            subtitle: _isSignUp
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
                  controller: _emailController,
                  label: 'Email',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  enabled: !isProcessing,
                  autofocus: true,
                ),

                const SizedBox(height: 16),

                AppTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: _isSignUp
                      ? 'Choose a strong password'
                      : 'Enter your password',
                  obscureText: true,
                  enabled: !isProcessing,
                  onChanged: _isSignUp ? (_) => setState(() {}) : null,
                  onEditingComplete: (_isSignUp || isProcessing)
                      ? null
                      : _submit,
                ),

                if (_isSignUp) ...[
                  const SizedBox(height: 12),
                  PasswordStrengthIndicator(password: _passwordController.text),
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

                if (_isSignUp) ...[
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
                        label: _isSignUp ? 'Create Account' : 'Sign In',
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
                          _isSignUp = !_isSignUp;
                          _validationError = null;
                        }),
                  child: Text(
                    _isSignUp
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
