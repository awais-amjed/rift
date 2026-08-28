import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu_region.dart';
import '../../channel_members_dialog.dart';

/// The three things you can do to a channel's privacy, out of the menu that
/// offers them.
///
/// Free functions rather than methods, because the same three belong in a
/// channel's own header eventually and neither surface should own them. Each
/// one says out loud the thing about an encrypted room that is not obvious:
/// what a removed member keeps, and what a new one does not get.

void openChannelMembers(BuildContext context, Channel channel) {
  showDialogFromMenu(
    context: context,
    build: (ctx) => BlocProvider.value(
      value: ctx.read<ServerCubit>(),
      child: ChannelMembersDialog(channel: channel),
    ),
  );
}

/// Closing a channel seats everybody who is on the server right now, so the
/// conversation does not empty out under the people having it. Narrowing it
/// down is the next step, which is why the member list opens straight after.
Future<void> makeChannelPrivate(BuildContext context, Channel channel) async {
  ContextMenuScope.of(context)?.call();
  final serverCubit = context.read<ServerCubit>();

  final confirmed = await showConfirmDialog(
    context: context,
    title: 'Make #${channel.name} private?',
    message:
        'Everyone here now stays in it, and you choose who to remove next. '
        'Anybody you remove keeps what they have already read — that cannot '
        'be taken back — but sees nothing after that.',
    confirmLabel: 'Make private',
    icon: Icons.lock_outline_rounded,
  );
  if (!confirmed || !context.mounted) return;

  final result = await serverCubit.setChannelPrivate(
    channelId: channel.id,
    isPrivate: true,
  );
  if (!result.success) {
    HelperMethods.showError(
      error: result.error ?? 'Could not make that channel private',
    );
    return;
  }
  if (context.mounted) openChannelMembers(context, channel);
}

Future<void> openChannelUp(BuildContext context, Channel channel) async {
  ContextMenuScope.of(context)?.call();
  final serverCubit = context.read<ServerCubit>();

  final confirmed = await showConfirmDialog(
    context: context,
    title: 'Open #${channel.name} to everyone?',
    message:
        'Everybody on the server will see it from now on. What was said '
        'while it was private stays unreadable to them — they are given a '
        'new key, not the old one.',
    confirmLabel: 'Open it up',
    icon: Icons.lock_open_rounded,
  );
  if (!confirmed) return;

  final result = await serverCubit.setChannelPrivate(
    channelId: channel.id,
    isPrivate: false,
  );
  if (!result.success) {
    HelperMethods.showError(
      error: result.error ?? 'Could not open that channel up',
    );
  }
}
