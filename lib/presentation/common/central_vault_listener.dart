import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../logic/cubits/token/token_cubit.dart';
import '../../logic/cubits/vault/vault_cubit.dart';

/// Tells Rift DMs to look again once the cloud backup has settled.
///
/// Rift DMs wait, without publishing anything, while the account's keys are
/// another vault's (`CentralDmStatus.otherVault`). Keeping this device's
/// vault answers that by uploading it, which nothing on central rings about,
/// so the backup finishing its work is the moment to ask again.
///
/// And drops the call tokens cached for the identity before, once the vault's
/// seed changes under them: a reset, or a backup of another identity restored.
/// Each is the server's word that its holder may join a channel as them, for
/// most of an hour.
class CentralVaultListener extends StatelessWidget {
  final Widget child;

  const CentralVaultListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SupabaseBackupCubit, SupabaseBackupState>(
          listenWhen: (before, after) =>
              before.isProcessing && !after.isProcessing,
          listener: (context, _) {
            final dms = context.read<CentralDmCubit>();
            if (dms.state.status == CentralDmStatus.otherVault) {
              dms.retryReady();
            }
          },
        ),
        BlocListener<VaultCubit, VaultState>(
          listenWhen: (before, after) =>
              before.masterSeed != null &&
              before.masterSeed != after.masterSeed,
          listener: (context, _) => context.read<TokenCubit>().forgetAll(),
        ),
      ],
      child: child,
    );
  }
}
