import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../common/app_modal.dart';
import 'server_manage_dialog.dart';
import 'server_manage_tab.dart';

/// The dialog with everything its pages read, for whichever route opens it.
///
/// Several cubits rather than one because the pages reach several places:
/// the server itself, the central listing, the account behind it, the
/// soundboard's library, the roster, and the reports.
///
/// The last three follow the selected server in the app. Opened from the
/// rail's menu for a server the person is *not* looking at, the dialog holds
/// that server's own for as long as it is open — live, from that server's
/// doorbells — rather than switching them, or the person, over.
Widget serverManageDialog(
  BuildContext context, {
  required Server server,
  ServerManageTab? initial,
}) {
  final serverCubit = context.read<ServerCubit>();
  final isSelected = serverCubit.state.selectedServer?.id == server.id;
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: serverCubit),
      BlocProvider.value(value: context.read<PublicServersCubit>()),
      BlocProvider.value(value: context.read<SupabaseBackupCubit>()),
      if (isSelected) ...[
        BlocProvider.value(value: context.read<SoundboardCubit>()),
        BlocProvider.value(value: context.read<ServerMembersCubit>()),
        BlocProvider.value(value: context.read<ReportsCubit>()),
      ] else ...[
        BlocProvider(
          create: (_) => SoundboardCubit(
            serverCubit: serverCubit,
            appCubit: context.read<AppCubit>(),
            livekitCubit: context.read<LiveKitCubit>(),
            serverId: server.id,
          ),
        ),
        BlocProvider(
          create: (_) =>
              ServerMembersCubit(serverCubit: serverCubit, serverId: server.id),
        ),
        BlocProvider(
          create: (_) => ReportsCubit(
            serverCubit: serverCubit,
            vaultCubit: context.read<VaultCubit>(),
            serverId: server.id,
          ),
        ),
      ],
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
