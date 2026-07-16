import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
import '../../../theme/custom_colors.dart';
import 'password_strength_indicator.dart';

/// Default onboarding step — sign in to or create a Rift account.
///
/// The vault is handled automatically after auth (see
/// [SupabaseBackupCubit]): an existing cloud backup is restored, or a fresh
/// vault is created and uploaded. The router leaves onboarding as soon as
/// the vault unlocks. Only a privacy-mode backup (manually chosen vault
/// password) requires the extra unlock prompt rendered here.
class AccountStep extends StatelessWidget {
  final VoidCallback onBack;

  const AccountStep({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        if (state.needsVaultPassword) {
          return _VaultPasswordView(state: state, onBack: onBack);
        }
        if (state.needsEmailConfirmation) {
          return _EmailConfirmationView(state: state, onBack: onBack);
        }
        return _AuthView(state: state, onBack: onBack);
      },
    );
  }
}

// ── Sign in / sign up ───────────────────────────────────────────────────────

class _AuthView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const _AuthView({required this.state, required this.onBack});

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSignUp = true;
  String? _validationError;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CustomColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _isSignUp
                    ? Icons.person_add_rounded
                    : Icons.cloud_sync_rounded,
                size: 32,
                color: CustomColors.primary,
              ),
            ),

            const SizedBox(height: 24),

            Text(
              _isSignUp ? 'Create Your Account' : 'Welcome Back',
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
                _isSignUp
                    ? 'One password for everything. It also protects your '
                        'encrypted backup and never leaves this device.'
                    : 'Sign in and your encrypted vault is restored '
                        'automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.textTertiary,
                ),
              ),
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
                    onEditingComplete:
                        (_isSignUp || isProcessing) ? null : _submit,
                  ),

                  if (_isSignUp) ...[
                    const SizedBox(height: 12),
                    PasswordStrengthIndicator(
                      password: _passwordController.text,
                    ),
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

                  if (_validationError != null ||
                      widget.state.error != null) ...[
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: CustomColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Email confirmation ──────────────────────────────────────────────────────

class _EmailConfirmationView extends StatelessWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const _EmailConfirmationView({required this.state, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CustomColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.mark_email_unread_rounded,
              size: 32,
              color: CustomColors.primary,
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
            onPressed: () =>
                context.read<SupabaseBackupCubit>().clearMessage(),
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

// ── Privacy-mode backup unlock ──────────────────────────────────────────────

class _VaultPasswordView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const _VaultPasswordView({required this.state, required this.onBack});

  @override
  State<_VaultPasswordView> createState() => _VaultPasswordViewState();
}

class _VaultPasswordViewState extends State<_VaultPasswordView> {
  final _vaultPasswordController = TextEditingController();

  @override
  void dispose() {
    _vaultPasswordController.dispose();
    super.dispose();
  }

  void _unlock() {
    context
        .read<SupabaseBackupCubit>()
        .submitVaultPassword(_vaultPasswordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final isProcessing = widget.state.isProcessing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CustomColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              size: 32,
              color: CustomColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Unlock Your Backup',
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
              'We found your backup, but it\'s protected by a separately '
              'chosen vault password (privacy mode). Enter it once — '
              'future restores will be automatic.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _vaultPasswordController,
                  label: 'Vault Password',
                  hint: 'Enter your vault password',
                  obscureText: true,
                  enabled: !isProcessing,
                  autofocus: true,
                  onEditingComplete: isProcessing ? null : _unlock,
                ),
                if (widget.state.error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(message: widget.state.error!, isError: true),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    AppButton(
                      label: 'Back',
                      variant: AppButtonVariant.secondary,
                      onPressed: isProcessing
                          ? null
                          : () {
                              final cubit =
                                  context.read<SupabaseBackupCubit>();
                              cubit.dismissPending();
                              cubit.signOut();
                              widget.onBack();
                            },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Unlock',
                        expanded: true,
                        isLoading: isProcessing,
                        onPressed: isProcessing ? null : _unlock,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
