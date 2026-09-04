import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';

import '../section_title.dart';
import '../../../../theme/app_text.dart';
import 'change_password_form.dart';

/// Changing the password that guards the vault, and the account if there is
/// one.
///
/// Two steps, because the second one is worth stopping for: proving the
/// current password is cheap and local, but on an account the change also
/// needs a code from the address on file. That extra step is the difference
/// between "someone walked past an unlocked laptop" and "someone has the
/// password *and* the inbox".
class ChangePasswordPanel extends StatefulWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const ChangePasswordPanel({
    super.key,
    required this.themeState,
    required this.state,
  });

  @override
  State<ChangePasswordPanel> createState() => _ChangePasswordPanelState();
}

class _ChangePasswordPanelState extends State<ChangePasswordPanel> {
  final _current = TextEditingController();
  bool _open = false;

  @override
  void dispose() {
    _current.dispose();
    super.dispose();
  }

  void _close() {
    _current.clear();
    context.read<SupabaseBackupCubit>().cancelPasswordChange();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;
    final state = widget.state;
    final cubit = context.read<SupabaseBackupCubit>();
    final started = state.passwordChange != PasswordChangeStage.idle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Password', themeState: theme),
        const SizedBox(height: 4),
        Text(
          state.isSignedIn
              ? 'One password signs you in and unlocks your encrypted backup. '
                    'Changing it needs a code emailed to ${state.email}.'
              : 'The password that unlocks your vault on this device.',
          style: AppText.secondary.copyWith(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),

        if (!_open && !started) ...[
          const SizedBox(height: 14),
          AppButton(
            label: 'Change password',
            variant: AppButtonVariant.secondary,
            onPressed: () => setState(() => _open = true),
          ),
        ],

        if (_open && !started) ...[
          const SizedBox(height: 16),
          AppTextField(
            controller: _current,
            label: 'Current password',
            hint: 'Enter your current password',
            obscureText: true,
            enabled: !state.isProcessing,
            onSubmitted: (_) => _submitCurrent(cubit),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            MessageBanner(message: state.error!, kind: MessageBannerKind.error),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                onPressed: state.isProcessing ? null : _close,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Continue',
                isLoading: state.isProcessing,
                onPressed: state.isProcessing
                    ? null
                    : () => _submitCurrent(cubit),
              ),
            ],
          ),
        ],

        if (started) ...[
          const SizedBox(height: 16),
          ChangePasswordForm(
            themeState: theme,
            state: state,
            onCancel: _close,
          ),
        ],
      ],
    );
  }

  void _submitCurrent(SupabaseBackupCubit cubit) {
    if (_current.text.isEmpty) return;
    cubit.beginPasswordChange(currentPassword: _current.text);
  }
}
