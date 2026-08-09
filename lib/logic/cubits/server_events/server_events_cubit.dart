import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../services/channel_eviction.dart';
import '../../services/server_table_watcher.dart';
import '../channel_chat/channel_chat_cubit.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

/// Realtime "something changed on this server" doorbell (Supabase Broadcast),
/// one topic per selected server — `server_events:<serverId>`.
///
/// Any member who makes a structural change (creating a channel, …) pings the
/// topic via [notifyServerChanged]; every subscribed member refreshes their
/// server details, so new channels appear without waiting for a reselect or
/// restart. Broadcast is ephemeral pub/sub, so — like the chat keysweep
/// doorbell — it needs no auth/RLS: the payload is just "go refresh", and the
/// authoritative state still comes from `get_server_details`.
///
/// Scoped to the selected server (that's the one whose channel list is shown);
/// other servers refresh on select.
class ServerEventsCubit extends Cubit<int> {
  final ServerCubit _serverCubit;
  final LiveKitCubit _livekitCubit;
  final ChannelChatCubit _chatCubit;
  StreamSubscription<ServerState>? _serverSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _serverId;

  /// The doorbell above is a courtesy — it only rings if the member who made
  /// the change remembered to ring it, and never for someone who was offline.
  /// `channels` is in the realtime publication, so this is the authoritative
  /// half: a rename or a deletion reaches everyone whatever the actor did.
  late final ServerTableWatcher _channelsWatcher;

  ServerEventsCubit({
    required ServerCubit serverCubit,
    required LiveKitCubit livekitCubit,
    required ChannelChatCubit chatCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       _chatCubit = chatCubit,
       super(0) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _sync();
    _channelsWatcher = ServerTableWatcher(
      serverCubit: serverCubit,
      table: 'channels',
      onChanged: () => unawaited(_onChannelsChanged()),
      onServerChanged: (_) {},
    );
  }

  Future<void> _onChannelsChanged() async {
    final result = await _serverCubit.refreshServerDetails();
    if (isClosed || !result.success) return;
    _evictFromDeletedChannels();
  }

  /// A deleted channel takes anyone standing in it with it.
  ///
  /// The event doesn't say which channel went, and it doesn't need to: after
  /// the refresh, anything we're still pointed at that the server no longer
  /// lists is gone. That covers a channel deleted out from under us and a
  /// channel we've lost access to, without treating them differently.
  ///
  /// LiveKit does the real eviction — `delete_channel` deletes the room, which
  /// drops every device in it. This is the local tidy-up: leaving the call
  /// properly rather than sitting in a room the server has removed, and closing
  /// a chat whose channel no longer exists.
  void _evictFromDeletedChannels() {
    final channels = _serverCubit.state.selectedServer?.channels;
    if (channels == null) return;
    final live = ChannelEviction.liveIds(channels);

    if (ChannelEviction.isGone(_livekitCubit.state.currentChannelId, live)) {
      unawaited(_livekitCubit.disconnect());
    }
    if (ChannelEviction.isGone(_chatCubit.state.channelId, live)) {
      _chatCubit.closeChannel();
    }
  }

  void _sync() {
    final server = _serverCubit.state.selectedServer;
    if (server == null || server.supabaseKey == null) {
      _teardown();
      return;
    }
    if (server.id == _serverId) return; // already subscribed to this server

    _teardown();
    _serverId = server.id;
    final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _client = client;
    _channel = client.channel('server_events:${server.id}')
      ..onBroadcast(event: 'changed', callback: (_) => _onChanged())
      ..subscribe();
  }

  void _onChanged() {
    if (isClosed) return;
    unawaited(_serverCubit.refreshServerDetails());
  }

  /// Ping the selected server's topic so other members refresh.
  void notifyServerChanged() {
    try {
      _channel?.sendBroadcastMessage(event: 'changed', payload: {});
    } catch (_) {}
  }

  void _teardown() {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    _serverId = null;
    unawaited(() async {
      try {
        await channel?.unsubscribe();
        client?.removeAllChannels();
        await client?.dispose();
      } catch (_) {}
    }());
  }

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _channelsWatcher.dispose();
    _teardown();
    return super.close();
  }
}
