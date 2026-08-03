import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';

import '../section_title.dart';

class VaultPasswordPanel extends StatefulWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const VaultPasswordPanel({
    super.key,
    required this.themeState,
    required this.state,
  });

  @override
  State<VaultPasswordPanel> createState() => VaultPasswordPanelState();
}

class VaultPasswordPanelState extends State<VaultPasswordPanel> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = widget.state.isProcessing;
    final theme = widget.themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Unlock Cloud Backup', themeState: theme),
        const SizedBox(height: 4),
        Text(
          'This backup is protected by a separately chosen vault password '
          '(privacy mode). Enter it once — it will be re-encrypted under '
          'your account password afterwards.',
          style: TextStyle(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _passwordController,
          label: 'Vault Password',
          hint: 'Enter your vault password',
          obscureText: true,
          enabled: !isProcessing,
          onEditingComplete: isProcessing
              ? null
              : () => cubit.submitVaultPassword(_passwordController.text),
        ),
        if (widget.state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(message: widget.state.error!, isError: true),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: 'Unlock',
              isLoading: isProcessing,
              onPressed: isProcessing
                  ? null
                  : () => cubit.submitVaultPassword(_passwordController.text),
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing ? null : cubit.dismissPending,
            ),
          ],
        ),
      ],
    );
  }
}
