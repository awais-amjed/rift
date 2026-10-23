import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart'
    show RemoteParticipant, TrackSource;
import 'package:supabase/supabase.dart';

import '../../../data/apis/voice_api.dart';
import '../../../data/classes/equality_props.dart';
import '../../../data/classes/region_load.dart';
import '../../../data/classes/server.dart';
import '../../../data/participant_identity.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/voice_region_probe.dart';
import '../../helper_methods.dart';
import '../../services/call_start_times.dart';
import '../../services/presence_ration.dart';
import '../../services/server_realtime.dart';
import '../../services/share_presence.dart';
import '../../services/steady_clock.dart';
import '../../services/voice_broadcast.dart';
import '../../services/voice_locations.dart';
import '../livekit/livekit_cubit.dart';

part 'channel_presence_location.dart';
part 'channel_presence_room.dart';
part 'channel_presence_state.dart';
part 'channel_presence_tracking.dart';

/// Who is online on one server, and who is in which voice channel.
///
/// Each server's context holds one (`ServerContext`), and holding it is what
/// keeps us there: our presence entry, and the location our call is announced
/// at. The call holds its server's while its member reads another, so nobody
/// there sees us leave a call we are still talking in, and the server being
/// read is never told we are in a channel it does not have.
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
    with _PresenceTrackingMixin, _RoomPeopleMixin, _VoiceLocationMixin {
  @override
  final SessionRepository _session;
  @override
  final LiveKitCubit _livekitCubit;

  /// The server this is about.
  final String _serverId;
  @override
  final VoiceRegionProbe _probe;

  StreamSubscription<void>? _serverSub;
  StreamSubscription<LiveKitState>? _lkSub;

  /// The presence topic on the server's shared connection. [_channel] is its
  /// join, for tracking and reading who is there — read through the lease
  /// every time, because a join refused under an expired token is replaced
  /// by a fresh channel once the token is renewed.
  RealtimeLease? _presenceTopic;
  @override
  RealtimeChannel? get _channel => _presenceTopic?.channel;
  @override
  VoiceBroadcast? _voice;
  @override
  String? _currentServerId;
  @override
  String? _currentUserId;
  @override
  bool _subscribed = false;

  /// Display names by user id, straight from the presence payload. The only
  /// place a name for someone in a voice channel comes from, and the reason
  /// "online" and "named" are the same set.
  Map<String, String> _names = const {};
  Set<String> _online = const {};

  /// What has answered since the server was opened — see
  /// [ChannelPresenceState.onlineKnown]. Kept through a rebuild, like the
  /// state it vouches for.
  bool _onlineKnown = false;
  bool _rosterRead = false;

  /// When the server was opened, for the log line that says how long
  /// presence took to answer ([_syncPresence]).
  DateTime? _openedAt;

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
    required LiveKitCubit livekitCubit,
    required SessionRepository session,
    required String serverId,
  }) : _session = session,
       _livekitCubit = livekitCubit,
       _serverId = serverId,
       _probe = session.regionProbe,
       super(const ChannelPresenceState()) {
    _serverSub = session.changes.listen((_) => _onServerChanged());
    _lkSub = livekitCubit.stream.listen((_) {
      _announceLocation();
      _onOwnChannel();
      _onRoomPeople();
    });
    // Bootstrap with current state
    _onServerChanged();
  }

  // ── Server changes ───────────────────────────────────────────────────────

  /// This server's own row, for the one it is about.
  @override
  Server? get _server => _session.serverById(_serverId);

  Future<void> _onServerChanged() async {
    // A server that has banned us refuses its presence topic, so it is no
    // server here until the ban is lifted.
    final server = _server?.admitsUs == true ? _server : null;
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
    Set<String> sharing = const {},
  }) {
    _currentServerId = server.id;
    _currentUserId = server.user?.id;
    _subscribed = false;
    _openedAt ??= DateTime.now();
    _startTrackingSession();
    final realtime = _session.realtime;
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
        initialSharing: sharing,
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
      _onlineKnown = false;
      _rosterRead = false;
      _openedAt = null;
      _starts = const CallStartTimes();
      _regionLoad = const {};
      emit(const ChannelPresenceState());
    }
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
    final server = _server;
    if (server == null || server.supabaseKey == null || !server.admitsUs) {
      return;
    }

    final locations = _voice?.locations ?? const <String, String>{};
    final sharing = _voice?.sharing ?? const <String>{};
    final epoch = ++_connectEpoch;
    await _disconnectPresence(keepState: true);
    if (isClosed || epoch != _connectEpoch) return;
    _connectPresence(server, locations: locations, sharing: sharing);
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
    if (!_onlineKnown && _openedAt != null) {
      // The wait the member list shows dots for, from opening the server to
      // the first answer: the joins' own lines say which part of it they were.
      final waited = DateTime.now().difference(_openedAt!).inMilliseconds;
      HelperMethods.printDebug('Presence: first answer after $waited ms');
    }
    _onlineKnown = true;
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
    final own =
        lk.connectionState == LiveKitConnectionState.connected &&
            lk.currentServerId == _currentServerId
        ? lk.currentChannelId
        : null;
    if (own == _ownChannel) return;
    _ownChannel = own;
    _emit();
  }

  /// Joins the two transports into the one picture the UI reads.
  @override
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
          excluding: _server?.user?.id,
        ).entries)
          if (entry.value.isNotEmpty) entry.key,
        ?_ownChannel,
      };
      _starts = _starts.update(occupied, SteadyClock.now());
    }
    final byChannel = VoiceLocations.rosters(
      locations: _voice?.locations ?? const {},
      online: _online,
      // Our own channel is drawn from live LiveKit participants; without this
      // we'd be listed twice in the call we're actually in.
      excluding: _server?.user?.id,
    );

    if (_voice?.rosterRead ?? false) _rosterRead = true;

    final sharing = _voice?.sharing ?? const <String>{};
    final rosters = <String, List<PresenceUser>>{};
    for (final entry in byChannel.entries) {
      rosters[entry.key] = [
        for (final userId in entry.value)
          if (_names[userId] case final name?)
            PresenceUser(
              userId: userId,
              displayName: name,
              isSharingScreen: sharing.contains(userId),
            ),
      ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    emit(
      ChannelPresenceState(
        channelPresence: rosters,
        onlineUserIds: _online,
        callStartedAt: _starts.started,
        regionLoad: _regionLoad,
        onlineKnown: _onlineKnown,
        voiceKnown: _onlineKnown && _rosterRead,
      ),
    );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _lkSub?.cancel();
    _rebuildTimer?.cancel();
    // Held by a call that has just ended, the context can close before the
    // call's own "nowhere" reaches us, and everybody here would see us in
    // the channel until presence gave up on us. Said once; a place already
    // said is not said again.
    _voice?.announce(null);
    await _disconnectPresence();
    return super.close();
  }
}
