import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'account_recovery_view.dart';
import 'auth_view.dart';
import 'email_confirmation_view.dart';
import 'vault_password_view.dart';

/// Default onboarding step — sign in to or create a Rift account.
///
/// The vault is handled automatically after auth (see
/// [SupabaseBackupCubit]): an existing cloud backup is restored, or a fresh
/// vault is created and uploaded. The router leaves onboarding as soon as
/// the vault unlocks. Only a privacy-mode backup (manually chosen vault
/// password) requires the extra unlock prompt rendered here.
class AccountStep extends StatelessWidget {
  final VoidCallback onBack;

  const AccountStep({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        if (state.accountRecovery != AccountRecoveryStage.idle) {
          return AccountRecoveryView(
            state: state,
            onBack: context.read<SupabaseBackupCubit>().cancelAccountRecovery,
          );
        }
        if (state.needsVaultPassword) {
          return VaultPasswordView(state: state, onBack: onBack);
        }
        if (state.needsEmailConfirmation) {
          return EmailConfirmationView(
            state: state,
            onBack: onBack,
            // Leaving the notice rebuilds the form from scratch, and the form
            // opens on sign in — which is where somebody who has just been
            // told to confirm an address belongs. It used to take a flag to
            // arrange that, back when the form opened on sign up.
            onSignIn: context.read<SupabaseBackupCubit>().clearMessage,
          );
        }
        return AuthView(state: state, onBack: onBack);
      },
    );
  }
}
