import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/apis/voice_api.dart';
import '../../../data/classes/equality_props.dart';
import '../../../data/classes/region_load.dart';
import '../../../data/classes/server.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/voice_region_probe.dart';
import '../../services/call_start_times.dart';
import '../../services/presence_ration.dart';
import '../../services/server_realtime.dart';
import '../../services/voice_broadcast.dart';
import '../../services/voice_locations.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'channel_presence_state.dart';
part 'channel_presence_tracking.dart';

/// Who is online on the selected server, and who is in which voice channel.
///
/// Two questions, and — the point of this class — **two transports**, because
/// they change at completely different rates.
///
/// **Online** rides Realtime Presence, which allows one client only five
/// publishes per 30 seconds and kills the channel on the sixth (see
/// [_PresenceTrackingMixin] for what that failure looks like from in here). A
/// budget that small is only safe for something that doesn't move, so the entry
/// says `{userId, displayName}` and is published once per connection. What it
/// buys in return is the thing nothing else here can do: **when the socket dies
/// the entry dies with it**, and every other member is told.
///
/// **Location** rides an ordinary broadcast on `voice:<serverId>`, one message
/// per hop, because people change voice channels constantly and broadcast has
/// no per-client window. See [VoiceBroadcast].
///
/// The two are joined in [_emit]: a location is only drawn while presence still
/// vouches for the person it belongs to. A client that crashes mid-call never
/// gets to say it left, and doesn't have to — it drops off presence, and its
/// last known location stops being believed.
class ChannelPresenceCubit extends Cubit<ChannelPresenceState>
    with _PresenceTrackingMixin {
  @override
  final ServerCubit _serverCubit;
  final LiveKitCubit _livekitCubit;
  final VoiceApi _voiceApi;
  final VoiceRegionProbe _probe;

  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<LiveKitState>? _lkSub;

  /// The presence topic on the server's shared connection. [_channel] is its
  /// join, for tracking and reading who is there — read through the lease
  /// every time, because a join refused under an expired token is replaced
  /// by a fresh channel once the token is renewed.
  RealtimeLease? _presenceTopic;
  @override
  RealtimeChannel? get _channel => _presenceTopic?.channel;
  VoiceBroadcast? _voice;
  String? _currentServerId;
  String? _currentUserId;
  @override
  bool _subscribed = false;

  /// Display names by user id, straight from the presence payload. The only
  /// place a name for someone in a voice channel comes from, and the reason
  /// "online" and "named" are the same set.
  Map<String, String> _names = const {};
  Set<String> _online = const {};

  /// When each occupied channel's call began — see [CallStartTimes].
  CallStartTimes _starts = const CallStartTimes();

  /// How busy each region was at the last roster read — see
  /// [ChannelPresenceState.regionLoad].
  Map<String, RegionLoad> _regionLoad = const {};

  /// The channel our own call is in, so a join or a leave re-times the
  /// sidebar without redrawing it on every LiveKit tick.
  String? _ownChannel;

  /// Bumped by everything that tears the channels down and builds them again,
  /// so a connect that was overtaken while awaiting the teardown gives up.
  int _connectEpoch = 0;

  /// Set while we're taking the channel down on purpose, so the `closed` status
  /// that follows isn't mistaken for the server hanging up on us.
  bool _tearingDown = false;

  ChannelPresenceCubit({
    required ServerCubit serverCubit,
    required LiveKitCubit livekitCubit,
    required SessionRepository session,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       _voiceApi = VoiceApi(session: session),
       _probe = session.regionProbe,
       super(const ChannelPresenceState()) {
    _serverSub = serverCubit.stream.listen(_onServerChanged);
    _lkSub = livekitCubit.stream.listen((_) {
      _announceLocation();
      _onOwnChannel();
    });
    // Bootstrap with current state
    _onServerChanged(serverCubit.state);
  }

  // ── Server changes ───────────────────────────────────────────────────────

  Future<void> _onServerChanged(ServerState serverState) async {
    final server = serverState.selectedServer;
    // The user arriving matters as much as the server doing: we connect before
    // registration finishes on first launch, and there is nobody to announce
    // until it has.
    if (server?.id == _currentServerId && server?.user?.id == _currentUserId) {
      return;
    }
    final epoch = ++_connectEpoch;
    await _disconnectPresence();
    // Two selections in quick succession both wait here, and without this the
    // loser would come back and build a second client over the winner's.
    if (isClosed || epoch != _connectEpoch) return;
    if (server != null && server.supabaseKey != null) {
      _connectPresence(server);
    }
  }

  void _connectPresence(
    Server server, {
    Map<String, String> locations = const {},
  }) {
    _currentServerId = server.id;
    _currentUserId = server.user?.id;
    _subscribed = false;
    _startTrackingSession();
    final realtime = _serverCubit.realtime;
    final topic = realtime.join(
      server,
      'presence:${server.id}',
      setUp: (channel, dispatch) => channel
          .onPresenceSync((_) => dispatch('presence', const {}))
          .onPresenceJoin((_) => dispatch('presence', const {}))
          .onPresenceLeave((_) => dispatch('presence', const {})),
      onStatus: _onPresenceStatus,
    );
    _presenceTopic = topic?..on('presence', (_) => _syncPresence());

    final userId = server.user?.id;
    if (userId != null) {
      _voice = VoiceBroadcast(
        realtime: realtime,
        server: server,
        userId: userId,
        fetchRoster: _fetchRoster,
        onChanged: _emit,
        initial: locations,
      );
      _announceLocation();
    }
  }

  void _onPresenceStatus(RealtimeSubscribeStatus status) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      // A realtime reconnect drops the server-side entry and rejoining does not
      // bring it back, so every subscribe re-establishes it.
      _subscribed = true;
      _rebuildAttempt = 0;
      _tracked = false;
      _ensureTracked();
    } else {
      _subscribed = false;
      // Closed, errored or timed out. Nothing rejoins a dead presence channel
      // on its own — this is the only notice we get.
      if (!_tearingDown) _scheduleRebuild();
    }
  }

  /// Tears both channels down. [keepState] holds on to what we last knew during
  /// a rebuild, so the sidebar doesn't blink empty on the way through.
  ///
  /// Deliberately does **not** untrack. An untrack is itself a presence event,
  /// it blocks for the full socket timeout when the channel is already dead
  /// (which is exactly when we rebuild), and it buys nothing: closing the
  /// socket drops the entry and tells everyone anyway.
  Future<void> _disconnectPresence({bool keepState = false}) async {
    _tearingDown = true;
    final topic = _presenceTopic;
    final voice = _voice;
    _presenceTopic = null;
    _voice = null;
    _currentServerId = null;
    _currentUserId = null;
    _subscribed = false;
    _stopTracking();
    await voice?.dispose();
    await topic?.release();
    _tearingDown = false;
    if (!isClosed && !keepState) {
      _names = const {};
      _online = const {};
      _starts = const CallStartTimes();
      _regionLoad = const {};
      emit(const ChannelPresenceState());
    }
  }

  // ── Location ─────────────────────────────────────────────────────────────

  /// Tells the server where we are now, if it isn't where we last said.
  void _announceLocation() {
    final lkState = _livekitCubit.state;
    // A move says where it is going the moment it starts. Waiting for the new
    // room meant waiting for the old one to close, a token, the key and the
    // connect — half a second on a local server, more on a real one — and
    // until then everyone else drew us in the channel we had left. A join
    // that then fails ends in `error`, which says "nowhere" like leaving
    // does. A DM call connects with no channel, and so leaves the one it
    // came from straight away too.
    _voice?.announce(switch (lkState.connectionState) {
      LiveKitConnectionState.connecting ||
      LiveKitConnectionState.connected => lkState.currentChannelId,
      _ => null,
    });
  }

  /// The authoritative roster from LiveKit, or null when it can't be had.
  Future<Map<String, String>?> _fetchRoster() async {
    // The subscribe that asked for this can land after the selection moved on.
    if (_serverCubit.state.selectedServer == null) return null;
    final asked = _currentServerId;
    final response = await _voiceApi.voiceRoster();
    if (!response.success) return null;
    _landRegionLoad(asked);
    final data = response.data;
    if (data is! Map) return null;
    // When the calls already running began. Kept aside until presence shows
    // each channel occupied; see [CallStartTimes].
    if (data['started'] case final Map started) {
      _starts = _starts.withServer({
        for (final entry in started.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: DateTime.fromMillisecondsSinceEpoch(
              (entry.value as num).toInt(),
            ),
      }, DateTime.now());
    }
    final roster = data['roster'];
    if (roster is! Map) return null;
    return {
      for (final entry in roster.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// Ask how busy each region is now, for a picker about to open.
  ///
  /// The roster is read when presence connects, not on a timer, so what this
  /// holds can be minutes old by the time a manager looks.
  Future<void> refreshRegionLoad() async {
    final asked = _currentServerId;
    if (asked == null) return;
    final response = await _voiceApi.voiceRoster();
    if (response.success) _landRegionLoad(asked);
  }

  /// Take the reading [asked]'s roster read left in the probe — unless the
  /// selection moved on while it was out, when it would put one server's
  /// numbers beside another's regions.
  void _landRegionLoad(String? asked) {
    if (isClosed || asked == null || asked != _currentServerId) return;
    _regionLoad = _probe.loadOf(asked);
    _emit();
  }

  // ── Presence ─────────────────────────────────────────────────────────────

  /// Throws both channels away and builds them again.
  ///
  /// The only cure for a dropped presence entry: the ration and the channel
  /// process both belong to the join, so a new one starts clean where the old
  /// one silently could not. The server's shared connection stays up.
  @override
  Future<void> _rebuild() async {
    if (isClosed) return;
    final server = _serverCubit.state.selectedServer;
    if (server == null || server.supabaseKey == null) return;

    final locations = _voice?.locations ?? const <String, String>{};
    final epoch = ++_connectEpoch;
    await _disconnectPresence(keepState: true);
    if (isClosed || epoch != _connectEpoch) return;
    _connectPresence(server, locations: locations);
  }

  void _syncPresence() {
    if (isClosed) return;
    final entries = _channel?.presenceState() ?? <SinglePresenceState>[];

    final names = <String, String>{};
    for (final entry in entries) {
      for (final presence in entry.presences) {
        final payload = presence.payload;
        final userId = payload['userId'] as String?;
        final displayName = payload['displayName'] as String?;
        if (userId == null || displayName == null) continue;
        names[userId] = displayName;
      }
    }
    _names = names;
    // The same set when nobody came or went, so a reader can select it by
    // identity: the member list does, and every move between voice channels
    // would otherwise redraw it.
    final online = names.keys.toSet();
    if (!setEquals(online, _online)) _online = online;
    _emit();
    _healTracking(_online);
  }

  /// Our own call started, ended or moved: that changes which channels are
  /// occupied, and presence leaves us out of its own count.
  void _onOwnChannel() {
    final lk = _livekitCubit.state;
    final own = lk.connectionState == LiveKitConnectionState.connected
        ? lk.currentChannelId
        : null;
    if (own == _ownChannel) return;
    _ownChannel = own;
    _emit();
  }

  /// Joins the two transports into the one picture the UI reads.
  void _emit() {
    if (isClosed) return;
    // Mid-rebuild there are no locations to read, and treating that as every
    // channel emptying would restart every timer.
    if (_voice != null) {
      // Our own place comes from our own call, never from the locations: a
      // roster can seed us somewhere a previous session of ours died, and
      // our own "nowhere" goes to everyone else, not back to us.
      final occupied = {
        for (final entry in VoiceLocations.rosters(
          locations: _voice!.locations,
          online: _online,
          excluding: _serverCubit.state.selectedServer?.user?.id,
        ).entries)
          if (entry.value.isNotEmpty) entry.key,
        ?_ownChannel,
      };
      _starts = _starts.update(occupied, DateTime.now());
    }
    final byChannel = VoiceLocations.rosters(
      locations: _voice?.locations ?? const {},
      online: _online,
      // Our own channel is drawn from live LiveKit participants; without this
      // we'd be listed twice in the call we're actually in.
      excluding: _serverCubit.state.selectedServer?.user?.id,
    );

    final rosters = <String, List<PresenceUser>>{};
    for (final entry in byChannel.entries) {
      rosters[entry.key] = [
        for (final userId in entry.value)
          if (_names[userId] case final name?)
            PresenceUser(userId: userId, displayName: name),
      ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    emit(
      ChannelPresenceState(
        channelPresence: rosters,
        onlineUserIds: _online,
        callStartedAt: _starts.started,
        regionLoad: _regionLoad,
      ),
    );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _lkSub?.cancel();
    _rebuildTimer?.cancel();
    await _disconnectPresence();
    return super.close();
  }
}
