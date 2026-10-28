import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/participant_identity.dart';
import '../../data/repositories/server_session.dart';
import '../../data/repositories/session_repository.dart';
import '../cubits/app/app_cubit.dart';
import '../cubits/call_panels/call_panels_cubit.dart';
import '../cubits/channel_chat/channel_chat_cubit.dart';
import '../cubits/channel_presence/channel_presence_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../cubits/reports/reports_cubit.dart';
import '../cubits/server/server_cubit.dart';
import '../cubits/server_events/server_events_cubit.dart';
import '../cubits/server_members/server_members_cubit.dart';
import '../cubits/soundboard/soundboard_cubit.dart';
import '../cubits/token/token_cubit.dart';
import '../cubits/vault/vault_cubit.dart';
import '../cubits/voice_listeners/voice_listeners_cubit.dart';

/// Everything the app keeps live about one server: its roster, who is online
/// there and in which voice channel, its soundboard, which bots hear which
/// channel, its reports and its doorbell.
///
/// One per server something is using, kept in [ServerHub]: the selected
/// server's, the call's, and the one a Manage page opened on another server
/// holds. Each of these cubits used to be one app-wide copy that followed the
/// selection, and what outlived the selection had to be patched with copies
/// of its own — a second roster for the call, a second presence join for the
/// call's server, a soundboard that followed the call, pinned copies for the
/// Manage page. Now the call holds its server's context like anything else,
/// and whatever is about that server reads the same one (`ServerScope`).
class ServerContext {
  final String serverId;
  final ServerMembersCubit members;
  final ChannelPresenceCubit presence;
  final SoundboardCubit soundboard;
  final VoiceListenersCubit voiceListeners;
  final ReportsCubit reports;
  final ServerEventsCubit events;
  final CallPanelsCubit callPanels;

  /// Calls to this server, for the scope that provides it.
  final ServerSession session;

  ServerContext({
    required this.serverId,
    required this.session,
    required this.members,
    required this.presence,
    required this.soundboard,
    required this.voiceListeners,
    required this.reports,
    required this.events,
    required this.callPanels,
  });

  /// Builds [serverId]'s cubits, wired to each other and to the app's.
  factory ServerContext.open(
    String serverId, {
    required SessionRepository session,
    required AppCubit appCubit,
    required VaultCubit vaultCubit,
    required TokenCubit tokenCubit,
    required ServerCubit serverCubit,
    required LiveKitCubit livekitCubit,
    required ChannelChatCubit chatCubit,
  }) {
    final presence = ChannelPresenceCubit(
      livekitCubit: livekitCubit,
      session: session,
      serverId: serverId,
    );
    final members = ServerMembersCubit(session: session, serverId: serverId);
    // A cached LiveKit token still grants what it was minted with, so being
    // muted here has to throw this server's away — otherwise rejoining
    // restores the old permissions until it expires.
    members.setOnSelfModerationChanged(() {
      final url = session.serverById(serverId)?.supabaseUrl;
      if (url != null) tokenCubit.invalidateServerTokens(url);
    });
    // Presence reports ids; with the roster paged, an id is routinely somebody
    // no page has reached. Resolving them is what keeps the sidebar's Online
    // group from being "the online people who sort early in the alphabet".
    members.watchPresence(presence.stream.map((state) => state.onlineUserIds));
    // And everybody in a call here, named and pictured — including a bot,
    // which is told apart by its row before its sound can be read.
    members.watchPresence(
      livekitCubit.stream
          .where((state) => state.callServerId == serverId)
          .map(
            (state) => {
              for (final participant in state.participants)
                ParticipantIdentity.userIdOf(participant.identity),
            },
          ),
    );
    // The players of the bots in this device's call, for every channel's bar
    // — the call's own server only.
    CallSeen inCall(LiveKitState state) => state.callServerId == serverId
        ? (
            channelId: state.currentChannelId,
            userIds: {
              for (final participant in state.participants)
                ParticipantIdentity.userIdOf(participant.identity),
            },
          )
        : (channelId: null, userIds: const {});
    final callPanels = CallPanelsCubit(session: session, serverId: serverId)
      ..watchCall(
        livekitCubit.stream.map(inCall),
        initial: inCall(livekitCubit.state),
      );
    return ServerContext(
      serverId: serverId,
      session: session.on(serverId),
      members: members,
      presence: presence,
      soundboard: SoundboardCubit(
        session: session,
        appCubit: appCubit,
        livekitCubit: livekitCubit,
        serverId: serverId,
      ),
      voiceListeners: VoiceListenersCubit(session: session, serverId: serverId),
      reports: ReportsCubit(
        session: session,
        vaultCubit: vaultCubit,
        serverId: serverId,
      ),
      events: ServerEventsCubit(
        serverCubit: serverCubit,
        session: session,
        livekitCubit: livekitCubit,
        chatCubit: chatCubit,
        serverId: serverId,
      ),
      callPanels: callPanels,
    );
  }

  /// [child] with this server's cubits above it.
  Widget provide(Widget child) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: members),
      BlocProvider.value(value: presence),
      BlocProvider.value(value: soundboard),
      BlocProvider.value(value: voiceListeners),
      BlocProvider.value(value: reports),
      BlocProvider.value(value: events),
      BlocProvider.value(value: callPanels),
    ],
    child: child,
  );

  Future<void> close() async {
    await members.close();
    await presence.close();
    await soundboard.close();
    await voiceListeners.close();
    await reports.close();
    await events.close();
    await callPanels.close();
  }
}
