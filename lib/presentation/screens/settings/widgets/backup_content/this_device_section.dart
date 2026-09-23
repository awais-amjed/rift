import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/setting_row.dart';
import '../section_title.dart';

/// What can be done to *this device*, at the end of the Cloud backup tab:
/// sign it out, and wipe its vault.
///
/// Both used to hide elsewhere. Sign out was red 11px text inside the green
/// signed-in banner, an action that wipes the local vault dressed as a
/// footnote. Reset lived at the bottom of the settings nav, the same corner
/// the gear that opens settings occupies on the screen behind — so a second
/// click landed on wiping the identity. Here they are unreachable until you
/// have chosen the one tab they belong with, and they read in the right
/// order: back up your vault, restore your vault, then leave or destroy it.
class ThisDeviceSection extends StatelessWidget {
  /// Whether there is an account to sign out of.
  final bool signedIn;

  /// Wipes the vault. Confirmed by the caller before anything is destroyed.
  final VoidCallback onResetVault;

  const ThisDeviceSection({
    super.key,
    required this.signedIn,
    required this.onResetVault,
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
      confirmLabel: 'Sign out',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'This device'),
        const SizedBox(height: 14),
        if (signedIn) ...[
          SettingRow(
            title: 'Sign out of this device',
            description:
                'Removes the vault and server list here. Your cloud backup '
                'stays, and signing back in restores them.',
            control: AppButton(
              label: 'Sign out',
              variant: AppButtonVariant.secondary,
              onPressed: () => _signOutOfDevice(context),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SettingRow(
          title: 'Reset vault',
          description: 'Wipes your keys and servers from this device.',
          control: AppButton(
            label: 'Reset vault',
            variant: AppButtonVariant.danger,
            onPressed: onResetVault,
          ),
        ),
      ],
    );
  }
}
