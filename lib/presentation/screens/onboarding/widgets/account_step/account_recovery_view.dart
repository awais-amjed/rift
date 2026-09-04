import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/feature_header.dart';
import '../../../../common/message_banner.dart';
import '../onboarding_page.dart';

/// Getting back in without the password.
///
/// Asks for three things at once — the emailed code, the recovery key, and a
/// new password — because they are one decision, not three. Splitting them
/// across pages would mean somebody discovering on the last screen that the
/// key they cannot find is the one thing this needed.
///
/// The code proves the address and recovers the *account*. The recovery key
/// opens the *vault*, and nothing else can: the backup is wrapped under the
/// password nobody remembers, and no reset on any server unwraps it.
class AccountRecoveryView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const AccountRecoveryView({
    super.key,
    required this.state,
    required this.onBack,
  });

  @override
  State<AccountRecoveryView> createState() => _AccountRecoveryViewState();
}

class _AccountRecoveryViewState extends State<AccountRecoveryView> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _recoveryKey = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _email.text = widget.state.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _recoveryKey.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _awaitingCode =>
      widget.state.accountRecovery == AccountRecoveryStage.enterCode;

  void _finish() {
    if (_code.text.trim().isEmpty) {
      setState(() => _validationError = 'Enter the code from your email');
      return;
    }
    if (_recoveryKey.text.trim().isEmpty) {
      setState(() => _validationError = 'Enter your recovery key');
      return;
    }
    if (_password.text.length < 8) {
      setState(
        () => _validationError = 'Password must be at least 8 characters',
      );
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _validationError = 'Passwords do not match');
      return;
    }
    setState(() => _validationError = null);

    context.read<SupabaseBackupCubit>().completeAccountRecovery(
      code: _code.text.trim(),
      recoveryKey: _recoveryKey.text.trim(),
      newPassword: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final state = widget.state;
    final busy = state.isProcessing;

    return OnboardingPage(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FeatureHeader(
            icon: Icons.lock_reset_rounded,
            title: 'Recover your account',
            subtitle: _awaitingCode
                ? 'Enter the code we emailed, your recovery key, and a new '
                      'password.'
                : 'We will email you a code. You will also need the recovery '
                      'key you saved when you created your account.',
            themeState: theme,
          ),

          const SizedBox(height: 28),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  enabled: !busy && !_awaitingCode,
                  autofocus: !_awaitingCode,
                ),

                if (_awaitingCode) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _code,
                    label: 'Code from email',
                    hint: 'The code we just sent',
                    enabled: !busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _recoveryKey,
                    label: 'Recovery key',
                    hint: 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX',
                    enabled: !busy,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _password,
                    label: 'New password',
                    hint: 'Choose a strong password',
                    obscureText: true,
                    enabled: !busy,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _confirm,
                    label: 'Confirm password',
                    hint: 'Re-enter the new password',
                    obscureText: true,
                    enabled: !busy,
                    onSubmitted: (_) => busy ? null : _finish(),
                  ),
                ],

                if (state.successMessage != null) ...[
                  const SizedBox(height: 14),
                  MessageBanner(
                    message: state.successMessage!,
                    kind: MessageBannerKind.success,
                  ),
                ],
                if (_validationError != null || state.error != null) ...[
                  const SizedBox(height: 14),
                  MessageBanner(
                    message: _validationError ?? state.error!,
                    kind: MessageBannerKind.error,
                  ),
                ],

                const SizedBox(height: 16),
                const MessageBanner(
                  message:
                      'Without the recovery key your messages and servers '
                      'cannot be restored. They are encrypted with a key only '
                      'you hold — resetting the password alone does not open '
                      'them.',
                  kind: MessageBannerKind.info,
                ),

                const SizedBox(height: 22),
                Row(
                  children: [
                    AppButton(
                      label: 'Back',
                      variant: AppButtonVariant.secondary,
                      onPressed: busy ? null : widget.onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: _awaitingCode ? 'Recover account' : 'Send code',
                        expanded: true,
                        isLoading: busy,
                        onPressed: busy
                            ? null
                            : () => _awaitingCode
                                  ? _finish()
                                  : context
                                        .read<SupabaseBackupCubit>()
                                        .beginAccountRecovery(
                                          email: _email.text,
                                        ),
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
