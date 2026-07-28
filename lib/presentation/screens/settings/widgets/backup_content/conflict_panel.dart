import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/message_banner.dart';

import 'section_title.dart';

class ConflictPanel extends StatelessWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const ConflictPanel({required this.themeState, required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = state.isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Backup Conflict', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          'Your account already has a cloud backup, but this device has its '
          'own vault. Choose which identity to keep — the other one is '
          'overwritten.',
          style: TextStyle(
            fontSize: 12,
            color: themeState.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: 'Keep This Device',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : cubit.keepLocalVault,
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Restore Cloud Backup',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing ? null : cubit.restoreCloudBackup,
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.error!, isError: true),
        ],
      ],
    );
  }
}
