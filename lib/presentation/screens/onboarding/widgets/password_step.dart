import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/feature_header.dart';
import '../../../common/message_banner.dart';
import '../../../common/restore_file_dialog.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';
import 'onboarding_footer.dart';
import 'onboarding_page.dart';
import 'password_strength_indicator.dart';

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
  String? _validationError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;

    if (password.length < 8) {
      setState(
        () => _validationError = 'Password must be at least 8 characters',
      );
      return;
    }

    setState(() => _validationError = null);
    context.read<VaultCubit>().createVault(password);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return BlocBuilder<VaultCubit, VaultState>(
      buildWhen: (prev, curr) =>
          prev.isProcessing != curr.isProcessing || prev.error != curr.error,
      builder: (context, vaultState) {
        final isProcessing = vaultState.isProcessing;

        return OnboardingPage(
          step: 1,
          stepLabel: 'vault',
          // Green on a phone, as the badge is: this step claims safety rather
          // than counting.
          progressColor: CustomColors.success,
          onBack: isProcessing ? null : widget.onBack,
          footer: OnboardingFooter(
            onBack: widget.onBack,
            backEnabled: !isProcessing,
            primary: AppButton(
              label: 'Create vault',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : _submit,
            ),
            secondary: TextButton(
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
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              // Green rather than accent: this step's badge is making a claim
              // about safety, not numbering a step.
              const FeatureHeader(
                icon: Icons.shield_outlined,
                title: 'Create a local vault',
                subtitle:
                    'Choose a password to encrypt your identity. Everything '
                    'stays on this device — no email, no central server.',

                badgeColor: CustomColors.success,
              ),

              const SizedBox(height: 32),

              // Form
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // One field, not two. Retyping a password you can't see
                    // guards against a typo by asking for it twice; the eye
                    // lets you read it instead, and the caution below says
                    // why it matters.
                    AppTextField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Choose a strong password',
                      obscureText: true,
                      enabled: !isProcessing,
                      autofocus: true,
                      onEditingComplete: _submit,
                      onChanged: (_) => setState(() {
                        _validationError = null;
                      }),
                    ),

                    const SizedBox(height: 12),

                    PasswordStrengthIndicator(
                      password: _passwordController.text,
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

                    // Processing hint
                    if (isProcessing) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Setting up your account…',
                        textAlign: TextAlign.center,
                        style: AppText.secondary.copyWith(
                          color: theme.textQuaternary,
                        ),
                      ),
                    ],
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
