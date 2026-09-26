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
class VoiceBroadcast {
  /// The local user, whose location we're the only one who can report.
  final String userId;

  /// The authoritative roster, `{userId: channelId}`, or null if it can't be
  /// fetched right now — a failed snapshot is survivable, we just start from
  /// what the deltas tell us.
  final Future<Map<String, String>?> Function() fetchRoster;

  /// [locations] moved.
  final void Function() onChanged;

  RealtimeLease? _topic;
  Map<String, String> _locations;
  bool _subscribed = false;

  /// Where we last told everyone we are. Held separately from the map because
  /// broadcast doesn't echo to the sender, so our own entry never arrives — and
  /// "we've said nothing yet" is not the same as "we said we're nowhere".
  String? _announced;
  bool _hasAnnounced = false;

  /// Everyone whose own broadcast reached us since the in-flight snapshot was
  /// requested. They outrank it; see [VoiceLocations.mergeSnapshot].
  final Set<String> _heard = {};
  int _epoch = 0;
  bool _disposed = false;

  /// [initial] carries the last known map through a reconnect, so the channel
  /// list doesn't blink empty while the replacement snapshot is in flight.
  VoiceBroadcast({
    required ServerRealtime realtime,
    required Server server,
    required this.userId,
    required this.fetchRoster,
    required this.onChanged,
    Map<String, String> initial = const {},
  }) : _locations = initial {
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
      },
    )?..onBroadcast(VoiceLocations.event, _onDelta);
  }

  /// Where each member is, the local user included if they've been heard about.
  Map<String, String> get locations => _locations;

  /// Tell everyone we're now in [channelId], or nowhere when it's null.
  ///
  /// Repeating ourselves is dropped: LiveKit emits state far more often than it
  /// changes rooms, and every one of those would otherwise be a message to the
  /// whole server.
  void announce(String? channelId) {
    if (_hasAnnounced && channelId == _announced) return;
    _announced = channelId;
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
      VoiceLocations.encode(userId: userId, channelId: _announced),
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
    onChanged();
  }

  Future<void> _snapshot() async {
    final epoch = ++_epoch;
    _heard.clear();
    final roster = await fetchRoster();
    // A newer snapshot started while this one was out, or we were torn down.
    if (roster == null || _disposed || epoch != _epoch) return;
    _locations = VoiceLocations.mergeSnapshot(
      roster,
      current: _locations,
      heard: _heard,
    );
    onChanged();
  }

  Future<void> dispose() async {
    _disposed = true;
    final topic = _topic;
    _topic = null;
    await topic?.release();
  }
}
