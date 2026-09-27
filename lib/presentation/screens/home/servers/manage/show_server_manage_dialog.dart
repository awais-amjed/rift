import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_modal.dart';
import 'server_manage_dialog.dart';
import 'server_manage_tab.dart';

/// The dialog with everything its pages read, for whichever route opens it.
///
/// Several cubits rather than one because the pages reach several places:
/// the server itself, the central listing, the account behind it, the
/// soundboard's library, and the roster the soundboard page credits a clip
/// to.
Widget serverManageDialog(
  BuildContext context, {
  required Server server,
  ServerManageTab? initial,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: context.read<ServerCubit>()),
      BlocProvider.value(value: context.read<PublicServersCubit>()),
      BlocProvider.value(value: context.read<SupabaseBackupCubit>()),
      BlocProvider.value(value: context.read<SoundboardCubit>()),
      BlocProvider.value(value: context.read<ServerMembersCubit>()),
      BlocProvider.value(value: context.read<ReportsCubit>()),
    ],
    child: ServerManageDialog(server: server, initial: initial),
  );
}

/// Open the dialog from anywhere with a plain context.
Future<void> showServerManageDialog(
  BuildContext context, {
  required Server server,
  ServerManageTab? initial,
}) {
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    build: (_) => serverManageDialog(context, server: server, initial: initial),
  );
}
