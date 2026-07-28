import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';

import 'auth_panel.dart';
import 'confirm_email_panel.dart';
import 'conflict_panel.dart';
import 'file_backup_panel.dart';
import 'signed_in_panel.dart';
import 'vault_password_panel.dart';

/// Backup tab content rendered inside the settings dialog.
///
/// Provides:
/// - Sign up / sign in to the central Supabase server
/// - Save current encrypted backup to the cloud
class BackupContent extends StatelessWidget {
  final ThemeState themeState;

  const BackupContent({super.key, required this.themeState});

  @override
  Widget build(BuildContext context) {
    // Uses the app-global SupabaseBackupCubit provided in main.dart.
    return _BackupBody(themeState: themeState);
  }
}

class _BackupBody extends StatelessWidget {
  final ThemeState themeState;

  const _BackupBody({required this.themeState});

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
          cloudPanel = ConfirmEmailPanel(
            themeState: themeState,
            email: state.email,
          );
        } else {
          cloudPanel = AuthPanel(themeState: themeState, state: state);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cloudPanel,
            const SizedBox(height: 28),
            FileBackupPanel(themeState: themeState),
          ],
        );
      },
    );
  }
}
