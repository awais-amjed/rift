import 'dart:async';

import 'package:supabase/supabase.dart';

import '../../data/classes/server.dart';
import 'server_realtime.dart';
import 'voice_locations.dart';

/// The live "who is in which voice channel" map for one server, over Realtime
/// broadcast.
///
/// One message per channel change, in either direction. Broadcast has no
/// per-client window the way presence does, which is the entire reason this
/// isn't part of the presence payload — see [VoiceLocations] for the split and
/// why presence still has a job.
///
/// Broadcast is also stateless: it carries changes, never the current picture.
/// So on subscribe we fetch a snapshot from LiveKit ([fetchRoster]) and say
/// again where we are, because a client that has just connected has missed
/// every change so far and everyone else has missed ours.
///
/// Who has a screen up rides the same messages ([sharing]): it changes about
/// as often as a location does, and only ever for somebody in a call.
class VoiceBroadcast {
  /// The local user, whose location we're the only one who can report.
  final String userId;

  /// The authoritative roster, `{userId: channelId}`, and who is sharing a
  /// screen (null from a server that does not say), or null if it can't be
  /// fetched right now — a failed snapshot is survivable, we just start from
  /// what the deltas tell us.
  final Future<({Map<String, String> locations, Set<String>? sharing})?>
  Function()
  fetchRoster;

  /// [locations] moved.
  final void Function() onChanged;

  RealtimeLease? _topic;
  Map<String, String> _locations;
  Set<String> _sharing;
  bool _subscribed = false;

  /// Where we last told everyone we are. Held separately from the map because
  /// broadcast doesn't echo to the sender, so our own entry never arrives — and
  /// "we've said nothing yet" is not the same as "we said we're nowhere".
  String? _announced;
  bool _announcedSharing = false;
  bool _hasAnnounced = false;

  /// Everyone whose own broadcast reached us since the in-flight snapshot was
  /// requested. They outrank it; see [VoiceLocations.mergeSnapshot].
  final Set<String> _heard = {};
  int _epoch = 0;
  bool _disposed = false;

  /// Whether a roster read has answered, or failed, since this was built.
  /// Until then an empty channel may only be one we have not heard about.
  bool get rosterRead => _rosterRead;
  bool _rosterRead = false;

  /// The one second look at the roster — see [recheckAfter].
  Timer? _recheck;

  /// A look asked for by [recheckSoon], pending.
  Timer? _soon;

  /// How long after joining to ask LiveKit again.
  ///
  /// A killed app stays in LiveKit's room until its departure timeout, about
  /// twenty seconds, and a roster read inside that window lists a session
  /// that is already dead. Nothing that session says afterwards can correct
  /// it — it says nothing — so a client that joined in that window drew the
  /// ghost until its next reconnect. One more read, after the window, does.
  static const recheckAfter = Duration(seconds: 30);

  /// How long [recheckSoon] waits: long enough for LiveKit to have let the
  /// departed go, so the read does not put them straight back.
  static const recheckSoonAfter = Duration(seconds: 3);

  /// [initial] carries the last known map through a reconnect, so the channel
  /// list doesn't blink empty while the replacement snapshot is in flight.
  VoiceBroadcast({
    required ServerRealtime realtime,
    required Server server,
    required this.userId,
    required this.fetchRoster,
    required this.onChanged,
    Map<String, String> initial = const {},
    Set<String> initialSharing = const {},
  }) : _locations = initial,
       _sharing = initialSharing {
    _topic = realtime.join(
      server,
      VoiceLocations.topic(server.id),
      onStatus: (status) {
        if (status != RealtimeSubscribeStatus.subscribed || _disposed) return;
        _subscribed = true;
        // Everyone else kept our last delta while we were away, but it may be
        // stale — and if we joined a channel with the topic down, they never
        // heard it at all. That holds on the very first join too: an app that
        // was killed mid-call never said it left, and everyone else still
        // draws it in that call once its new session comes online. One
        // "nowhere" per start is what clears that ghost.
        if (_hasAnnounced) _send();
        unawaited(_snapshot());
        _recheck ??= Timer(recheckAfter, () {
          if (!_disposed) unawaited(_snapshot());
        });
      },
    )?..onBroadcast(VoiceLocations.event, _onDelta);
    // Read now as well, not only once the topic is joined. The read is an
    // ordinary request, and a server answers a socket's joins one at a time,
    // so the voice topic can be seconds behind the others; the sidebar had
    // no calls to draw until it was. The read after the join still comes,
    // for whatever moved before the deltas could reach us.
    if (_topic != null) unawaited(_snapshot());
  }

  /// Read the roster again shortly: someone left our call and never said so
  /// (`VoiceLocations.leftSilently`). Several departures in a row share one
  /// read.
  void recheckSoon() {
    if (_disposed || _soon != null) return;
    _soon = Timer(recheckSoonAfter, () {
      _soon = null;
      if (!_disposed) unawaited(_snapshot());
    });
  }

  /// Where each member is, the local user included if they've been heard about.
  Map<String, String> get locations => _locations;

  /// Who has a screen up, by user id.
  Set<String> get sharing => _sharing;

  /// Tell everyone we're now in [channelId], or nowhere when it's null, and
  /// whether we have a screen up there.
  ///
  /// Repeating ourselves is dropped: LiveKit emits state far more often than it
  /// changes rooms, and every one of those would otherwise be a message to the
  /// whole server. [again] says it anyway, for a place everyone may have
  /// stopped believing: we have just come back into a room we never left.
  void announce(String? channelId, {bool sharing = false, bool again = false}) {
    sharing = sharing && channelId != null;
    if (!again &&
        _hasAnnounced &&
        channelId == _announced &&
        sharing == _announcedSharing) {
      return;
    }
    _announced = channelId;
    _announcedSharing = sharing;
    _hasAnnounced = true;
    _send();
  }

  void _send() {
    // Before the join, `sendBroadcastMessage` silently falls back to an HTTP
    // POST. It would work, but the subscribe callback is a few milliseconds
    // away and re-sends this anyway.
    if (!_subscribed) return;
    _topic?.send(
      VoiceLocations.event,
      VoiceLocations.encode(
        userId: userId,
        channelId: _announced,
        sharing: _announcedSharing,
      ),
    );
  }

  void _onDelta(Map<String, dynamic> message) {
    if (_disposed) return;
    final delta = VoiceLocations.decode(message);
    if (delta == null) return;
    _heard.add(delta.userId);
    _locations = VoiceLocations.applyDelta(
      _locations,
      userId: delta.userId,
      channelId: delta.channelId,
    );
    _sharing = VoiceLocations.applySharing(
      _sharing,
      userId: delta.userId,
      channelId: delta.channelId,
      sharing: delta.sharing,
    );
    onChanged();
  }

  Future<void> _snapshot() async {
    final epoch = ++_epoch;
    _heard.clear();
    final roster = await fetchRoster();
    // A newer snapshot started while this one was out, or we were torn down.
    if (_disposed || epoch != _epoch) return;
    if (roster == null) {
      // Nothing more to wait for: the deltas are all there will be.
      if (!_rosterRead) {
        _rosterRead = true;
        onChanged();
      }
      return;
    }
    _rosterRead = true;
    _locations = VoiceLocations.mergeSnapshot(
      roster.locations,
      current: _locations,
      heard: _heard,
    );
    _sharing = VoiceLocations.mergeSharing(
      roster.sharing,
      current: _sharing,
      heard: _heard,
      locations: _locations,
    );
    onChanged();
  }

  Future<void> dispose() async {
    _disposed = true;
    _recheck?.cancel();
    _soon?.cancel();
    final topic = _topic;
    _topic = null;
    await topic?.release();
  }
}
