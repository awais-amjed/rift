import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu_region.dart';
import '../../bots/channel_bots_dialog.dart';
import '../../bots/voice_bots_dialog.dart';
import '../../channel_members_dialog.dart';
import '../../channel_settings_dialog.dart';
import '../../webhooks/channel_webhooks_dialog.dart';

/// Everything the channel menu opens or asks, out of the menu that offers it.
///
/// Free functions rather than methods, because the same set belongs in a
/// channel's own header eventually and neither surface should own them. The
/// privacy ones each say out loud the thing about an encrypted room that is not
/// obvious: what a removed member keeps, and what a new one does not get.

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

/// Walk out of one.
///
/// The confirm says the two things that are true and unobvious: what you have
/// already read stays read, because nobody can take back a decrypted message,
/// and there is no way back in on your own.
Future<void> leaveChannel(BuildContext context, Channel channel) async {
  ContextMenuScope.of(context)?.call();
  final serverCubit = context.read<ServerCubit>();

  final confirmed = await showConfirmDialog(
    context: context,
    title: 'Leave #${channel.name}?',
    message:
        'You will stop seeing anything new in here, and only somebody already '
        'in it can add you back. What you have already read stays readable.',
    confirmLabel: 'Leave channel',
    icon: Icons.logout_rounded,
    isDestructive: true,
  );
  if (!confirmed) return;

  final result = await serverCubit.leaveChannel(channel.id);
  if (!result.success) {
    HelperMethods.showError(error: result.error ?? 'Could not leave');
  }
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

void openChannelSettings(BuildContext context, Channel channel) {
  showDialogFromMenu(
    context: context,
    build: (ctx) => BlocProvider.value(
      value: ctx.read<ServerCubit>(),
      child: ChannelSettingsDialog(channel: channel),
    ),
  );
}

void openChannelWebhooks(BuildContext context, Channel channel) {
  showDialogFromMenu(
    context: context,
    build: (ctx) => BlocProvider.value(
      value: ctx.read<ServerCubit>(),
      child: ChannelWebhooksDialog(channel: channel),
    ),
  );
}

/// The one that gives something away permanently — see [ChannelBotsDialog].
void openChannelBots(BuildContext context, Channel channel) {
  showDialogFromMenu(
    context: context,
    build: (ctx) => BlocProvider.value(
      value: ctx.read<ServerCubit>(),
      child: ChannelBotsDialog(channel: channel),
    ),
  );
}

/// The voice one, which unlike its neighbour can be undone — see
/// [VoiceBotsDialog]. Two providers, because the dialog refreshes the sidebar's
/// marker itself rather than leaving it saying something that stopped being
/// true.
void openVoiceBots(BuildContext context, Channel channel) {
  showDialogFromMenu(
    context: context,
    build: (ctx) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: ctx.read<ServerCubit>()),
        BlocProvider.value(value: ctx.read<VoiceListenersCubit>()),
      ],
      child: VoiceBotsDialog(channel: channel),
    ),
  );
}
