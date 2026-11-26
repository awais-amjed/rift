import 'dart:async';

import '../../data/classes/server.dart';
import 'broadcast_payload.dart';
import 'ring_throttle.dart';
import 'server_realtime.dart';
import 'server_topics.dart';

/// A subscription to a server's key-sweep doorbell.
///
/// A `sweep` on the server's topic, rung whenever a client publishes a chat
/// key, heals somebody's keyring entry, or rotates a channel. It is a nudge to
/// go and look, which is what keeps it cheap enough to ring often.
///
/// A ring that announces keys already sealed names their channels
/// (`{"channels": [...]}`): a heal, a sweep's pass, a summon owed a key. Every
/// app on the server hears it, and only the ones showing or in one of those
/// channels have anything to read; the rest let it go. A ring that asks for
/// work — a member published a chat key, or waits for one — and the
/// database's own rings name nothing, and every app looks (found in the
/// call-count review, Nov 26: each heal cost every online app a sweep and a
/// read of the channel it had open, four requests in a call).
///
/// Extracted because there are two listeners with nothing else in common: the
/// open text channel wants to re-run its sweep, and a call in progress wants to
/// know its key rotated out from under it.
class KeySweepDoorbell {
  RealtimeLease? _lease;
  RingThrottle? _throttle;

  /// Whether this doorbell is currently listening.
  bool get isListening => _lease != null;

  /// Listen on [server], calling [onRing] each time somebody rings.
  ///
  /// Replaces any existing subscription, so it is safe to call again on a
  /// server change without leaking the previous one. Does nothing for a server
  /// with no anon key — there is nothing to connect with, and a call or a
  /// channel that works without the doorbell is better than one that fails
  /// because of it. The chat and a call in progress each hold one of these;
  /// [realtime] gives them the same join.
  ///
  /// Answered at most every two seconds ([RingThrottle]): any member may ring
  /// it, and each answer is a sweep's reads.
  ///
  /// [onRing] is handed the channels the rings since the last answer named,
  /// or null when any of them named none.
  void listen(
    ServerRealtime realtime,
    Server server,
    void Function(Set<String>? channels) onRing,
  ) {
    unawaited(stop());
    Set<String>? named = {};
    final throttle = _throttle = RingThrottle(() {
      final channels = named;
      named = {};
      onRing(channels);
    });
    _lease = realtime.join(server, ServerTopics.server(server.id))
      ?..onBroadcast(ServerEvent.sweep, (message) {
        final channels = BroadcastPayload.channelsOf(message);
        named = channels == null ? null : named?.union(channels);
        throttle.ring();
      });
  }

  /// Ring it, so other clients go and look — and anything else on this device
  /// listening to the same server.
  ///
  /// The second half is not a courtesy. A rotation is minted by whichever
  /// client's sweep wins the race, and when that client is also in the call,
  /// the call has to move with everyone else. It heard the server's ring (a
  /// ban) before the rotation existed, found nothing new, and would never
  /// hear this one: the socket does not echo a send to its sender.
  ///
  /// Best-effort: the thing being announced has already happened, and a
  /// doorbell nobody heard costs somebody a wait rather than correctness.
  ///
  /// [channels] names where keys were just sealed, for a ring that announces
  /// them; left out, or more than [BroadcastPayload.maxNamedChannels], the
  /// ring asks everybody to look.
  void ring({Iterable<String>? channels}) {
    final names = channels?.toSet();
    final payload =
        names == null ||
            names.isEmpty ||
            names.length > BroadcastPayload.maxNamedChannels
        ? const <String, dynamic>{}
        : {'channels': names.toList()};
    _lease
      ?..send(ServerEvent.sweep, payload)
      ..echoLocally(ServerEvent.sweep, payload);
  }

  /// Stop listening.
  ///
  /// The field is cleared before the await so a `stop` racing a `listen`
  /// cannot release the new subscription instead of the old one.
  Future<void> stop() async {
    final lease = _lease;
    _lease = null;
    _throttle?.cancel();
    _throttle = null;
    await lease?.release();
  }
}
