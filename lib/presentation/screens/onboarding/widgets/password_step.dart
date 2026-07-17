import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../theme/custom_colors.dart';
import 'onboarding_page.dart';
import 'password_strength_indicator.dart';
import '../../../common/restore_file_dialog.dart';

/// Privacy-mode onboarding step — create a local-only vault.
///
/// No central-server contact: the identity lives (and stays) on this device.
/// A backup file exported later is the only recovery path.
class PasswordStep extends StatefulWidget {
  final VoidCallback onBack;

  const PasswordStep({super.key, required this.onBack});

  @override
  State<PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<PasswordStep> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(
        () => _validationError = 'Password must be at least 8 characters',
      );
      return;
    }
    if (password != confirm) {
      setState(() => _validationError = 'Passwords do not match');
      return;
    }

    setState(() => _validationError = null);
    context.read<VaultCubit>().createVault(password);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return BlocBuilder<VaultCubit, VaultState>(
      buildWhen: (prev, curr) =>
          prev.isProcessing != curr.isProcessing || prev.error != curr.error,
      builder: (context, vaultState) {
        final isProcessing = vaultState.isProcessing;

        return OnboardingPage(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.person_add_rounded,
                  size: 32,
                  color: theme.primary,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Create a Local Vault',
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
                  'Choose a password to encrypt your identity. Everything '
                  'stays on this device — no email, no central server.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: theme.textTertiary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Form
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Choose a strong password',
                      obscureText: true,
                      enabled: !isProcessing,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 12),

                    // Strength indicator
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
                      onEditingComplete: _submit,
                      onChanged: (_) {
                        if (_validationError != null) {
                          setState(() => _validationError = null);
                        }
                      },
                    ),

                    // Validation / API error
                    if (_validationError != null ||
                        vaultState.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _validationError ?? vaultState.error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CustomColors.error,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Remember-password warning
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
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: CustomColors.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Make sure you remember this password. '
                              'It cannot be reset or recovered.',
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

                    const SizedBox(height: 24),

                    // Processing hint
                    if (isProcessing) ...[
                      Text(
                        'Setting up your account…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textQuaternary,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Actions
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
                            label: 'Create Vault',
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
                          : () => showCustomDialog(
                                context: context,
                                builder: (_) => BlocProvider.value(
                                  value: context.read<VaultCubit>(),
                                  child: const RestoreFileDialog(),
                                ),
                              ),
                      child: Text(
                        'Have a backup file? Restore it instead',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
