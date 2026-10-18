import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/server_context_scope.dart';
import 'server_manage_dialog.dart';
import 'server_manage_tab.dart';

/// The dialog with everything its pages read, for whichever route opens it.
///
/// Several cubits rather than one because the pages reach several places:
/// the server itself, the central listing and the account behind it — and
/// that server's own roster, soundboard and reports, which come with its
/// context ([ServerContextScope]). Opened from the rail's menu for a server
/// the person is *not* looking at, the dialog holds that server's context for
/// as long as it is open — live, from that server's doorbells — rather than
/// switching the person over, and every call its pages and the dialogs they
/// open make goes there.
Widget serverManageDialog(
  BuildContext context, {
  required Server server,
  ServerManageTab? initial,
}) {
  return ServerContextScope(
    serverId: server.id,
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<ServerCubit>()),
        BlocProvider.value(value: context.read<PublicServersCubit>()),
        BlocProvider.value(value: context.read<SupabaseBackupCubit>()),
      ],
      child: ServerManageDialog(server: server, initial: initial),
    ),
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
