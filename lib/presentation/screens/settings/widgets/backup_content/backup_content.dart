import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'auth_panel.dart';
import 'change_password_panel.dart';
import 'confirm_email_panel.dart';
import 'conflict_panel.dart';
import 'file_backup_panel.dart';
import 'recovery_key_panel.dart';
import 'signed_in_panel.dart';
import 'this_device_section.dart';
import 'vault_password_panel.dart';

/// Backup tab content rendered inside the settings dialog.
///
/// Everything that decides which identity this device holds, in the order you
/// would do it: sign in to the central account, save or restore the encrypted
/// backup, and — last, because they are the steps with no way back — sign the
/// device out or wipe its vault (see [ThisDeviceSection] for why those live
/// here rather than in the nav or the signed-in banner).
class BackupContent extends StatelessWidget {
  /// Wipes the vault. Confirmed by the caller before anything is destroyed.
  final VoidCallback onResetVault;

  const BackupContent({super.key, required this.onResetVault});

  @override
  Widget build(BuildContext context) {
    // Uses the app-global SupabaseBackupCubit provided in main.dart.
    return _BackupBody(onResetVault: onResetVault);
  }
}

class _BackupBody extends StatelessWidget {
  final VoidCallback onResetVault;

  const _BackupBody({required this.onResetVault});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        final Widget cloudPanel;
        if (state.cloudBackupConflict) {
          cloudPanel = ConflictPanel(state: state);
        } else if (state.needsVaultPassword) {
          cloudPanel = VaultPasswordPanel(state: state);
        } else if (state.isSignedIn) {
          cloudPanel = SignedInPanel(state: state);
        } else if (state.needsEmailConfirmation) {
          cloudPanel = ConfirmEmailPanel(state: state);
        } else {
          cloudPanel = AuthPanel(state: state);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cloudPanel,
            // Only once there is a settled vault to change the password of —
            // not while the screen is still asking someone to sign in, resolve
            // a conflict, or confirm an address.
            if (!state.cloudBackupConflict &&
                !state.needsVaultPassword &&
                !state.needsEmailConfirmation) ...[
              const SizedBox(height: 28),
              ChangePasswordPanel(state: state),
              const SizedBox(height: 28),
              const RecoveryKeyPanel(),
            ],
            const SizedBox(height: 28),
            const FileBackupPanel(),
            const SizedBox(height: 28),
            ThisDeviceSection(
              signedIn: state.isSignedIn,
              onResetVault: onResetVault,
            ),
          ],
        );
      },
    );
  }
}
