import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/server.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class PresenceUser {
  final String userId;
  final String displayName;

  const PresenceUser({required this.userId, required this.displayName});
}

// ── State ────────────────────────────────────────────────────────────────────

class ChannelPresenceState {
  /// Maps channelId → list of users currently in that channel.
  final Map<String, List<PresenceUser>> channelPresence;

  /// Everyone with the app open on this server, whether or not they're in a
  /// voice channel — including the local user. Drives the member sidebar's
  /// online/offline split.
  final Set<String> onlineUserIds;

  const ChannelPresenceState({
    this.channelPresence = const {},
    this.onlineUserIds = const {},
  });

  List<PresenceUser> usersIn(String channelId) =>
      channelPresence[channelId] ?? const [];

  /// The voice channel [userId] is in, or null if they're in none.
  ///
  /// Never answers for the local user — we're deliberately left out of the
  /// per-channel roster (see [_syncPresence]), so ask [LiveKitState] for
  /// yourself.
  String? channelOf(String userId) {
    for (final entry in channelPresence.entries) {
      if (entry.value.any((user) => user.userId == userId)) return entry.key;
    }
    return null;
  }

  bool isOnline(String userId) => onlineUserIds.contains(userId);
}

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Maintains Supabase Realtime Presence for the selected server.
///
/// The local user is tracked for as long as the server is selected, so
/// presence answers both questions the UI asks: *who is online here* (the
/// member sidebar) and *who is in which voice channel* (the channel list). The
/// tracked `channelId` is null while not in voice, and follows the LiveKit
/// connection otherwise — no changes needed in LiveKitCubit.
class ChannelPresenceCubit extends Cubit<ChannelPresenceState> {
  final ServerCubit _serverCubit;
  final LiveKitCubit _livekitCubit;

  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<LiveKitState>? _lkSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _currentServerId;
  bool _subscribed = false;

  /// Whether the local user is tracked at all, and the channel id in that
  /// entry (null while not in a voice channel). Both are needed: "tracked with
  /// no channel" and "not tracked" are different states, and collapsing them
  /// would re-track on every LiveKit event. Reconciled against LiveKit state so
  /// we never leak a stale entry — and against the presence state itself, since
  /// this pair is only ever our *belief* about what the server holds.
  bool _tracked = false;
  String? _trackedChannelId;

  /// Pending re-track after one didn't land. Long enough for a reconnecting
  /// socket to come back, short enough that nobody stays invisible.
  static const _retrackDelay = Duration(seconds: 2);
  Timer? _retrack;

  ChannelPresenceCubit({
    required ServerCubit serverCubit,
    required LiveKitCubit livekitCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       super(const ChannelPresenceState()) {
    _serverSub = serverCubit.stream.listen(_onServerChanged);
    _lkSub = livekitCubit.stream.listen((_) => _reconcileTracking());
    // Bootstrap with current state
    _onServerChanged(serverCubit.state);
  }

  // ── Server changes ───────────────────────────────────────────────────────

  Future<void> _onServerChanged(ServerState serverState) async {
    final server = serverState.selectedServer;
    if (server?.id == _currentServerId) return;
    await _disconnectPresence();
    if (server != null && server.supabaseKey != null) {
      _connectPresence(server);
    }
  }

  void _connectPresence(Server server) {
    _currentServerId = server.id;
    _tracked = false;
    _trackedChannelId = null;
    _subscribed = false;
    _client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _channel = _client!.channel('presence:${server.id}');

    _channel!
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((status, [err]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            // (Re)subscribed — re-establish our presence from scratch (a
            // realtime reconnect drops the server-side entry).
            _subscribed = true;
            _tracked = false;
            _trackedChannelId = null;
            _reconcileTracking();
          } else {
            _subscribed = false;
          }
        });
  }

  Future<void> _disconnectPresence() async {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    _currentServerId = null;
    _tracked = false;
    _trackedChannelId = null;
    _subscribed = false;
    _retrack?.cancel();
    _retrack = null;
    try {
      await channel?.untrack();
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
    if (!isClosed) emit(const ChannelPresenceState());
  }

  // ── LiveKit state → track / untrack ─────────────────────────────────────

  /// Brings the tracked presence in line with the live LiveKit state. We stay
  /// tracked the whole time the server is selected (that *is* being online);
  /// only the `channelId` in the entry follows the voice connection. Driven by
  /// connection state rather than transitions, so an error/network-drop path
  /// (connected → error → disconnected) still clears the channel.
  void _reconcileTracking() {
    // Only touch presence once the channel is actually subscribed.
    if (_channel == null || !_subscribed) return;

    final user = _serverCubit.state.selectedServer?.user;
    if (user == null) return;

    final lkState = _livekitCubit.state;
    final channelId =
        lkState.connectionState == LiveKitConnectionState.connected
        ? lkState.currentChannelId
        : null;

    if (_tracked && channelId == _trackedChannelId) return;

    _tracked = true;
    _trackedChannelId = channelId;
    _track(
      channelId: channelId,
      userId: user.id,
      displayName: user.displayName,
    );
  }

  /// Publishes our presence entry, and **checks that it landed**.
  ///
  /// A track made while the socket is reconnecting isn't sent — it goes into
  /// the channel's push buffer and quietly times out. This used to be ignored
  /// while `_tracked` had already been set to true, so the entry never existed
  /// and nothing ever tried again: the member vanished from everyone else's
  /// sidebar and channel list, permanently, while their own app carried on
  /// showing them in the call (that comes from LiveKit, not presence). Moving
  /// someone is exactly the moment to hit it — their client is tearing a
  /// WebRTC connection down and building another.
  Future<void> _track({
    required String? channelId,
    required String userId,
    required String displayName,
  }) async {
    ChannelResponse? result;
    try {
      result = await _channel?.track({
        // Absent while not in a voice channel — the entry still means online.
        'channelId': ?channelId,
        'userId': userId,
        'displayName': displayName,
      });
    } catch (_) {}
    if (result != ChannelResponse.ok) _retrackSoon();
  }

  /// Drops our belief that we're tracked and tries again shortly.
  ///
  /// The belief is the thing that has to go: [_reconcileTracking] returns early
  /// while it holds, so leaving it set is what turns one lost push into being
  /// invisible for the rest of the session.
  void _retrackSoon() {
    if (isClosed || _channel == null) return;
    _tracked = false;
    _trackedChannelId = null;
    _retrack?.cancel();
    _retrack = Timer(_retrackDelay, () {
      if (!isClosed) _reconcileTracking();
    });
  }

  /// Whether our own entry has gone missing from what the server is telling
  /// everyone, while we still think we published one.
  ///
  /// The sync is the truth and this pair of fields is only a guess, so any
  /// disagreement is ours to fix — whatever dropped the entry, and whether or
  /// not we were the ones who dropped it.
  @visibleForTesting
  static bool shouldRetrack({
    required bool tracked,
    required String? localUserId,
    required Set<String> onlineUserIds,
  }) => tracked && localUserId != null && !onlineUserIds.contains(localUserId);

  void _syncPresence() {
    if (isClosed) return;
    final entries = _channel?.presenceState() ?? <SinglePresenceState>[];

    // The local user is rendered from LiveKit participants in their selected
    // channel, never from presence — so exclude self here. This also means a
    // stale self-entry (e.g. before an untrack round-trips) can never show us
    // as "still in" a channel we've left.
    final localUserId = _serverCubit.state.selectedServer?.user?.id;

    final Map<String, List<PresenceUser>> result = {};
    final Set<String> online = {};
    for (final entry in entries) {
      for (final presence in entry.presences) {
        final payload = presence.payload;
        final channelId = payload['channelId'] as String?;
        final userId = payload['userId'] as String?;
        final displayName = payload['displayName'] as String?;
        if (userId == null || displayName == null) continue;

        // Online counts the local user — the sidebar lists you too.
        online.add(userId);

        // ...but the per-channel roster doesn't: the local user's own channel
        // is rendered from live LiveKit participants, so a stale self-entry
        // (before an untrack round-trips) can't show us where we no longer are.
        if (channelId == null || userId == localUserId) continue;
        result
            .putIfAbsent(channelId, () => [])
            .add(PresenceUser(userId: userId, displayName: displayName));
      }
    }

    emit(ChannelPresenceState(channelPresence: result, onlineUserIds: online));

    if (shouldRetrack(
      tracked: _tracked,
      localUserId: localUserId,
      onlineUserIds: online,
    )) {
      _retrackSoon();
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _lkSub?.cancel();
    await _disconnectPresence();
    return super.close();
  }
}
