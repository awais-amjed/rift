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
import '../../../common/feature_header.dart';
import '../../../common/message_banner.dart';
import '../../../theme/app_text.dart';
import '../../../common/button_footer.dart';

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
          step: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              // Green rather than accent: this step's badge is making a claim
              // about safety, not numbering a step.
              FeatureHeader(
                icon: Icons.shield_outlined,
                title: 'Create a local vault',
                subtitle:
                    'Choose a password to encrypt your identity. Everything '
                    'stays on this device — no email, no central server.',
                themeState: theme,
                badgeColor: CustomColors.success,
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
                      MessageBanner(
                        message: _validationError ?? vaultState.error!,
                        kind: MessageBannerKind.error,
                      ),
                    ],

                    const SizedBox(height: 16),

                    const MessageBanner(
                      message:
                          'Make sure you remember this password. '
                          'It cannot be reset or recovered.',
                      kind: MessageBannerKind.caution,
                    ),

                    const SizedBox(height: 24),

                    // Processing hint
                    if (isProcessing) ...[
                      Text(
                        'Setting up your account…',
                        textAlign: TextAlign.center,
                        style: AppText.secondary.copyWith(
                          color: theme.textQuaternary,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Actions
                    ButtonFooter(
                      buttons: [
                        AppButton(
                          label: 'Back',
                          variant: AppButtonVariant.secondary,
                          onPressed: isProcessing ? null : widget.onBack,
                        ),
                        AppButton(
                          label: 'Create vault',
                          isLoading: isProcessing,
                          onPressed: isProcessing ? null : _submit,
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
                        style: AppText.secondary.copyWith(color: theme.primary),
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
