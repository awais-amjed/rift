import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/custom_colors.dart';

import '../section_title.dart';
import '../../../../theme/app_text.dart';

class SignedInPanel extends StatelessWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const SignedInPanel({
    super.key,
    required this.themeState,
    required this.state,
  });

  /// Signs out of the account AND removes the vault + server list from this
  /// device, returning to onboarding. The cloud backup is untouched, so
  /// signing back in restores everything.
  Future<void> _signOutOfDevice(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Sign out of this device?',
      message:
          'Your encrypted cloud backup stays safe. The vault and server list '
          'on this device will be removed — sign back in to restore them '
          'automatically.',
      confirmLabel: 'Sign Out',
      icon: Icons.logout_rounded,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final backupCubit = context.read<SupabaseBackupCubit>();
    final serverCubit = context.read<ServerCubit>();
    final vaultCubit = context.read<VaultCubit>();
    final navigator = Navigator.of(context);

    await backupCubit.signOut();
    await serverCubit.reset();
    await vaultCubit.resetVault();

    // Close the settings dialog — the router now shows onboarding.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = state.isProcessing;
    final theme = themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Signed-in banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: CustomColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: CustomColors.success.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_done_rounded,
                size: 16,
                color: CustomColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Signed in as ${state.email ?? 'unknown'}',
                  style: AppText.secondary.copyWith(
                    fontSize: 12,
                    color: theme.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: isProcessing
                    ? null
                    : () => _signOutOfDevice(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Sign out',
                  style: AppText.label.copyWith(
                    fontSize: 11,
                    color: CustomColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Save backup ────────────────────────────────────────
        SectionTitle(label: 'Save Backup', themeState: theme),
        const SizedBox(height: 4),
        Text(
          'Upload your current encrypted vault backup to the cloud. '
          'Your password is never sent.',
          style: AppText.secondary.copyWith(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            AppButton(
              label: 'Save to Cloud',
              isLoading: isProcessing,
              icon: const Icon(
                Icons.cloud_upload_rounded,
                size: 15,
                color: Colors.white,
              ),
              onPressed: isProcessing ? null : cubit.saveBackupToCloud,
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Restore from Cloud',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing
                  ? null
                  : () => cubit.importBackupFromCloud(),
            ),
          ],
        ),

        // Messages
        if (state.error != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.error!, isError: true),
        ],
        if (state.successMessage != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.successMessage!, isError: false),
        ],
      ],
    );
  }
}
