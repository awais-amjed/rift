import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/quiet_danger_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
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
    // Each action under its own words, on the left, like every other section
    // on this page. As setting rows the two buttons sat at the far right of a
    // column whose other buttons all start at its left edge.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'This device'),
        const SizedBox(height: 14),
        if (signedIn) ...[
          _Action(
            title: 'Sign out of this device',
            description:
                'Removes the vault and server list here. Your cloud backup '
                'stays, and signing back in restores them.',
            button: AppButton(
              label: 'Sign out',
              variant: AppButtonVariant.secondary,
              onPressed: () => _signOutOfDevice(context),
            ),
          ),
          const SizedBox(height: 20),
        ],
        _Action(
          title: 'Reset vault',
          description: 'Wipes your keys and servers from this device.',
          // Quiet, as `QuietDangerButton` says a destructive option on a page
          // of options should be. The solid red belongs to the confirmation
          // this opens, which is the one button that actually wipes.
          button: QuietDangerButton(
            icon: Icons.delete_forever_outlined,
            label: 'Reset vault',
            onTap: onResetVault,
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final String title;
  final String description;
  final Widget button;

  const _Action({
    required this.title,
    required this.description,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.row.copyWith(color: theme.textPrimary)),
        const SizedBox(height: 3),
        Text(
          description,
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
        const SizedBox(height: 12),
        // Its own width, not the column's: a QuietDangerButton fills
        // whatever it is given.
        IntrinsicWidth(child: button),
      ],
    );
  }
}
