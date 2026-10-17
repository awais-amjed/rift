import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
import 'add_server_dialog.dart';

/// Opens [AddServerDialog] — joining, browsing for or connecting a server —
/// from anywhere that can reach the two cubits it needs.
///
/// The dialog is pushed above the shell, out of reach of the providers it
/// was opened under, so it carries them along. [servers] and [app] are for a
/// caller that has already left its own context behind, as the phone's
/// switcher does by closing itself first; everyone else lets them be read.
void showAddServerDialog(
  BuildContext context, {
  ServerCubit? servers,
  AppCubit? app,
}) {
  final serverCubit = servers ?? context.read<ServerCubit>();
  final appCubit = app ?? context.read<AppCubit>();
  showCustomDialog(
    context: context,
    build: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: serverCubit),
        BlocProvider.value(value: appCubit),
      ],
      child: const AddServerDialog(),
    ),
  );
}
