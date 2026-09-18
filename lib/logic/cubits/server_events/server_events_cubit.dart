import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/channel_eviction.dart';
import '../../services/server_realtime.dart';
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

  RealtimeLease? _topic;
  String? _serverId;

  /// The doorbell above is a courtesy — it only rings if the member who made
  /// the change remembered to ring it, and never for someone who was offline.
  /// `channels` is in the realtime publication, so this is the authoritative
  /// half: a rename or a deletion reaches everyone whatever the actor did.
  late final ServerTableWatcher _channelsWatcher;

  /// Our own membership row, which is the only thing a banned member can still
  /// read (`users_select_self`).
  ///
  /// A ban is a structural change like any other here, and the response is the
  /// same one: re-read the server. The difference is what comes back — no
  /// channels, and a user row saying `is_banned`, which is what the UI needs
  /// to say something rather than going quietly inert. Lifting the ban arrives
  /// through the same subscription, so a client comes back on its own instead
  /// of needing a restart.
  late final ServerTableWatcher _membershipWatcher;

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
    _membershipWatcher = ServerTableWatcher(
      serverCubit: serverCubit,
      table: 'users',
      onChanged: () => unawaited(_onMembershipChanged()),
      // Selecting a server re-reads it anyway; this only has to keep up with
      // changes after that.
      onServerChanged: (_) {},
    );
  }

  /// Someone's `users` row moved — possibly ours.
  ///
  /// The watcher can't tell us whose, and doesn't need to: re-reading the
  /// server is cheap, idempotent, and is what makes `user.isBanned` current.
  /// A ban that arrives while we're in a call is left to `moderate_user`,
  /// which removes us from LiveKit itself.
  Future<void> _onMembershipChanged() async {
    await _serverCubit.refreshServerDetails();
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
    _topic = _serverCubit.realtime.join(server, 'server_events:${server.id}')
      ?..onBroadcast('changed', (_) => _onChanged());
  }

  void _onChanged() {
    if (isClosed) return;
    unawaited(_serverCubit.refreshServerDetails());
  }

  /// Ping [serverId]'s topic so other members refresh.
  ///
  /// Only one server is subscribed at a time — the one being looked at — so a
  /// change applied to another server (its settings, from the rail's menu) has
  /// no topic to ring here and is dropped. Those members hear it from Realtime
  /// on the row itself instead; the doorbell is only what makes it immediate.
  void notifyServerChanged(String serverId) {
    if (serverId != _serverId) return;
    _topic?.send('changed', const {});
  }

  void _teardown() {
    final topic = _topic;
    _topic = null;
    _serverId = null;
    unawaited(topic?.release());
  }

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _channelsWatcher.dispose();
    await _membershipWatcher.dispose();
    _teardown();
    return super.close();
  }
}
