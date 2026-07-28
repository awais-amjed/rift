import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
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
class AccountStep extends StatefulWidget {
  final VoidCallback onBack;

  const AccountStep({super.key, required this.onBack});

  @override
  State<AccountStep> createState() => _AccountStepState();
}

class _AccountStepState extends State<AccountStep> {
  /// Set when the user returns from the email-confirmation view — the auth
  /// form should then open in sign-in mode (they already have an account).
  bool _preferSignIn = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        if (state.needsVaultPassword) {
          return VaultPasswordView(state: state, onBack: widget.onBack);
        }
        if (state.needsEmailConfirmation) {
          return EmailConfirmationView(
            state: state,
            onBack: widget.onBack,
            onSignIn: () {
              setState(() => _preferSignIn = true);
              context.read<SupabaseBackupCubit>().clearMessage();
            },
          );
        }
        return AuthView(
          state: state,
          onBack: widget.onBack,
          initialSignUp: !_preferSignIn,
        );
      },
    );
  }
}
