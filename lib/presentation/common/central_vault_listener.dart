import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';

/// Tells Rift DMs to look again once the cloud backup has settled.
///
/// Rift DMs wait, without publishing anything, while the account's keys are
/// another vault's (`CentralDmStatus.otherVault`). Keeping this device's
/// vault answers that by uploading it, which nothing on central rings about,
/// so the backup finishing its work is the moment to ask again.
class CentralVaultListener extends StatelessWidget {
  final Widget child;

  const CentralVaultListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SupabaseBackupCubit, SupabaseBackupState>(
      listenWhen: (before, after) => before.isProcessing && !after.isProcessing,
      listener: (context, _) {
        final dms = context.read<CentralDmCubit>();
        if (dms.state.status == CentralDmStatus.otherVault) {
          dms.retryReady();
        }
      },
      child: child,
    );
  }
}
