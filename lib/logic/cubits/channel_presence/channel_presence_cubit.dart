import 'dart:async';

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

  const ChannelPresenceState({this.channelPresence = const {}});

  List<PresenceUser> usersIn(String channelId) =>
      channelPresence[channelId] ?? const [];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Maintains Supabase Realtime Presence for the selected server.
/// Automatically tracks/untracks the local user based on LiveKit connection
/// state — no changes needed in LiveKitCubit.
class ChannelPresenceCubit extends Cubit<ChannelPresenceState> {
  final ServerCubit _serverCubit;
  final LiveKitCubit _livekitCubit;

  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<LiveKitState>? _lkSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _currentServerId;
  LiveKitConnectionState? _lastLkConnectionState;

  ChannelPresenceCubit({
    required ServerCubit serverCubit,
    required LiveKitCubit livekitCubit,
  })  : _serverCubit = serverCubit,
        _livekitCubit = livekitCubit,
        super(const ChannelPresenceState()) {
    _serverSub = serverCubit.stream.listen(_onServerChanged);
    _lkSub = livekitCubit.stream.listen(_onLiveKitChanged);
    // Bootstrap with current state
    _onServerChanged(serverCubit.state);
    _lastLkConnectionState = livekitCubit.state.connectionState;
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
    _client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _channel = _client!.channel('presence:${server.id}');

    _channel!
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((status, [err]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            final lkState = _livekitCubit.state;
            if (lkState.connectionState == LiveKitConnectionState.connected &&
                lkState.currentChannelId != null) {
              final user = _serverCubit.state.selectedServer?.user;
              if (user != null) {
                await _track(
                  channelId: lkState.currentChannelId!,
                  userId: user.id,
                  displayName: user.displayName,
                );
              }
            }
          }
        });
  }

  Future<void> _disconnectPresence() async {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    _currentServerId = null;
    try {
      await channel?.untrack();
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
    if (!isClosed) emit(const ChannelPresenceState());
  }

  // ── LiveKit state → track / untrack ─────────────────────────────────────

  void _onLiveKitChanged(LiveKitState lkState) {
    final prev = _lastLkConnectionState;
    _lastLkConnectionState = lkState.connectionState;

    final justConnected =
        lkState.connectionState == LiveKitConnectionState.connected &&
            prev != LiveKitConnectionState.connected;

    final justDisconnected =
        lkState.connectionState == LiveKitConnectionState.disconnected &&
            prev == LiveKitConnectionState.connected;

    if (justConnected && lkState.currentChannelId != null) {
      final user = _serverCubit.state.selectedServer?.user;
      if (user != null) {
        _track(
          channelId: lkState.currentChannelId!,
          userId: user.id,
          displayName: user.displayName,
        );
      }
    } else if (justDisconnected) {
      _untrack();
    }
  }

  Future<void> _track({
    required String channelId,
    required String userId,
    required String displayName,
  }) async {
    try {
      await _channel?.track({
        'channelId': channelId,
        'userId': userId,
        'displayName': displayName,
      });
    } catch (_) {}
  }

  Future<void> _untrack() async {
    try {
      await _channel?.untrack();
    } catch (_) {}
  }

  void _syncPresence() {
    if (isClosed) return;
    final entries = _channel?.presenceState() ?? <SinglePresenceState>[];

    final Map<String, List<PresenceUser>> result = {};
    for (final entry in entries) {
      for (final presence in entry.presences) {
        final payload = presence.payload;
        final channelId = payload['channelId'] as String?;
        final userId = payload['userId'] as String?;
        final displayName = payload['displayName'] as String?;
        if (channelId == null || userId == null || displayName == null) {
          continue;
        }
        result.putIfAbsent(channelId, () => []).add(
              PresenceUser(userId: userId, displayName: displayName),
            );
      }
    }

    emit(ChannelPresenceState(channelPresence: result));
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

