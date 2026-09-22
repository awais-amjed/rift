import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../dms/widgets/central_identity_line.dart';
import '../../dms/widgets/change_handle_dialog.dart';

/// Home's second line: the central account's handle, with the way to change
/// it — the line the conversation list used to open with.
class SwitcherHomeLine extends StatelessWidget {
  const SwitcherHomeLine({super.key});

  @override
  Widget build(BuildContext context) {
    final handle = context.select<CentralDmCubit, String?>(
      (c) => c.state.myHandle,
    );
    return CentralIdentityLine(
      handle: handle,
      onChangeHandle: () => showChangeHandle(context, handle!),
    );
  }
}
