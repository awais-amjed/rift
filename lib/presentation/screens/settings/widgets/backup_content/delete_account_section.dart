import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/quiet_danger_button.dart';
import '../../../../common/show_custom_dialog.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import 'delete_account_dialog.dart';

/// The account's own end, below what can be done to this device.
///
/// Apart from [ThisDeviceSection] on purpose: signing out wipes this device
/// and keeps the account, and this is the opposite, so the two must never
/// read as one action in two strengths.
class DeleteAccountSection extends StatelessWidget {
  final String email;

  const DeleteAccountSection({super.key, required this.email});

  void _open(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    showCustomDialog<void>(
      context: context,
      build: (_) => DeleteAccountDialog(
        email: email,
        onDelete: (password) => cubit.deleteAccount(password: password),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Rift account'),
        const SizedBox(height: 14),
        Text(
          'Delete account',
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
        const SizedBox(height: 3),
        Text(
          'Deletes your account, cloud backup and Rift DMs for good. Your '
          'servers stay.',
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
        const SizedBox(height: 12),
        IntrinsicWidth(
          child: QuietDangerButton(
            icon: Icons.person_remove_outlined,
            label: 'Delete account',
            onTap: () => _open(context),
          ),
        ),
      ],
    );
  }
}
