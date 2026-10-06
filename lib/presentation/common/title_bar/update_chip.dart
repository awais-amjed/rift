import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/update/update_cubit.dart';
import '../../routing/app_routes.dart';
import '../../theme/custom_colors.dart';
import '../status_chip.dart';
import '../update/update_ready_dialog.dart';

/// "Update ready" beside the window controls, once a newer Rift has
/// downloaded; pressing it shows what is new and the restart.
class UpdateChip extends StatelessWidget {
  const UpdateChip({super.key});

  @override
  Widget build(BuildContext context) {
    final version = context.select<UpdateCubit, String?>(
      (c) => c.state.status == UpdateStatus.ready ? c.state.version : null,
    );
    if (version == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: K.titleBarChipMaxWidth),
        child: StatusChip(
          icon: Icons.system_update_alt_rounded,
          label: 'Update ready',
          color: CustomColors.success,
          tooltip: 'Rift $version has downloaded. Restart to start using it.',
          // The bar sits above the navigator, so the dialog opens on the
          // navigator's own context.
          onTap: () => showUpdateReadyDialog(AppRoutes.context),
        ),
      ),
    );
  }
}
