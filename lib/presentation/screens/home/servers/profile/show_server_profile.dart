import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_sheet.dart';
import '../../../../common/server_context_scope.dart';
import '../../../../responsive/shell_scope.dart';
import 'server_profile_dialog.dart';

/// The profile with everything it reads, for whichever route opens it.
///
/// Inside [server]'s own context ([ServerContextScope]), because it can be
/// opened from the rail's menu for a server the person is not looking at:
/// its member count, who is online and the person's own roles come from
/// that server's roster, held for as long as the profile is open. The
/// cubits Manage server reads are passed in too, since it opens from here.
Widget serverProfileDialog(BuildContext context, {required Server server}) {
  return ServerContextScope(
    serverId: server.id,
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<ThemeCubit>()),
        BlocProvider.value(value: context.read<ServerCubit>()),
        BlocProvider.value(value: context.read<ServerNotificationsCubit>()),
        BlocProvider.value(value: context.read<PublicServersCubit>()),
        BlocProvider.value(value: context.read<SupabaseBackupCubit>()),
        BlocProvider.value(value: context.read<LiveKitCubit>()),
      ],
      child: ServerProfileDialog(serverId: server.id),
    ),
  );
}

/// Open the profile from anywhere with a plain context; a sheet on a phone,
/// as a person's profile is. A context menu goes through
/// [showDialogFromMenu] with [serverProfileDialog] instead.
Future<void> showServerProfile(BuildContext context, {required Server server}) {
  final dialog = serverProfileDialog(context, server: server);
  if (context.layoutMode.isCompact) return showAppSheet<void>(context, dialog);
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    build: (_) => dialog,
  );
}
