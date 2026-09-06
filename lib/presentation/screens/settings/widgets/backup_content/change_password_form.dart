import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/button_footer.dart';
import '../../../../common/message_banner.dart';

/// The second half of a password change: the emailed code, where there is one,
/// and the new password.
///
/// Split from [ChangePasswordPanel] rather than living inside it because the
/// two halves ask completely different questions and share no fields — one
/// proves who you are, the other decides what happens next.
class ChangePasswordForm extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onCancel;

  const ChangePasswordForm({
    super.key,
    required this.state,
    required this.onCancel,
  });

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _needsCode =>
      widget.state.passwordChange == PasswordChangeStage.enterCode;

  void _submit() {
    final password = _password.text;

    if (_needsCode && _code.text.trim().isEmpty) {
      setState(() => _validationError = 'Enter the code from your email');
      return;
    }
    if (password.length < 8) {
      setState(
        () => _validationError = 'Password must be at least 8 characters',
      );
      return;
    }
    if (password != _confirm.text) {
      setState(() => _validationError = 'Passwords do not match');
      return;
    }
    setState(() => _validationError = null);

    context.read<SupabaseBackupCubit>().submitPasswordChange(
      newPassword: password,
      code: _needsCode ? _code.text.trim() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = state.isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.successMessage != null) ...[
          MessageBanner(
            message: state.successMessage!,
            kind: MessageBannerKind.success,
          ),
          const SizedBox(height: 14),
        ],

        if (_needsCode) ...[
          AppTextField(
            controller: _code,
            label: 'Code from email',
            hint: 'The code we just sent you',
            enabled: !busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 16),
        ],

        AppTextField(
          controller: _password,
          label: 'New password',
          hint: 'Choose a strong password',
          obscureText: true,
          enabled: !busy,
          autofocus: !_needsCode,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _confirm,
          label: 'Confirm new password',
          hint: 'Re-enter the new password',
          obscureText: true,
          enabled: !busy,
          onSubmitted: (_) => busy ? null : _submit(),
        ),

        if (_validationError != null || state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(
            message: _validationError ?? state.error!,
            kind: MessageBannerKind.error,
          ),
        ],

        const SizedBox(height: 12),
        // Said here as well as at signup, because this is the moment it stops
        // being hypothetical: the old blobs in the cloud are about to be
        // replaced, and anything still encrypted under the old password
        // becomes unreadable.
        const MessageBanner(
          message:
              'Backups made with the old password can no longer be restored '
              'once this goes through. Your recovery key keeps working — it '
              'wraps the same vault independently of the password.',
          kind: MessageBannerKind.caution,
        ),

        const SizedBox(height: 16),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: busy ? null : widget.onCancel,
            ),
            AppButton(
              label: 'Change password',
              isLoading: busy,
              onPressed: busy ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }
}
