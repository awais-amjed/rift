import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/session_repository.dart';
import '../../services/channel_eviction.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topic_watcher.dart';
import '../../services/server_topics.dart';
import '../channel_chat/channel_chat_cubit.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

/// Realtime "something changed on this server" doorbell: a `changed` on one
/// server's topic (`server:<serverId>`, private to its members).
///
/// Any member who makes a structural change (creating a channel, …) pings the
/// topic via [notifyServerChanged]; every subscribed member refreshes their
/// server details, so new channels appear without waiting for a reselect or
/// restart. The payload is just "go refresh", and the authoritative state
/// still comes from `get_server_details`.
///
/// Each server's context holds one (`ServerContext`): the selected server's,
/// whose channel list is shown, and the call's, so a channel deleted under a
/// call is left whichever server is being read. Other servers refresh on
/// select.
class ServerEventsCubit extends Cubit<int> {
  final ServerCubit _serverCubit;
  final SessionRepository _session;
  final LiveKitCubit _livekitCubit;
  final ChannelChatCubit _chatCubit;
  StreamSubscription<void>? _serverSub;

  /// The server this is about.
  final String _serverId;
  RealtimeLease? _topic;

  /// The doorbell above is a courtesy — it only rings if the member who made
  /// the change remembered to ring it, and never for someone who was offline.
  /// The database says `channels` itself whenever one moves,
  /// so this is the authoritative half: a rename or a deletion reaches
  /// everyone whatever the actor did.
  late final ServerTopicWatcher _channelsWatcher;

  /// Our own membership row, which is the only thing a banned member can still
  /// read (`users_select_self`) — and our own topic the only one they can
  /// still join, which is where the database says `me`.
  ///
  /// A ban is a structural change like any other here, and the response is the
  /// same one: re-read the server. The difference is what comes back — no
  /// channels, and a user row saying `is_banned`, which is what the UI needs
  /// to say something rather than going quietly inert. Lifting the ban arrives
  /// through the same subscription, so a client comes back on its own instead
  /// of needing a restart.
  late final ServerTopicWatcher _membershipWatcher;

  ServerEventsCubit({
    required ServerCubit serverCubit,
    required SessionRepository session,
    required LiveKitCubit livekitCubit,
    required ChannelChatCubit chatCubit,
    required String serverId,
  }) : _serverId = serverId,
       _serverCubit = serverCubit,
       _session = session,
       _livekitCubit = livekitCubit,
       _chatCubit = chatCubit,
       super(0) {
    _serverSub = session.changes.listen((_) => _sync());
    _sync();
    _channelsWatcher = ServerTopicWatcher(
      session: session,
      watchedServerId: serverId,
      topicOf: (server) => ServerTopics.server(server.id),
      event: ServerEvent.channels,
      onChanged: () => unawaited(_onChannelsChanged()),
      onServerChanged: (_) {},
    );
    _membershipWatcher = ServerTopicWatcher(
      session: session,
      watchedServerId: serverId,
      topicOf: (server) => ServerTopics.user(server.user!.id),
      event: ServerEvent.me,
      onChanged: () => unawaited(_onMembershipChanged()),
      whileBanned: true,
      // Opening a server re-reads it anyway; this only has to keep up with
      // changes after that.
      onServerChanged: (_) {},
    );
  }

  /// Our own `users` row moved.
  ///
  /// Re-reading the server is what makes `user.isBanned` current. It used to
  /// run for *anybody's* row, on every member at once.
  /// A ban that arrives while we're in a call is left to `moderate_user`,
  /// which removes us from LiveKit itself.
  Future<void> _onMembershipChanged() async {
    await _serverCubit.refreshServerDetails(serverId: _serverId);
  }

  Future<void> _onChannelsChanged() async {
    final result = await _serverCubit.refreshServerDetails(serverId: _serverId);
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
  ///
  /// Only what is on this server: a call or a chat on another one is that
  /// one's to judge, and against this server's channels it would look gone.
  void _evictFromDeletedChannels() {
    final channels = _session.serverById(_serverId)?.channels;
    if (channels == null) return;
    final live = ChannelEviction.liveIds(channels);

    final call = _livekitCubit.state;
    if (call.currentServerId == _serverId &&
        ChannelEviction.isGone(call.currentChannelId, live)) {
      unawaited(_livekitCubit.disconnect());
    }
    if (_chatCubit.openServerId == _serverId &&
        ChannelEviction.isGone(_chatCubit.state.channelId, live)) {
      _chatCubit.closeChannel();
    }
  }

  void _sync() {
    final server = _session.serverById(_serverId);
    if (server == null || server.supabaseKey == null || !server.admitsUs) {
      _teardown();
      return;
    }
    if (_topic != null) return; // already subscribed

    _topic = _session.realtime.join(server, ServerTopics.server(server.id))
      ?..onBroadcast(ServerEvent.changed, (_) => _onChanged());
  }

  void _onChanged() {
    if (isClosed) return;
    unawaited(_serverCubit.refreshServerDetails(serverId: _serverId));
  }

  /// Ping [serverId]'s topic so other members refresh.
  ///
  /// Rung on the cubit of the server the change was made on, which the
  /// widget that made it finds in its scope. One for another server has no
  /// topic here and is dropped.
  void notifyServerChanged(String serverId) {
    if (serverId != _serverId) return;
    _topic?.send(ServerEvent.changed, const {});
  }

  void _teardown() {
    final topic = _topic;
    _topic = null;
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
