import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/confirm_dialog.dart';
import '../../../common/context_menu/context_menu_scope.dart';

/// Ask, then leave [server]: from its rail chip's menu, or its profile.
///
/// Leaving takes us off the server's member list (`leave_server`): a kick
/// by our own hand, so the roles and private channels go, what we wrote
/// stays, and any new invite brings us back as ourselves.
///
/// Except for an **owner**, whom the server will not let go, because the
/// one person who can end the server or hand it on would be walking out of
/// the only place they could do either from. For them leaving still only
/// forgets the server here, and the dialog says so: nobody else can do it
/// for them, and an invite back has to come from an admin who is still
/// there. The danger zone already points at Transfer ownership; this is the
/// other door into the same mistake.
///
/// [beforeLeaving] runs once the answer is yes: the profile closes there,
/// rather than staying open over a server that is about to go.
Future<void> leaveServer(
  BuildContext context, {
  required Server server,
  VoidCallback? beforeLeaving,
}) async {
  // Read before the menu goes, which takes [context] with it.
  final dismiss = ContextMenuScope.of(context);
  final serverCubit = context.read<ServerCubit>();
  final call = context.read<LiveKitCubit>();
  final isOwner = server.user?.permissions.isOwner ?? false;
  dismiss?.call();

  final confirmed = await showConfirmDialog(
    context: context,
    title: 'Leave ${server.name}?',
    message: isOwner
        ? 'This removes the server and its keys from this device, but you '
              'stay its owner — and the owner is the only person who can '
              'end it or hand it on. Nobody left behind can do either, and '
              'getting back in needs an invite from an admin who is still '
              'there. To step down properly, open Members and choose '
              'Transfer ownership first.'
        : 'You leave its member list, and lose your roles and private '
              'channels. Your messages stay. A new invite brings you back '
              'as yourself.',
    confirmLabel: 'Leave',
    icon: Icons.logout_rounded,
    isDestructive: true,
  );
  if (!confirmed) return;
  beforeLeaving?.call();
  // Hung up first: the server takes away what the call stood on, and a
  // call left running would talk on into a server we are no longer in.
  final state = call.state;
  final inCallHere =
      state.dmCall?.serverId == server.id ||
      server.channels.any((c) => c.id == state.currentChannelId);
  if (inCallHere) await call.disconnect();
  await serverCubit.leaveServer(server);
}
