import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../mobile/mobile_shell_scope.dart';
import 'confirm_voice_switch.dart';

/// Opens the call in [ch], joining it unless already in it. False when the
/// person cancelled the switch from another call.
///
/// Shared by the channel list and anything else that takes somebody into a
/// call — a member card's Watch, from either sidebar.
Future<bool> openVoiceChannel(BuildContext context, Channel ch) async {
  final app = context.read<AppCubit>();
  final selected = app.state.selectedChannelId;
  // On a phone the call is a page: opening the one you are already in takes
  // you back into it.
  final shell = MobileShellScope.maybeOf(context);
  if (shell != null && selected == ch.id) {
    shell.openCall();
    return true;
  }
  // Asked before anything moves, so cancelling leaves the screen exactly as
  // it was — the chat you were reading included.
  if (!await confirmVoiceSwitch(context, ch)) return false;
  if (!context.mounted) return false;
  if (shell != null) {
    app.setSelectedChannelId(ch.id);
    return true;
  }
  // Joining voice brings the voice pane back to the front.
  app.setSurface(HomeSurface.server);
  unawaited(context.read<ChannelChatCubit>().closeChannel());
  if (selected != ch.id) app.setSelectedChannelId(ch.id);
  return true;
}

/// Into [userId]'s call in [ch], if not there already, and onto their stream.
/// The stream opens once the call has connected and it has arrived.
Future<void> watchStreamIn(
  BuildContext context,
  Channel ch,
  String userId,
) async {
  final livekit = context.read<LiveKitCubit>();
  if (!await openVoiceChannel(context, ch)) return;
  livekit.watchStreamOf(userId, channelId: ch.id);
}
