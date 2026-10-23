part of 'channel_presence_cubit.dart';

/// Where we are, said to the server, and where everybody else is, read from
/// LiveKit: the voice channel each person is in, when each call began, and
/// how busy each region is.
mixin _VoiceLocationMixin on Cubit<ChannelPresenceState> {
  SessionRepository get _session;
  LiveKitCubit get _livekitCubit;
  VoiceBroadcast? get _voice;
  VoiceRegionProbe get _probe;
  String? get _currentServerId;
  String? get _currentUserId;

  /// Draws the joined state of presence and locations.
  void _emit();

  /// When each occupied channel's call began — see [CallStartTimes].
  CallStartTimes _starts = const CallStartTimes();

  /// How busy each region was at the last roster read — see
  /// [ChannelPresenceState.regionLoad].
  Map<String, RegionLoad> _regionLoad = const {};

  /// The call's [LiveKitState.arrivals] when we last said where we are.
  int? _announcedArrivals;

  /// Tells the server where we are now, if it isn't where we last said, or
  /// again when the call has just landed in its room.
  ///
  /// Everyone else reads the roster from LiveKit now and then, and replaces
  /// what they had with it. A read taken while we were between rooms — a
  /// move still connecting, or a connection that gave out and is coming
  /// back — leaves us out, and they take us out of the channel. Nothing they
  /// do afterwards puts us back, and we used to say nothing more: the
  /// channel had not changed. One person sat in a call for everyone else to
  /// see only from inside it (Oct 21 2026).
  void _announceLocation() {
    // A move says where it is going the moment it starts. Waiting for the new
    // room meant waiting for the old one to close, a token, the key and the
    // connect — half a second on a local server, more on a real one — and
    // until then everyone else drew us in the channel we had left. A join
    // that then fails ends in `error`, which says "nowhere" like leaving
    // does. A DM call connects with no channel, and so leaves the one it
    // came from straight away too.
    final serverId = _currentServerId;
    final userId = _currentUserId;
    if (serverId == null || userId == null) return;
    final place = _placeOn(serverId, userId);
    final arrivals = _livekitCubit.state.arrivals;
    final arrived =
        place.channelId != null &&
        _livekitCubit.state.connectionState ==
            LiveKitConnectionState.connected &&
        arrivals != _announcedArrivals;
    if (arrived) _announcedArrivals = arrivals;
    _voice?.announce(place.channelId, sharing: place.sharing, again: arrived);
  }

  ({String? channelId, bool sharing}) _placeOn(String serverId, String userId) {
    final lkState = _livekitCubit.state;
    // Only the call's own server hears where it is. Read on another, its
    // channel is one that server does not have.
    final channelId = lkState.currentServerId != serverId
        ? null
        : switch (lkState.connectionState) {
            LiveKitConnectionState.connecting ||
            LiveKitConnectionState.connected => lkState.currentChannelId,
            _ => null,
          };
    return (
      channelId: channelId,
      // A desktop's screen is a connection of its own, which comes back to
      // us like anybody else's; a phone's rides our own. The sweep the
      // roster rows use finds either.
      sharing:
          channelId != null &&
          sharePresenceOf(
            lkState.participants,
            identityOf: (p) => p.identity,
            publishesScreenshare: (p) => p.videoTrackPublications.any(
              (pub) => pub.source == TrackSource.screenShareVideo,
            ),
          ).sharesScreen(userId),
    );
  }

  /// The authoritative roster from LiveKit, or null when it can't be had.
  Future<({Map<String, String> locations, Set<String>? sharing})?>
  _fetchRoster() async {
    // The subscribe that asked for this can land after a rebuild moved on.
    final asked = _currentServerId;
    if (asked == null) return null;
    final response = await VoiceApi(_session.on(asked)).voiceRoster();
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
            entry.key as String: SteadyClock.fromWall(
              DateTime.fromMillisecondsSinceEpoch((entry.value as num).toInt()),
            ),
      }, SteadyClock.now());
    }
    final roster = data['roster'];
    if (roster is! Map) return null;
    // Who has a screen up. Absent from a server older than the list, which
    // is not the same as nobody sharing.
    final sharing = data['sharing'];
    return (
      locations: {
        for (final entry in roster.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      },
      sharing: sharing is List ? sharing.whereType<String>().toSet() : null,
    );
  }

  /// Ask how busy each region is now, for a picker about to open.
  ///
  /// The roster is read when presence connects, not on a timer, so what this
  /// holds can be minutes old by the time a manager looks.
  Future<void> refreshRegionLoad() async {
    final asked = _currentServerId;
    if (asked == null) return;
    final response = await VoiceApi(_session.on(asked)).voiceRoster();
    if (response.success) _landRegionLoad(asked);
  }

  /// Take the reading [asked]'s roster read left in the probe — unless the
  /// server went away while it was out.
  void _landRegionLoad(String? asked) {
    if (isClosed || asked == null || asked != _currentServerId) return;
    _regionLoad = _probe.loadOf(asked);
    _emit();
  }
}
