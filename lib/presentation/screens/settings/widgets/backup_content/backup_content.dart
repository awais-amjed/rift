import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';

import 'auth_panel.dart';
import 'confirm_email_panel.dart';
import 'conflict_panel.dart';
import 'file_backup_panel.dart';
import 'reset_vault_card.dart';
import 'signed_in_panel.dart';
import 'vault_password_panel.dart';

/// Backup tab content rendered inside the settings dialog.
///
/// Everything that decides which identity this device holds, in the order you
/// would do it: sign in to the central account, save or restore the encrypted
/// backup, and — last, because it is the one step with no way back — wipe the
/// vault (see [ResetVaultCard] for why that lives here rather than in the nav).
class BackupContent extends StatelessWidget {
  final ThemeState themeState;

  /// Wipes the vault. Confirmed by the caller before anything is destroyed.
  final VoidCallback onResetVault;

  const BackupContent({
    super.key,
    required this.themeState,
    required this.onResetVault,
  });

  @override
  Widget build(BuildContext context) {
    // Uses the app-global SupabaseBackupCubit provided in main.dart.
    return _BackupBody(themeState: themeState, onResetVault: onResetVault);
  }
}

class _BackupBody extends StatelessWidget {
  final ThemeState themeState;
  final VoidCallback onResetVault;

  const _BackupBody({required this.themeState, required this.onResetVault});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        final Widget cloudPanel;
        if (state.cloudBackupConflict) {
          cloudPanel = ConflictPanel(themeState: themeState, state: state);
        } else if (state.needsVaultPassword) {
          cloudPanel = VaultPasswordPanel(themeState: themeState, state: state);
        } else if (state.isSignedIn) {
          cloudPanel = SignedInPanel(themeState: themeState, state: state);
        } else if (state.needsEmailConfirmation) {
          cloudPanel = ConfirmEmailPanel(themeState: themeState, state: state);
        } else {
          cloudPanel = AuthPanel(themeState: themeState, state: state);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cloudPanel,
            const SizedBox(height: 28),
            FileBackupPanel(themeState: themeState),
            const SizedBox(height: 28),
            ResetVaultCard(themeState: themeState, onTap: onResetVault),
          ],
        );
      },
    );
  }
}
