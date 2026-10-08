import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/channel_access_api.dart';
import '../../../../../../data/apis/channels_api.dart';
import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../data/repositories/session_repository.dart';
import '../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu_region.dart';
import '../../settings/channel_settings_dialog.dart';
import '../../settings/channel_settings_tab.dart';

/// Everything a channel's menu and its settings open or ask, out of the
/// surfaces that offer them.
///
/// Free functions rather than methods, because more than one surface offers
/// each of them — the menu, the row's gear, the settings pages — and none of
/// them should own it. The privacy ones each say out loud the thing about an
/// encrypted room that is not obvious: what a removed member keeps, and what a
/// new one does not get.

/// Closing a channel seats everybody who is on the server right now, so the
/// conversation does not empty out under the people having it. Narrowing it
/// down is the next step, on the Access page this is asked from.
///
/// True when the channel is now private.
Future<bool> makeChannelPrivate(BuildContext context, Channel channel) async {
  final access = ChannelAccessApi(session: context.read<SessionRepository>());

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
  if (!confirmed) return false;

  final result = await access.setChannelPrivate(
    channelId: channel.id,
    isPrivate: true,
  );
  if (!result.success) {
    HelperMethods.showError(
      error: result.error ?? 'Could not make that channel private',
    );
  }
  return result.success;
}

/// Walk out of one.
///
/// The confirm says the two things that are true and unobvious: what you have
/// already read stays read, because nobody can take back a decrypted message,
/// and there is no way back in on your own.
Future<void> leaveChannel(BuildContext context, Channel channel) async {
  ContextMenuScope.of(context)?.call();
  final access = ChannelAccessApi(session: context.read<SessionRepository>());

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

  final result = await access.leaveChannel(channel.id);
  if (!result.success) {
    HelperMethods.showError(error: result.error ?? 'Could not leave');
  }
}

/// True when the channel is now open to everyone.
Future<bool> openChannelUp(BuildContext context, Channel channel) async {
  final access = ChannelAccessApi(session: context.read<SessionRepository>());

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
  if (!confirmed) return false;

  final result = await access.setChannelPrivate(
    channelId: channel.id,
    isPrivate: false,
  );
  if (!result.success) {
    HelperMethods.showError(
      error: result.error ?? 'Could not open that channel up',
    );
  }
  return result.success;
}

/// Turn a public text channel's encryption off, or back on. True when it
/// changed.
///
/// The confirm says what moves and what does not: only new messages change,
/// and off means the server, and anybody who joins, can read them.
Future<bool> setChannelEncryption(
  BuildContext context,
  Channel channel, {
  required bool encrypted,
}) async {
  final access = ChannelAccessApi(session: context.read<SessionRepository>());

  final confirmed = await showConfirmDialog(
    context: context,
    title: encrypted
        ? 'Turn encryption back on in #${channel.name}?'
        : 'Turn off encryption in #${channel.name}?',
    message: encrypted
        ? 'New messages will be end-to-end encrypted again. What was sent '
              'while it was off stays readable to the server.'
        : 'The server, and anybody who joins, will be able to read new '
              'messages here. What was already sent stays encrypted. Everyone '
              'in the channel is told.',
    confirmLabel: encrypted ? 'Turn on' : 'Turn off',
    icon: encrypted ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
    isDestructive: !encrypted,
  );
  if (!confirmed) return false;

  final result = await access.setChannelEncrypted(
    channelId: channel.id,
    encrypted: encrypted,
  );
  if (!result.success) {
    HelperMethods.showError(
      error: result.error ?? 'Could not change encryption here',
    );
  }
  return result.success;
}

/// Asks, then deletes. True when the channel is gone.
///
/// [onConfirmed] runs between the two, for a button that should look busy
/// only once there is something to wait for — not behind the question.
Future<bool> deleteChannel(
  BuildContext context,
  Channel channel, {
  VoidCallback? onConfirmed,
}) async {
  final channels = ChannelsApi(session: context.read<SessionRepository>());
  final isVoice = channel.channelType == ChannelType.voice;

  final confirmed = await showConfirmDialog(
    context: context,
    title: 'Delete #${channel.name}?',
    message: isVoice
        ? 'Anyone in this call will be disconnected. The channel and its '
              'history are gone for everyone, and this cannot be undone.'
        : 'The channel and every message in it are gone for everyone, and '
              'this cannot be undone.',
    confirmLabel: 'Delete channel',
    icon: Icons.delete_outline_rounded,
    isDestructive: true,
  );
  if (!confirmed) return false;
  onConfirmed?.call();

  final result = await channels.deleteChannel(channel.id);
  if (!result.success) {
    HelperMethods.showError(
      error: result.error ?? 'Could not delete that channel',
    );
  }
  return result.success;
}

/// Open [channel]'s settings, on [initial] or its first page.
///
/// From the menu or from the row's gear; [showDialogFromMenu] closes a menu
/// if there is one and is a plain dialog otherwise.
void openChannelSettings(
  BuildContext context,
  Channel channel, {
  ChannelSettingsTab? initial,
}) {
  // Ask how busy each region is before the dialog draws, because the picker
  // inside it is the only thing that shows this and nothing else keeps it
  // fresh: the roster is fetched when presence reconnects, not on a timer, so
  // what the cubit holds can be minutes old. A picker calling a region idle
  // while a call fills it is worse than one that says nothing.
  //
  // Here rather than in the dialog's `initState`: the action is what knows a
  // manager is about to look, and this way the request is in flight while the
  // dialog is still being built.
  //
  // Only for a voice channel on a server with somewhere to choose between —
  // anywhere else it is a request that would change no pixel.
  final serverCubit = context.read<ServerCubit>();
  if (!channel.hasMessages &&
      (serverCubit.state.selectedServer?.livekitNodes.length ?? 0) > 1) {
    unawaited(serverCubit.voiceRoster());
    // And where a call here is running right now. That comes with the
    // server's details, which nothing refreshes when a call starts — so
    // without this the picker said "always held in this region" over a call
    // running somewhere else, and never warned that saving would move it.
    unawaited(serverCubit.refreshServerDetails());
  }

  // The bots pages refresh the markers other surfaces show — the header's
  // chip and the sidebar's ear — rather than leaving them saying something
  // that stopped being true.
  showDialogFromMenu(
    context: context,
    build: (ctx) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: ctx.read<ServerCubit>()),
        BlocProvider.value(value: ctx.read<VoiceListenersCubit>()),
        BlocProvider.value(value: ctx.read<ChannelChatCubit>()),
      ],
      child: ChannelSettingsDialog(channel: channel, initial: initial),
    ),
  );
}
